//! Frozen independent translation of original Swift policy hash26f5f347...;
//! ordinary f64 storage and separate transition methods, not the Rust decoder/reducer.
//! Candidate0-at-mint is the separately reviewed fail-closed ABI extension.
use beluga_core::youtube_handoff_operation::{initial, step, Event, Evidence, Request, Result, State, ABI};
use std::mem::{align_of, offset_of, size_of};

fn b(value: f64) -> u64 { value.to_bits() }
fn n(value: u64) -> f64 { f64::from_bits(value) }
#[derive(Clone, Copy)]
struct RefEvidence { token: u64, position: f64, rate: f64, observed: f64 }
#[derive(Clone)]
struct Reference {
    request: Request, phase: u32, failure: u32, mac: u32, visible: bool, ever: bool,
    ready: bool, last: f64, sequence: u32, first: Option<(f64, f64)>,
    latest: Option<f64>, latest_state: Option<i32>, proof: Option<RefEvidence>,
    revoked: bool, reply: Option<f64>,
}
impl Reference {
    fn initial(request: Request, now: f64) -> Self {
        Self { request, phase: 0, failure: 0, mac: 0, visible: false, ever: false,
            ready: false, last: now, sequence: 0, first: None, latest: None,
            latest_state: None, proof: None, revoked: false, reply: None }
    }
    fn wire(&self) -> State {
        State { abi: 1, phase: self.phase, failure: self.failure, mac_pause: self.mac,
            flags: u32::from(self.visible) | (u32::from(self.ever) << 1)
                | (u32::from(self.ready) << 2) | (u32::from(self.revoked) << 3),
            presence: u32::from(self.first.is_some()) | (u32::from(self.latest.is_some()) << 1)
                | (u32::from(self.latest_state.is_some()) << 2) | (u32::from(self.proof.is_some()) << 3)
                | (u32::from(self.reply.is_some()) << 4),
            sequence: self.sequence, reserved: 0, request: self.request, last_now: self.last.to_bits(),
            first_position: self.first.map(|x| x.0.to_bits()).unwrap_or(0), first_at: self.first.map(|x| x.1.to_bits()).unwrap_or(0),
            latest_playing_at: self.latest.map(f64::to_bits).unwrap_or(0), latest_state: self.latest_state.unwrap_or(0),
            latest_state_reserved: 0, evidence: self.proof.map(|x| Evidence { token: x.token,
                position: x.position.to_bits(), rate: x.rate.to_bits(), observed_at: x.observed.to_bits() }).unwrap_or_default(),
            reply_deadline: self.reply.map(f64::to_bits).unwrap_or(0) }
    }
    fn failure(&mut self, reason: u32) -> (u32, u32) {
        if self.phase == 7 { return (0, 0); }
        if self.mac == 1 { self.mac = 4; }
        self.reply = None; self.revoked = true; self.phase = 7; self.failure = reason;
        self.visible = false; self.first = None; self.latest = None; self.latest_state = None;
        (4, reason)
    }
    fn observe(&mut self, now: f64) -> Option<u32> {
        if self.phase == 7 { return None; }
        if !(now.is_finite() && now >= self.last) { return Some(9); }
        self.last = now;
        if let Some(reply) = self.reply { if now >= reply { return Some(14); } }
        if self.phase != 6 && now >= n(self.request.deadline) { return Some(2); }
        None
    }
    fn expected(&self, now: f64) -> f64 {
        let elapsed = now - n(self.request.position_observed_at);
        let nonnegative = if elapsed >= 0.0 { elapsed } else { 0.0 };
        let position = n(self.request.position) + nonnegative * n(self.request.rate);
        if position < n(self.request.duration) { position } else { n(self.request.duration) }
    }
    fn current(&mut self, event: Event) -> bool {
        let now = n(event.now);
        if let Some(failure) = self.observe(now) { let _ = self.failure(failure); }
        if self.phase == 7 || !matches!(self.mac, 0 | 1) || !self.visible || self.revoked
            || event.flags != 16 || now >= n(self.request.deadline) { return false; }
        let Some(proof) = self.proof else { return false; };
        if event.proof_token != proof.token || now < proof.observed || now - proof.observed > 0.75
            || self.latest_state != Some(1) { return false; }
        let Some(latest) = self.latest else { return false; };
        now >= latest && now - latest <= 0.75
    }
    fn receive(&mut self, event: Event) -> (u32, u32) {
        let now = n(event.now);
        if event.flags & 6 != 6 { return (0, 0); }
        if let Some(failure) = self.observe(now) { return self.failure(failure); }
        if self.phase == 7 || event.sequence <= self.sequence { return (0, 0); }
        self.sequence = event.sequence;
        if event.flags & 8 == 0 { return self.failure(7); }
        if self.phase == 6 {
            return match event.kind { 3 => self.failure(6), 4 => self.failure(10),
                1 => (1, 0), 0 | 2 => (0, 0), _ => unreachable!() };
        }
        match event.kind {
            3 => return self.failure(6), 4 => return self.failure(10),
            0 => { self.ready = true; if self.proof.is_none() { self.phase = 1; } },
            1 => {
                self.first = None; self.latest = None; self.latest_state = None;
                if self.proof.is_some() { self.revoked = true; }
                if self.mac == 1 { return self.failure(12); }
                if self.proof.is_none() { self.phase = 2; }
                return (1, 0);
            },
            2 => {
                if !self.visible || !self.ready || event.presence != 15 { return (0, 0); }
                let (position, duration, rate) = (n(event.sample_position), n(event.sample_duration), n(event.sample_rate));
                self.latest_state = Some(event.sample_state);
                let ratio = n(self.request.duration) * 0.002;
                let tolerance = if ratio >= 1.0 { ratio } else { 1.0 };
                if !(event.sample_state == 1 && (duration - n(self.request.duration)).abs() <= tolerance
                    && (rate - n(self.request.rate)).abs() <= 0.01 && position <= duration) {
                    self.first = None; self.latest = None;
                    if self.proof.is_some() { self.revoked = true; }
                    if self.mac == 1 { return self.failure(12); }
                    if self.proof.is_none() { self.phase = 1; }
                    return (0, 0);
                }
                if let Some(proof) = self.proof {
                    if (position - (proof.position + (now - proof.observed) * rate)).abs() > 2.0 {
                        return self.failure(11);
                    }
                }
                self.latest = Some(now);
                if self.proof.is_some() { return (0, 0); }
                let Some((first_position, first_now)) = self.first else {
                    if (position - self.expected(now)).abs() <= 2.0 {
                        self.first = Some((position, now)); self.phase = 3;
                    }
                    return (0, 0);
                };
                let elapsed = now - first_now; let advance = position - first_position;
                if !(elapsed <= 1.5 && (position - self.expected(now)).abs() <= 2.0) {
                    self.first = None; self.phase = 1; return (0, 0);
                }
                let ratio = elapsed * rate * 0.5;
                let tolerance = if ratio >= 0.15 { ratio } else { 0.15 };
                if !(elapsed >= 0.2 && advance > 0.02 && (advance - elapsed * rate).abs() <= tolerance) { return (0, 0); }
                // New raw-ABI exhaustion rule is not an original Swift UUID failure path.
                if event.candidate_token == 0 { return self.failure(8); }
                self.proof = Some(RefEvidence { token: event.candidate_token, position, rate, observed: now });
                self.phase = 4; return (2, 0);
            },
            _ => unreachable!(),
        }
        (0, 0)
    }
    fn run(&mut self, event: Event) -> Result {
        let mut outcome = (0, 0); let mut accepted = false; let now = n(event.now);
        match event.opcode {
            0 => {
                if let Some(failure) = self.observe(now) { outcome = self.failure(failure); }
                else if self.phase != 7 {
                    self.visible = event.flags == 1;
                    if self.visible { self.ever = true; }
                    else { self.first = None; self.latest = None; if self.ever { outcome = self.failure(3); } }
                }
            },
            1 => if let Some(failure) = self.observe(now) { outcome = self.failure(failure); },
            2 => outcome = self.receive(event),
            3 => accepted = self.current(event),
            4 => {
                if self.mac == 0 && self.current(event) {
                    self.mac = 1;
                    let timeout = now + 3.0;
                    self.reply = Some(if timeout < n(self.request.deadline) { timeout } else { n(self.request.deadline) });
                    self.phase = 5; accepted = true;
                }
            },
            5 => {
                if event.flags == 32 && self.mac == 1 {
                    if let Some(failure) = self.observe(now) { outcome = self.failure(failure); }
                    else {
                        self.reply = None;
                        match event.completion {
                            1 => {
                                self.mac = 2;
                                if !(self.visible && !self.revoked && self.latest_state == Some(1)
                                    && self.latest.map(|last| now >= last && now - last <= 0.75).unwrap_or(false)) {
                                    outcome = self.failure(12);
                                } else {
                                    self.revoked = true; self.proof = None; self.first = None;
                                    self.phase = 6; outcome = (3, 0);
                                }
                            },
                            2 => { self.mac = 3; outcome = self.failure(13); },
                            3 => { self.mac = 4; outcome = self.failure(14); },
                            _ => unreachable!(),
                        }
                    }
                }
            },
            6 => outcome = self.failure(event.failure),
            _ => unreachable!(),
        }
        Result { state: self.wire(), status: 0, event: outcome.0, accepted: u32::from(accepted), failure: outcome.1 }
    }
}

fn request() -> Request { Request { position: b(20.0), duration: b(200.0), rate: b(1.0),
    deadline: b(40.0), position_observed_at: b(10.0) } }
fn pair() -> (State, Reference) { let request = request(); (initial(request, b(10.0)), Reference::initial(request, 10.0)) }
fn assert_step(state: &mut State, reference: &mut Reference, event: Event) -> Result {
    let expected = reference.run(event); let actual = step(ABI, *state, event);
    assert_eq!(actual, expected, "event={event:?}"); *state = actual.state;
    // Every emitted valid state must round-trip without loss through the copied decoder.
    let ignored = Event { opcode: 2, sequence: 1, now: b(f64::INFINITY), ..Event::default() };
    let roundtrip = step(ABI, *state, ignored);
    assert_eq!(roundtrip, Result { state: *state, status: 0, event: 0, accepted: 0, failure: 0 });
    actual
}
fn event(opcode: u32, now: f64) -> Event { Event { opcode, now: b(now), ..Event::default() } }
fn message(sequence: u32, kind: u32, position: f64, state: i32, now: f64) -> Event {
    Event { opcode: 2, flags: 14, sequence, kind, now: b(now), candidate_token: 100,
        presence: if kind == 2 { 15 } else { 0 }, sample_state: if kind == 2 { state } else { 0 },
        sample_position: if kind == 2 { b(position) } else { 0 },
        sample_duration: if kind == 2 { b(200.0) } else { 0 }, sample_rate: if kind == 2 { b(1.0) } else { 0 },
        ..Event::default() }
}
fn visible(state: &mut State, reference: &mut Reference) { let mut e = event(0, 10.0); e.flags = 1; assert_step(state, reference, e); }
fn confirm(state: &mut State, reference: &mut Reference) {
    visible(state, reference); assert_step(state, reference, message(1, 0, 20.0, 1, 10.0));
    assert_step(state, reference, message(2, 2, 20.0, 1, 10.1));
    assert_eq!(assert_step(state, reference, message(3, 2, 20.3, 1, 10.4)).event, 2);
}
fn proof_event(opcode: u32, now: f64, token: u64) -> Event { Event { flags: 16, proof_token: token, ..event(opcode, now) } }
fn pending(state: &mut State, reference: &mut Reference) {
    confirm(state, reference); let token = state.evidence.token;
    assert_eq!(assert_step(state, reference, proof_event(4, 10.5, token)).accepted, 1);
}
fn completion(result: u32, now: f64) -> Event { Event { flags: 32, completion: result, ..event(5, now) } }
fn failure(reason: u32) -> Event { Event { opcode: 6, failure: reason, ..Event::default() } }
fn invalid(abi: u32, state: State, event: Event) {
    assert_eq!(step(abi, state, event), Result { state, status: 3, event: 0, accepted: 0, failure: 0 });
}

#[test]
fn copied_abi_layout_is_exact_and_pointer_free() {
    assert_eq!((size_of::<Request>(), align_of::<Request>()), (40, 8));
    assert_eq!((size_of::<Evidence>(), align_of::<Evidence>()), (32, 8));
    assert_eq!((size_of::<State>(), align_of::<State>()), (152, 8));
    assert_eq!((size_of::<Event>(), align_of::<Event>()), (80, 8));
    assert_eq!((size_of::<Result>(), align_of::<Result>()), (168, 8));
    assert_eq!(offset_of!(State, request), 32); assert_eq!(offset_of!(State, last_now), 72);
    assert_eq!(offset_of!(State, latest_state), 104); assert_eq!(offset_of!(State, evidence), 112);
    assert_eq!(offset_of!(State, reply_deadline), 144); assert_eq!(offset_of!(Event, now), 32);
    assert_eq!(offset_of!(Event, candidate_token), 48); assert_eq!(offset_of!(Result, status), 152);
}
#[test]
fn ready_stationary_paused_and_wrong_position_do_not_confirm() {
    for (position, state_value) in [(20.0, 1), (20.3, 2), (80.3, 1)] {
        let (mut state, mut reference) = pair(); visible(&mut state, &mut reference);
        assert_step(&mut state, &mut reference, message(1, 0, position, state_value, 10.0));
        assert_step(&mut state, &mut reference, message(2, 2, position, state_value, 10.1));
        assert_step(&mut state, &mut reference, message(3, 2, position, state_value, 10.4));
        assert_eq!(state.evidence, Evidence::default());
    }
}
#[test]
fn slow_provider_requires_the_advancing_original_request_timeline() {
    for follows in [false, true] {
        let (mut state, mut reference) = pair(); visible(&mut state, &mut reference);
        assert_step(&mut state, &mut reference, message(1, 0, 20.0, 1, 18.0));
        assert_step(&mut state, &mut reference, message(2, 2, if follows { 28.1 } else { 20.0 }, 1, 18.1));
        assert_step(&mut state, &mut reference, message(3, 2, if follows { 28.4 } else { 20.3 }, 1, 18.4));
        assert_eq!(state.evidence.token != 0, follows);
    }
}
#[test]
fn advancing_exact_visible_playback_confirms_once_without_refreshing_proof() {
    let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference); let owned = state.evidence;
    assert_step(&mut state, &mut reference, message(4, 2, 20.5, 1, 10.6));
    assert_eq!(state.evidence, owned);
    assert_eq!(assert_step(&mut state, &mut reference, proof_event(3, 10.6, owned.token)).accepted, 1);
}
#[test]
fn blocked_provider_requests_play_but_never_claims_confirmation() {
    let (mut state, mut reference) = pair(); visible(&mut state, &mut reference);
    assert_step(&mut state, &mut reference, message(1, 0, 20.0, 1, 10.0));
    assert_eq!(assert_step(&mut state, &mut reference, message(2, 1, 20.0, 1, 10.1)).event, 1);
    assert_eq!(state.phase, 2); assert_eq!(state.evidence.token, 0);
    assert_step(&mut state, &mut reference, message(3, 2, 20.0, 1, 11.0));
    assert_eq!(assert_step(&mut state, &mut reference, message(4, 2, 20.3, 1, 11.3)).event, 2);
}
#[test]
fn hidden_once_visible_and_every_terminal_failure_cannot_revive() {
    let (mut state, mut reference) = pair(); assert_step(&mut state, &mut reference, event(0, 10.0));
    assert_eq!(state.phase, 0); confirm(&mut state, &mut reference); let proof = state.evidence;
    assert_eq!(assert_step(&mut state, &mut reference, event(0, 10.5)).failure, 3);
    assert_eq!(state.evidence, proof); assert_eq!(state.flags & 8, 8);
    let before = state;
    for reason in 1..=14 { assert_step(&mut state, &mut reference, failure(reason)); }
    let mut e = event(0, 11.0); e.flags = 1; assert_step(&mut state, &mut reference, e);
    assert_step(&mut state, &mut reference, message(u32::MAX, 2, 20.8, 1, 11.0));
    assert_eq!(state, before);
}
#[test]
fn foreign_identity_returns_before_time_but_matching_replay_observes_time() {
    for flags in [10, 12] {
        let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference); let before = state;
        let mut e = message(99, 3, 0.0, 0, f64::INFINITY); e.flags = flags;
        assert_step(&mut state, &mut reference, e); assert_eq!(state, before);
        assert_eq!(assert_step(&mut state, &mut reference, message(1, 0, 0.0, 0, 40.0)).failure, 2);
    }
}
#[test]
fn wrong_video_burns_matching_sequence_before_terminal_failure() {
    let (mut state, mut reference) = pair(); visible(&mut state, &mut reference);
    let mut e = message(100, 0, 20.0, 1, 10.1); e.flags = 6;
    assert_eq!(assert_step(&mut state, &mut reference, e).failure, 7); assert_eq!(state.sequence, 100);
    let before = state; assert_step(&mut state, &mut reference, message(101, 2, 20.3, 1, 10.4)); assert_eq!(state, before);
}
#[test]
fn original_proof_age_never_renews_but_completion_uses_latest_sample() {
    let (mut state, mut reference) = pair(); pending(&mut state, &mut reference); let original = state.evidence;
    assert_step(&mut state, &mut reference, message(4, 2, 21.3, 1, 11.4));
    assert_eq!(assert_step(&mut state, &mut reference, proof_event(3, 11.4, original.token)).accepted, 0);
    assert_eq!(state.evidence, original);
    assert_eq!(assert_step(&mut state, &mut reference, completion(1, 11.5)).event, 3);
    assert_eq!(state.mac_pause, 2); assert_eq!(state.evidence, Evidence::default());
}
#[test]
fn interruption_or_seek_cannot_revive_previously_confirmed_authority() {
    for variant in 0..6 {
        let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference); let owned = state.evidence;
        let mut e = message(4, if variant == 0 { 1 } else { 2 }, if variant == 3 { 80.0 } else { 20.4 },
            if variant == 1 { 2 } else if variant == 2 { 3 } else { 1 }, 10.5);
        if variant == 4 { e.sample_duration = b(100.0); } if variant == 5 { e.sample_rate = b(2.0); }
        assert_step(&mut state, &mut reference, e);
        assert_eq!(assert_step(&mut state, &mut reference, proof_event(3, 10.5, owned.token)).accepted, 0);
        assert_step(&mut state, &mut reference, message(5, 2, 20.5, 1, 10.6));
        assert_eq!(assert_step(&mut state, &mut reference, proof_event(3, 10.6, owned.token)).accepted, 0);
        assert_eq!(state.evidence, owned);
    }
}
#[test]
fn clock_regression_and_nonfinite_clock_fail_without_rewriting_last_bits() {
    for now in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, 9.0] {
        let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference); let last = state.last_now;
        assert_eq!(assert_step(&mut state, &mut reference, event(1, now)).failure, 9); assert_eq!(state.last_now, last);
    }
}
#[test]
fn only_reserved_correlated_completion_moves_and_cannot_be_replayed() {
    let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference); let token = state.evidence.token;
    assert_step(&mut state, &mut reference, completion(1, f64::NAN)); assert_eq!(state.phase, 4);
    assert_eq!(assert_step(&mut state, &mut reference, proof_event(4, 10.5, token)).accepted, 1);
    let before = state;
    assert_eq!(assert_step(&mut state, &mut reference, proof_event(4, f64::NAN, token)).accepted, 0); assert_eq!(state, before);
    let mut e = completion(1, f64::INFINITY); e.flags = 0; assert_step(&mut state, &mut reference, e); assert_eq!(state, before);
    assert_eq!(assert_step(&mut state, &mut reference, completion(1, 10.6)).event, 3);
    let before = state;
    for result in 1..=3 { assert_step(&mut state, &mut reference, completion(result, f64::NAN)); }
    assert_step(&mut state, &mut reference, proof_event(4, f64::INFINITY, token)); assert_eq!(state, before);
}
#[test]
fn committed_local_controls_past_deadline_never_reopen_authority() {
    let (mut state, mut reference) = pair(); pending(&mut state, &mut reference);
    assert_eq!(assert_step(&mut state, &mut reference, completion(1, 10.6)).event, 3);
    for (index, state_value) in [2, 1, 3, 0].into_iter().enumerate() {
        let mut e = message(4 + index as u32, 2, 80.0, state_value, 60.0 + index as f64); e.sample_rate = b(2.0);
        assert_step(&mut state, &mut reference, e); assert_step(&mut state, &mut reference, event(1, n(e.now)));
        assert_eq!(state.phase, 6); assert_eq!(state.mac_pause, 2);
        assert_eq!(assert_step(&mut state, &mut reference, proof_event(3, n(e.now), 100)).accepted, 0);
    }
    let mut e = message(8, 0, 0.0, 0, 64.0); e.flags = 6;
    assert_eq!(assert_step(&mut state, &mut reference, e).failure, 7); assert_eq!(state.mac_pause, 2);
}
#[test]
fn pending_interruption_becomes_unknown_and_late_success_cannot_revive() {
    for variant in 0..6 {
        let (mut state, mut reference) = pair(); pending(&mut state, &mut reference); let owned = state.evidence;
        let mut e = message(4, if variant == 0 { 1 } else { 2 }, if variant == 3 { 80.0 } else { 20.4 },
            if variant == 1 { 2 } else if variant == 2 { 3 } else { 1 }, 10.6);
        if variant == 4 { e.sample_duration = b(100.0); } if variant == 5 { e.sample_rate = b(2.0); }
        assert_eq!(assert_step(&mut state, &mut reference, e).event, 4); assert_eq!(state.mac_pause, 4);
        assert_eq!(state.evidence, owned); assert_step(&mut state, &mut reference, completion(1, 10.7));
        assert_step(&mut state, &mut reference, message(5, 2, 20.7, 1, 10.8)); assert_eq!(state.phase, 7);
    }
}
#[test]
fn successful_native_pause_is_retained_even_when_phone_freshness_fails() {
    let (mut state, mut reference) = pair(); pending(&mut state, &mut reference); let owned = state.evidence;
    assert_eq!(assert_step(&mut state, &mut reference, completion(1, 11.5)).failure, 12);
    assert_eq!(state.mac_pause, 2); assert_eq!(state.evidence, owned); assert_eq!(state.flags & 8, 8);
}
#[test]
fn reply_timeout_precedes_offer_timeout_and_never_renews_deadline() {
    let (mut state, mut reference) = pair(); pending(&mut state, &mut reference);
    assert_step(&mut state, &mut reference, event(1, 13.49));
    assert_eq!(assert_step(&mut state, &mut reference, event(1, 13.5)).failure, 14); assert_eq!(state.mac_pause, 4);
    assert_step(&mut state, &mut reference, completion(1, 13.6));
    let req = Request { deadline: b(10.8), ..request() };
    let (mut state, mut reference) = (initial(req, b(10.0)), Reference::initial(req, 10.0));
    pending(&mut state, &mut reference); assert_eq!(state.reply_deadline, b(10.8));
    assert_eq!(assert_step(&mut state, &mut reference, event(1, 10.8)).failure, 14);
    let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference);
    assert_eq!(assert_step(&mut state, &mut reference, event(1, 40.0)).failure, 2); assert_eq!(state.mac_pause, 0);
}
#[test]
fn every_pending_failure_retains_proof_but_becomes_unknown_terminal() {
    for reason in 1..=14 {
        let (mut state, mut reference) = pair(); pending(&mut state, &mut reference); let owned = state.evidence;
        assert_eq!(assert_step(&mut state, &mut reference, failure(reason)).failure, reason);
        assert_eq!(state.mac_pause, 4); assert_eq!(state.evidence, owned);
        let before = state; assert_step(&mut state, &mut reference, completion(1, 10.6));
        assert_step(&mut state, &mut reference, proof_event(4, 10.6, 100)); assert_eq!(state, before);
    }
}
#[test]
fn rejected_and_unknown_completion_results_retain_their_honest_status() {
    for (result, mac, failure_code) in [(2, 3, 13), (3, 4, 14)] {
        let (mut state, mut reference) = pair(); pending(&mut state, &mut reference);
        assert_eq!(assert_step(&mut state, &mut reference, completion(result, 10.6)).failure, failure_code);
        assert_eq!(state.mac_pause, mac); let before = state;
        assert_step(&mut state, &mut reference, completion(1, 10.7)); assert_eq!(state, before);
    }
}
#[test]
fn whole_native_proof_equality_and_scalar_identity_are_separate_guards() {
    for matched in [false, true] {
        let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference);
        let mut e = proof_event(4, 10.5, 101);
        if !matched { e.flags = 0; e.proof_token = 0; }
        assert_eq!(assert_step(&mut state, &mut reference, e).accepted, 0); assert_eq!(state.mac_pause, 0);
    }
}
#[test]
fn initial_nonfinite_and_signed_zero_bits_are_stored_without_observation() {
    for raw in [b(0.0), b(-0.0), b(f64::INFINITY), b(f64::NEG_INFINITY), 0x7ff8_0000_0000_1234, 0xfff8_0000_0000_4321] {
        let req = request(); let (mut state, mut reference) = (initial(req, raw), Reference::initial(req, n(raw)));
        assert_eq!(state.last_now, raw); assert_eq!(state.phase, 0);
        let result = assert_step(&mut state, &mut reference, event(1, 10.0));
        if n(raw).is_nan() || n(raw) == f64::INFINITY { assert_eq!(result.failure, 9); assert_eq!(state.last_now, raw); }
        else { assert_eq!(result.event, 0); assert_eq!(state.last_now, b(10.0)); }
    }
    let req = Request { position: b(-0.0), position_observed_at: b(-0.0), deadline: b(30.0), ..request() };
    let (mut state, mut reference) = (initial(req, b(-0.0)), Reference::initial(req, -0.0));
    assert_step(&mut state, &mut reference, event(1, 0.0)); assert_eq!(state.last_now, b(0.0));
    assert_step(&mut state, &mut reference, event(1, -0.0)); assert_eq!(state.last_now, b(-0.0));
    assert_eq!(state.request.position, b(-0.0)); assert_eq!(state.request.position_observed_at, b(-0.0));
}
#[test]
fn negative_monotone_times_can_confirm_and_reserve_negative_reply_deadline() {
    let req = request(); let (mut state, mut reference) = (initial(req, b(f64::NEG_INFINITY)), Reference::initial(req, f64::NEG_INFINITY));
    let mut e = event(0, -20.0); e.flags = 1; assert_step(&mut state, &mut reference, e);
    assert_step(&mut state, &mut reference, message(1, 0, 20.0, 1, -20.0));
    assert_step(&mut state, &mut reference, message(2, 2, 20.0, 1, -19.9));
    assert_eq!(assert_step(&mut state, &mut reference, message(3, 2, 20.3, 1, -19.6)).event, 2);
    assert_eq!(state.evidence.observed_at, b(-19.6));
    assert_eq!(assert_step(&mut state, &mut reference, proof_event(4, -19.5, 100)).accepted, 1);
    assert_eq!(state.reply_deadline, b(-16.5));
    assert_eq!(assert_step(&mut state, &mut reference, completion(1, -19.4)).event, 3);
}
#[test]
fn duration_tolerance_can_confirm_evidence_beyond_original_request_duration() {
    let req = Request { position: b(199.9), ..request() };
    let (mut state, mut reference) = (initial(req, b(10.0)), Reference::initial(req, 10.0)); visible(&mut state, &mut reference);
    assert_step(&mut state, &mut reference, message(1, 0, 0.0, 0, 10.0));
    for (seq, position, now) in [(2, 200.1, 10.1), (3, 200.4, 10.4)] {
        let mut e = message(seq, 2, position, 1, now); e.sample_duration = b(200.8);
        assert_step(&mut state, &mut reference, e);
    }
    assert_eq!(state.phase, 4); assert!(n(state.evidence.position) > n(req.duration));
    assert_eq!(assert_step(&mut state, &mut reference, proof_event(3, 10.5, 100)).accepted, 1);
}
#[test]
fn sample_partial_presence_burns_sequence_but_never_processes_partial_sample() {
    for mask in 0..=15 {
        let (mut state, mut reference) = pair(); visible(&mut state, &mut reference);
        assert_step(&mut state, &mut reference, message(1, 0, 0.0, 0, 10.0));
        let mut e = message(2, 2, 20.0, 1, 10.1); e.presence = mask;
        if mask & 1 == 0 { e.sample_state = 0; } if mask & 2 == 0 { e.sample_position = 0; }
        if mask & 4 == 0 { e.sample_duration = 0; } if mask & 8 == 0 { e.sample_rate = 0; }
        assert_step(&mut state, &mut reference, e); assert_eq!(state.sequence, 2);
        assert_eq!(state.presence & 7 != 0, mask == 15); assert_eq!(state.evidence.token, 0);
    }
}
#[test]
fn candidate_zero_is_ignored_before_the_genuine_new_proof_mint_point() {
    let (mut state, mut reference) = pair();
    let mut e = message(99, 3, 0.0, 0, f64::INFINITY); e.flags = 10; e.candidate_token = 0;
    let before = state; assert_step(&mut state, &mut reference, e); assert_eq!(state, before);
    visible(&mut state, &mut reference);
    let mut e = message(1, 0, 0.0, 0, 10.0); e.candidate_token = 0; assert_step(&mut state, &mut reference, e);
    let mut e = message(2, 2, 20.0, 1, 10.1); e.candidate_token = 0; assert_step(&mut state, &mut reference, e);
    assert_eq!(state.phase, 3);
    let mut e = message(3, 2, 20.0, 1, 10.4); e.candidate_token = 0; assert_step(&mut state, &mut reference, e);
    assert_eq!(state.phase, 3); assert_eq!(state.evidence.token, 0);
    let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference); let owned = state.evidence;
    let mut e = message(4, 2, 20.5, 1, 10.6); e.candidate_token = 0; assert_step(&mut state, &mut reference, e);
    assert_eq!(state.evidence, owned); assert_eq!(state.phase, 4);
    assert_step(&mut state, &mut reference, proof_event(4, 10.6, 100)); assert_step(&mut state, &mut reference, completion(1, 10.7));
    let mut e = message(5, 2, 80.0, 2, 60.0); e.candidate_token = 0; assert_step(&mut state, &mut reference, e);
    assert_eq!(state.phase, 6);
}
#[test]
fn eligible_zero_candidate_fails_invalid_bridge_after_clock_and_sequence_burn() {
    let (mut state, mut reference) = pair(); visible(&mut state, &mut reference);
    assert_step(&mut state, &mut reference, message(1, 0, 0.0, 0, 10.0));
    assert_step(&mut state, &mut reference, message(2, 2, 20.0, 1, 10.1));
    let mut e = message(3, 2, 20.3, 1, 10.4); e.candidate_token = 0;
    let result = assert_step(&mut state, &mut reference, e); assert_eq!((result.event, result.failure), (4, 8));
    assert_eq!(state.sequence, 3); assert_eq!(state.last_now, b(10.4)); assert_eq!(state.evidence.token, 0);
    let before = state; assert_step(&mut state, &mut reference, message(4, 2, 20.6, 1, 10.7)); assert_eq!(state, before);
}
#[test]
fn maximum_candidate_is_valid_once_and_later_candidate_zero_cannot_remint() {
    let (mut state, mut reference) = pair(); visible(&mut state, &mut reference);
    assert_step(&mut state, &mut reference, message(1, 0, 0.0, 0, 10.0));
    assert_step(&mut state, &mut reference, message(2, 2, 20.0, 1, 10.1));
    let mut e = message(3, 2, 20.3, 1, 10.4); e.candidate_token = u64::MAX;
    assert_eq!(assert_step(&mut state, &mut reference, e).event, 2); assert_eq!(state.evidence.token, u64::MAX);
    let mut e = message(4, 2, 20.5, 1, 10.6); e.candidate_token = 0;
    assert_step(&mut state, &mut reference, e); assert_eq!(state.evidence.token, u64::MAX);
    assert_step(&mut state, &mut reference, failure(4));
    assert_step(&mut state, &mut reference, message(5, 2, 20.8, 1, 10.9)); assert_eq!(state.evidence.token, u64::MAX);
}
#[test]
fn raw_state_value_copies_are_independent_and_native_fact_blocks_cross_proof() {
    let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference);
    let mut other = state; let mut other_reference = reference.clone();
    assert_step(&mut state, &mut reference, failure(4)); assert_eq!(state.phase, 7);
    assert_eq!(assert_step(&mut other, &mut other_reference, proof_event(3, 10.5, 100)).accepted, 1);
    let mut e = event(3, 10.6); e.flags = 0; e.proof_token = 0;
    assert_eq!(assert_step(&mut other, &mut other_reference, e).accepted, 0); assert_eq!(other.phase, 4);
}
#[test]
fn exact_advance_elapsed_and_original_proof_age_boundaries_match_double_semantics() {
    for (elapsed, advance, expect) in [(f64::from_bits(b(0.2) - 1), 0.0201, false),
        (0.2, 0.02, false), (0.2, f64::from_bits(b(0.02) + 1), true),
        (1.5, 0.15, true), (f64::from_bits(b(1.5) + 1), 0.15, false)] {
        let req = Request { position: b(0.0), rate: b(0.1), deadline: b(30.0), position_observed_at: b(0.0), ..request() };
        let (mut state, mut reference) = (initial(req, b(0.0)), Reference::initial(req, 0.0));
        let mut e = event(0, 0.0); e.flags = 1; assert_step(&mut state, &mut reference, e);
        assert_step(&mut state, &mut reference, message(1, 0, 0.0, 0, 0.0));
        for (seq, now, position) in [(2, 0.0, 0.0), (3, elapsed, advance)] {
            let mut e = message(seq, 2, position, 1, now); e.sample_rate = b(0.1); assert_step(&mut state, &mut reference, e);
        }
        assert_eq!(state.evidence.token != 0, expect);
    }
    for (now, expect) in [(11.15, 1), (f64::from_bits(b(11.15) + 1), 0)] {
        let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference);
        assert_eq!(assert_step(&mut state, &mut reference, proof_event(3, now, 100)).accepted, expect);
    }
}
#[test]
fn is_current_silent_failure_does_not_fabricate_an_emitted_failure_event() {
    let (mut state, mut reference) = pair(); confirm(&mut state, &mut reference);
    let result = assert_step(&mut state, &mut reference, proof_event(3, 40.0, 100));
    assert_eq!((result.event, result.failure, result.accepted), (0, 0, 0));
    assert_eq!((state.phase, state.failure), (7, 2)); assert_ne!(state.evidence.token, 0);
}
#[test]
fn malformed_abi_and_every_structural_state_field_fail_byte_identically() {
    let (base, _) = pair(); invalid(0, base, event(1, 10.0)); invalid(2, base, event(1, 10.0));
    let mut cases = Vec::new();
    macro_rules! change { ($field:ident, $value:expr) => {{ let mut s = base; s.$field = $value; cases.push(s); }}; }
    change!(abi, 2); change!(phase, 8); change!(failure, 1); change!(mac_pause, 5); change!(flags, 16);
    change!(presence, 32); change!(reserved, 1); change!(latest_state_reserved, 1); change!(flags, 1);
    change!(first_position, b(-0.0)); change!(first_at, b(1.0)); change!(latest_playing_at, b(1.0));
    change!(latest_state, 1); change!(reply_deadline, b(1.0));
    for field in 0..5 { let mut s = base; match field { 0 => s.request.position = b(f64::NAN),
        1 => s.request.duration = b(0.0), 2 => s.request.rate = b(0.0),
        3 => s.request.deadline = s.request.position_observed_at, _ => s.request.position_observed_at = b(-1.0) }; cases.push(s); }
    let mut s = base; s.phase = 7; cases.push(s);
    let mut s = base; s.presence = 8; cases.push(s);
    let mut s = base; s.phase = 4; cases.push(s);
    let mut s = base; s.phase = 5; s.mac_pause = 1; cases.push(s);
    let mut s = base; s.phase = 6; s.mac_pause = 2; cases.push(s);
    let mut s = base; s.phase = 7; s.failure = 8; cases.push(s);
    let mut s = base; s.phase = 1; s.last_now = b(f64::NAN); cases.push(s);
    let mut s = base; s.presence = 4; s.latest_state = 4; cases.push(s);
    let mut s = base; s.evidence.token = 1; cases.push(s);
    for state in cases { invalid(ABI, state, event(1, f64::NAN)); }
}
#[test]
fn malformed_opcodes_domains_optional_payloads_and_primitive_fields_fail_closed() {
    let (state, _) = pair(); let base = message(1, 2, 20.0, 1, 10.1); let mut cases = Vec::new();
    macro_rules! change { ($field:ident, $value:expr) => {{ let mut e = base; e.$field = $value; cases.push(e); }}; }
    change!(opcode, 7); change!(flags, 64); change!(flags, 15); change!(presence, 16);
    change!(sequence, 0); change!(kind, 5); change!(sample_state, 4); change!(completion, 1);
    change!(failure, 1); change!(proof_token, 1); change!(sample_position, b(-1.0));
    change!(sample_duration, b(f64::INFINITY)); change!(sample_rate, b(0.0));
    let mut e = base; e.presence &= !2; e.sample_position = b(-0.0); cases.push(e);
    let mut e = base; e.presence &= !1; e.sample_state = 1; cases.push(e);
    let mut e = message(1, 0, 0.0, 0, 10.1); e.presence = 1; cases.push(e);
    let mut e = event(1, 10.1); e.sequence = 1; cases.push(e);
    let mut e = event(1, 10.1); e.candidate_token = 1; cases.push(e);
    let mut e = event(3, 10.1); e.flags = 32; cases.push(e);
    let mut e = event(3, 10.1); e.flags = 16; cases.push(e);
    let mut e = event(3, 10.1); e.proof_token = 1; cases.push(e);
    cases.push(event(5, 10.1)); cases.push(failure(0)); cases.push(failure(15));
    for event in cases { invalid(ABI, state, event); }
}
#[test]
fn deterministic_independent_traces_compare_every_raw_state_event_and_boolean() {
    let mut seed = 0x4d595df4d0f33173u64; let mut steps = 0;
    for episode in 0..600 {
        let (mut state, mut reference) = pair();
        match episode % 5 { 0 => (), 1 => visible(&mut state, &mut reference), 2 => confirm(&mut state, &mut reference),
            3 => pending(&mut state, &mut reference), _ => { pending(&mut state, &mut reference); assert_step(&mut state, &mut reference, completion(1, 10.6)); } }
        for index in 0..32 {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            let now = match (seed >> 8) % 13 { 0 => f64::NAN, 1 => f64::INFINITY, 2 => 9.0,
                3 => 40.0, _ => 10.0 + index as f64 * 0.15 };
            let e = match seed % 7 {
                0 => { let mut e = event(0, now); e.flags = u32::from(seed & 128 == 0); e },
                1 => event(1, now),
                2 => { let kind = ((seed >> 16) % 5) as u32; let states = [-1, 0, 1, 2, 3, 5];
                    let mut e = message(if seed & 2048 == 0 { index + 1 } else { u32::MAX }, kind,
                        20.0 + index as f64 * 0.15, states[((seed >> 24) % 6) as usize], now);
                    e.flags = u32::from(seed & 256 == 0) * 2 + u32::from(seed & 512 == 0) * 4 + u32::from(seed & 1024 == 0) * 8;
                    if kind == 2 && seed & 4096 != 0 { e.presence = 0; e.sample_state = 0; e.sample_position = 0; e.sample_duration = 0; e.sample_rate = 0; }
                    if seed & 8192 != 0 { e.candidate_token = 0; } e },
                3 | 4 => { let mut e = event((seed % 7) as u32, now); if seed & 16 == 0 {
                    e.flags = 16; e.proof_token = if seed & 32 == 0 { 100 } else { 101 }; } e },
                5 => { let mut e = completion(1 + ((seed >> 16) % 3) as u32, now); if seed & 64 != 0 { e.flags = 0; } e },
                _ => failure(1 + ((seed >> 32) % 14) as u32),
            };
            assert_step(&mut state, &mut reference, e); steps += 1;
        }
    }
    assert_eq!(steps, 19_200);
}
