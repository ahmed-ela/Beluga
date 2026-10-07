//! Independent test-only translation of the original Swift ownership reducer.
use beluga_core::handoff_offers::{ABI, Event, State, Result, TimelineWire, Envelope, Primary, Source, Decision,
    PRIMARY_FLAGS, ALL_NATIVE_MATCHES, AUTH_EQUAL, CONTEXT_EQUAL, VIDEO_EQUAL,
    RETIRE_SENT, RETIRE_RECEIVED, MINT_SENT, MINT_RECEIVED, initial, step};

fn d(raw: u64) -> f64 { f64::from_bits(raw) }
fn primary(position: f64, revision: u64) -> Primary {
    Primary { flags: PRIMARY_FLAGS, native_matches: CONTEXT_EQUAL | VIDEO_EQUAL, revision,
        position: position.to_bits(), duration: 200.0f64.to_bits(), rate: 1.0f64.to_bits() }
}
fn offer(sequence: u64, revision: u64, position: f64) -> Envelope {
    Envelope { text_valid: 1, sequence, revision, position: position.to_bits(),
        duration: 200.0f64.to_bits(), rate: 1.0f64.to_bits(), lifetime: 30.0f64.to_bits(), reserved: 0 }
}
fn event(opcode: u32, now: f64) -> Event {
    Event { opcode, token: 100, native_matches: ALL_NATIVE_MATCHES, now: now.to_bits(),
        phone_position: 20.0f64.to_bits(), phone_observed_at: now.to_bits(),
        primary: primary(20.0, 1), envelope: offer(1, 1, 20.0), ..Event::default() }
}

#[derive(Clone, Copy)]
struct RefTimeline { envelope: Envelope, token: u64, origin: f64, deadline: f64, last_observation: f64, last_position: f64 }
impl RefTimeline {
    fn new(envelope: Envelope, token: u64, now: f64) -> Self {
        Self { envelope, token, origin: now, deadline: now + d(envelope.lifetime),
            last_observation: now, last_position: d(envelope.position) }
    }
    fn observe(&mut self, p: Primary, now: f64) -> bool {
        if !(now.is_finite() && now >= self.last_observation && now < self.deadline
            && ref_matches_primary(self.envelope, p) && d(p.position) >= self.last_position) { return false; }
        let expected = d(self.envelope.position) + (now - self.origin) * d(self.envelope.rate);
        let uncertainty = 2.0 * d(self.envelope.rate) + 0.25;
        if (d(p.position) - expected).abs() <= uncertainty {
            self.last_observation = now; self.last_position = d(p.position); true
        } else { false }
    }
    fn wire(self) -> TimelineWire {
        TimelineWire { token: self.token, sequence: self.envelope.sequence, revision: self.envelope.revision,
            position: self.envelope.position, duration: self.envelope.duration, rate: self.envelope.rate,
            lifetime: self.envelope.lifetime, origin: self.origin.to_bits(), deadline: self.deadline.to_bits(),
            last_observation: self.last_observation.to_bits(), last_position: self.last_position.to_bits() }
    }
}
#[derive(Clone)]
struct Reference { next: u64, highest: u64, sent: Option<RefTimeline>, received: Option<RefTimeline>, sent_at: Option<f64>, received_at: Option<f64> }
impl Reference {
    fn new() -> Self { Self { next: 1, highest: 0, sent: None, received: None, sent_at: None, received_at: None } }
    fn wire(&self) -> State {
        State { abi: ABI, presence: u32::from(self.sent.is_some()) | (u32::from(self.received.is_some()) << 1)
                | (u32::from(self.sent_at.is_some()) << 2) | (u32::from(self.received_at.is_some()) << 3), terminal: 0, reserved: 0,
            next_sent: self.next, highest_received: self.highest,
            sent_at: self.sent_at.map(f64::to_bits).unwrap_or(0), received_at: self.received_at.map(f64::to_bits).unwrap_or(0),
            sent: self.sent.map(RefTimeline::wire).unwrap_or_default(), received: self.received.map(RefTimeline::wire).unwrap_or_default() }
    }
    fn retire_sent(&mut self, r: &mut Result) {
        if let Some(previous) = self.sent { r.effects |= RETIRE_SENT; r.retired_sent = previous.token; }
        self.sent = None;
    }
    fn retire_received(&mut self, r: &mut Result) {
        if let Some(previous) = self.received { r.effects |= RETIRE_RECEIVED; r.retired_received = previous.token; }
        self.received = None;
    }
    fn consume_received(&mut self, e: Event, r: &mut Result) -> bool {
        match self.received {
            Some(mut old) if old.token == e.token => {
                self.retire_received(r);
                e.native_matches & AUTH_EQUAL != 0 && ref_fresh(self.received_at, d(e.now))
                    && old.observe(e.primary, d(e.now))
            },
            _ => false,
        }
    }
    fn run(&mut self, e: Event) -> Result {
        let mut r = Result { state: self.wire(), status: 0, decision: 0, effects: 0,
            reserved: 0, retired_sent: 0, retired_received: 0, minted_token: 0, sequence: 0, lifetime: 0, deadline: 0 };
        let now = d(e.now);
        match e.opcode {
            0 => {
                self.sent_at = if now.is_finite() { Some(now) } else { None };
                if let Some(mut old) = self.sent {
                    if old.observe(e.primary, now) { self.sent = Some(old); }
                    else { self.retire_sent(&mut r); }
                }
            },
            1 => {
                self.received_at = if now.is_finite() { Some(now) } else { None };
                if let Some(mut old) = self.received {
                    if old.observe(e.primary, now) { self.received = Some(old); }
                    else { self.retire_received(&mut r); }
                }
            },
            2 => {
                if let Some(old) = self.sent { if now >= old.deadline { self.retire_sent(&mut r); } }
                if self.sent.is_none() && ref_fresh(self.sent_at, now) && self.next < u64::MAX
                    && ref_eligible(e.primary) && e.native_matches & CONTEXT_EQUAL != 0
                    && ref_source(e.source, e.primary, now) {
                    let proposed = Envelope { sequence: self.next, revision: e.primary.revision,
                        position: e.primary.position, duration: e.primary.duration, rate: e.primary.rate,
                        lifetime: if e.source.present == 0 { 30.0f64.to_bits() } else {
                            let remainder = d(e.source.deadline) - now;
                            (if 30.0 < remainder { 30.0 } else { remainder }).to_bits()
                        }, text_valid: e.envelope.text_valid, reserved: 0 };
                    if ref_offer_valid(proposed) && e.token != 0 {
                        self.next += 1;
                        let old = RefTimeline::new(proposed, e.token, now); self.sent = Some(old);
                        r.decision = Decision::SentReady as u32; r.effects |= MINT_SENT;
                        r.minted_token = e.token; r.sequence = proposed.sequence; r.lifetime = proposed.lifetime; r.deadline = old.deadline.to_bits();
                    }
                }
            },
            3 => if self.sent.map(|x| x.token == e.token).unwrap_or(false) { self.retire_sent(&mut r); },
            4 => if let Some(mut old) = self.sent {
                if ref_commit_valid(e.envelope, d(e.phone_position)) && e.native_matches == ALL_NATIVE_MATCHES
                    && e.envelope.sequence == old.envelope.sequence && d(e.envelope.duration) == d(old.envelope.duration)
                    && d(e.envelope.rate) == d(old.envelope.rate) {
                    self.retire_sent(&mut r);
                    if ref_fresh(self.sent_at, now) && old.observe(e.primary, now) {
                        let expected = d(old.envelope.position) + (now - old.origin) * d(old.envelope.rate);
                        if (d(e.phone_position) - expected).abs() <= 2.0 + 2.0 * d(old.envelope.rate) {
                            r.decision = Decision::SentConsumed as u32; r.deadline = old.deadline.to_bits();
                        }
                    }
                }
            },
            5 => if ref_offer_valid(e.envelope) && e.native_matches & AUTH_EQUAL != 0 && e.envelope.sequence > self.highest {
                self.highest = e.envelope.sequence; self.retire_received(&mut r);
                if ref_fresh(self.received_at, now) && e.envelope.revision == e.primary.revision
                    && ref_matches_primary(e.envelope, e.primary)
                    && d(e.primary.position) == d(e.envelope.position) && e.token != 0 {
                    let old = RefTimeline::new(e.envelope, e.token, now); self.received = Some(old);
                    r.decision = Decision::ReceivedReady as u32; r.effects |= MINT_RECEIVED;
                    r.minted_token = e.token; r.sequence = e.envelope.sequence; r.lifetime = e.envelope.lifetime; r.deadline = old.deadline.to_bits();
                }
            },
            6 => if self.consume_received(e, &mut r) { r.decision = Decision::ReceivedConsumed as u32; },
            7 => if ref_commit_valid(e.envelope, d(e.phone_position)) && now.is_finite() && d(e.phone_observed_at).is_finite()
                && now >= d(e.phone_observed_at) && now - d(e.phone_observed_at) <= 0.75 {
                if self.consume_received(e, &mut r) { r.decision = Decision::CommitReady as u32; }
            },
            8 => if self.received.map(|x| x.token == e.token).unwrap_or(false) { self.retire_received(&mut r); },
            9 => { self.retire_sent(&mut r); self.retire_received(&mut r); self.sent_at = None; self.received_at = None; },
            // No original Swift entry point exists for an unknown opcode. The
            // copied FFI rejects it explicitly without normal operation effects.
            _ => r.status = 3,
        }
        r.state = self.wire(); r
    }
}
fn ref_fresh(observed: Option<f64>, now: f64) -> bool {
    match observed { Some(at) if at.is_finite() && now.is_finite() => { let age = now - at; age >= 0.0 && age < 2.0 }, _ => false }
}
fn ref_eligible(p: Primary) -> bool {
    p.flags == PRIMARY_FLAGS && d(p.rate) > 0.0 && d(p.position).is_finite() && d(p.duration).is_finite()
        && d(p.duration) > 0.0 && d(p.position) >= 0.0 && d(p.position) < d(p.duration)
}
fn ref_matches_primary(e: Envelope, p: Primary) -> bool {
    ref_eligible(p) && p.native_matches == CONTEXT_EQUAL | VIDEO_EQUAL
        && d(p.duration) == d(e.duration) && d(p.rate) == d(e.rate) && p.revision >= e.revision
}
fn ref_offer_valid(e: Envelope) -> bool {
    e.sequence > 0 && e.revision > 0 && e.text_valid == 1 && d(e.position).is_finite() && d(e.position) >= 0.0
        && d(e.duration).is_finite() && d(e.duration) > 0.0 && d(e.duration) <= 31_536_000.0 && d(e.position) < d(e.duration)
        && d(e.rate).is_finite() && d(e.rate) > 0.0 && d(e.rate) <= 16.0
        && d(e.lifetime).is_finite() && d(e.lifetime) > 0.0 && d(e.lifetime) <= 30.0
}
fn ref_commit_valid(e: Envelope, phone: f64) -> bool {
    e.sequence > 0 && e.text_valid == 1 && d(e.duration).is_finite() && d(e.duration) > 0.0 && d(e.duration) <= 31_536_000.0
        && phone.is_finite() && phone >= 0.0 && phone < d(e.duration) && d(e.rate).is_finite() && d(e.rate) > 0.0 && d(e.rate) <= 16.0
}
fn ref_source(s: Source, p: Primary, now: f64) -> bool {
    if s.present == 0 { return true; }
    let age = now - d(s.observed_at);
    if !(age.is_finite() && age >= 0.0 && age < 2.0 && d(s.observed_at) >= 0.0
        && d(s.deadline).is_finite() && d(s.deadline) > now && d(s.deadline) - d(s.observed_at) <= 30.0
        && d(s.position).is_finite() && d(s.position) >= 0.0 && d(s.position) < d(s.duration)
        && d(s.duration).is_finite() && d(s.duration) <= 31_536_000.0 && d(s.rate).is_finite() && d(s.rate) > 0.0
        && d(s.rate) <= 16.0 && s.video_equal == 1 && d(p.duration) == d(s.duration) && d(p.rate) == d(s.rate)) { return false; }
    (d(p.position) - (d(s.position) + age * d(s.rate))).abs() <= 2.0 * d(s.rate) + 0.25
}
fn assert_step(reference: &mut Reference, state: &mut State, e: Event) -> Result {
    let expected = reference.run(e); let actual = step(ABI, *state, e);
    assert_eq!(actual, expected, "opcode={} now={:?}", e.opcode, d(e.now)); *state = actual.state; actual
}
fn issued_pair() -> (Reference, State) {
    let mut r = Reference::new(); let mut s = initial();
    for opcode in [0, 1, 2, 5] { assert_step(&mut r, &mut s, event(opcode, 10.0)); }
    assert_eq!(s.presence & 3, 3); (r, s)
}

#[test]
fn independent_slots_preserve_other_owner() {
    for opcode in [0, 1, 3, 8] {
        let (mut r, mut s) = issued_pair(); let before = s;
        let mut e = event(opcode, 10.1); e.primary.flags &= !16;
        assert_step(&mut r, &mut s, e);
        if opcode == 0 || opcode == 3 { assert_eq!(s.received, before.received); }
        else { assert_eq!(s.sent, before.sent); }
    }
}
#[test]
fn rejected_new_sequence_burns_and_retires_before_late_validation() {
    for now in [12.0, f64::NAN, f64::INFINITY, 9.0] {
        let (mut r, mut s) = issued_pair(); let mut e = event(5, now); e.envelope.sequence = 2; e.token = 101;
        let out = assert_step(&mut r, &mut s, e);
        assert_eq!(out.retired_received, 100); assert_eq!(s.highest_received, 2); assert_eq!(s.presence & 2, 0);
        assert_step(&mut r, &mut s, event(1, 12.0));
        let out = assert_step(&mut r, &mut s, e); assert_eq!(out.decision, 0);
    }
}
#[test]
fn matching_consumption_cannot_revive_after_late_failure() {
    for opcode in [4, 6] {
        for now in [9.0, 12.0, 40.0, f64::NAN] {
            let (mut r, mut s) = issued_pair();
            let out = assert_step(&mut r, &mut s, event(opcode, now)); assert_eq!(out.decision, 0);
            assert!(out.retired_sent == 100 || out.retired_received == 100);
            let out = assert_step(&mut r, &mut s, event(opcode, 10.1)); assert_eq!(out.decision, 0);
        }
    }
}
#[test]
fn wrong_identity_and_invalid_phone_observation_do_not_consume() {
    for opcode in [3, 6, 8] {
        let (mut r, mut s) = issued_pair(); let before = s; let mut e = event(opcode, 10.1); e.token = 101;
        assert_step(&mut r, &mut s, e); assert_eq!(s, before);
    }
    for observed in [9.0, 11.0, f64::NAN] {
        let (mut r, mut s) = issued_pair(); let before = s; let mut e = event(7, 10.0); e.phone_observed_at = observed.to_bits();
        assert_step(&mut r, &mut s, e); assert_eq!(s, before);
        let accepted = assert_step(&mut r, &mut s, event(7, 10.0)); assert_eq!(accepted.decision, Decision::CommitReady as u32);
    }
}
#[test]
fn exact_freshness_sample_deadline_and_uncertainty_boundaries() {
    for age in [0.0f64, 0.75, f64::from_bits(0.75f64.to_bits() + 1), 1.999999999, 2.0] {
        let (mut r, mut s) = issued_pair(); let mut e = event(7, 10.0); e.phone_observed_at = (10.0 - age).to_bits();
        assert_step(&mut r, &mut s, e);
    }
    for position in [22.25f64, f64::from_bits(22.25f64.to_bits() + 1), 19.999, 200.0, f64::NAN] {
        let (mut r, mut s) = issued_pair(); let mut e = event(0, 10.0); e.primary.position = position.to_bits(); assert_step(&mut r, &mut s, e);
    }
    let (mut r, mut s) = issued_pair(); let mut e = event(2, f64::INFINITY);
    let out = assert_step(&mut r, &mut s, e); assert_eq!(out.retired_sent, 100); assert_eq!(out.decision, 0);
    e.now = f64::NAN.to_bits(); assert_step(&mut r, &mut s, e);
}
#[test]
fn clear_preserves_counters_and_send_capacity_cannot_wrap() {
    let (mut r, mut s) = issued_pair(); assert_step(&mut r, &mut s, event(9, 11.0));
    assert_eq!((s.next_sent, s.highest_received, s.presence), (2, 1, 0));
    assert_step(&mut r, &mut s, event(0, 12.0));
    r.next = u64::MAX - 1; s.next_sent = r.next;
    let out = assert_step(&mut r, &mut s, event(2, 12.0)); assert_eq!(out.sequence, u64::MAX - 1); assert_eq!(s.next_sent, u64::MAX);
    assert_step(&mut r, &mut s, event(9, 12.0)); assert_step(&mut r, &mut s, event(0, 12.0));
    assert_eq!(assert_step(&mut r, &mut s, event(2, 12.0)).decision, 0);
    assert_eq!(initial().next_sent, 1); assert_eq!(initial().highest_received, 0);
}
#[test]
fn source_description_numeric_crosscheck_matches_reference() {
    for observed in [8.0f64, 9.0, 10.0, f64::NAN] {
        for deadline in [10.0f64, 39.0, 40.0, 41.0, f64::INFINITY] {
            let mut r = Reference::new(); let mut s = initial(); assert_step(&mut r, &mut s, event(0, 10.0));
            let mut e = event(2, 10.0); e.source = Source { present: 1, video_equal: 1,
                position: 19.0f64.to_bits(), duration: 200.0f64.to_bits(), rate: 1.0f64.to_bits(),
                observed_at: observed.to_bits(), deadline: deadline.to_bits() };
            assert_step(&mut r, &mut s, e);
        }
    }
}
#[test]
fn raw_float_bits_preserve_signed_zero_and_extreme_derived_deadline() {
    for now in [-0.0f64, 0.0, -10.0, f64::MAX] {
        let mut r = Reference::new(); let mut s = initial(); let mut e = event(0, now); e.primary = primary(-0.0, 1);
        assert_step(&mut r, &mut s, e); e.opcode = 2; assert_step(&mut r, &mut s, e);
        e.opcode = 0; e.primary.position = 0.0f64.to_bits(); assert_step(&mut r, &mut s, e);
    }
}
#[test]
fn bounded_deterministic_original_reference_trace_matches_all_projections() {
    let mut r = Reference::new(); let mut s = initial(); let mut random = 731u64;
    let times = [10.0f64, 10.1, 11.0, 12.0, 40.0, 9.0, f64::NAN, f64::INFINITY, -0.0];
    for ordinal in 0..10_000u64 {
        random = random.wrapping_mul(6364136223846793005).wrapping_add(1);
        let mut e = event((random % 11) as u32, times[(random as usize >> 8) % times.len()]);
        e.token = if random & 32 != 0 { 100 } else { ordinal + 101 };
        e.envelope.sequence = random % 8; e.envelope.revision = random % 3;
        e.primary.revision = random % 4; e.primary.position = [20.0f64, 21.0, 80.0, -0.0][(random as usize >> 16) % 4].to_bits();
        e.native_matches = (random >> 20) & 15;
        e.primary.native_matches = ((random >> 30) & 3) << 2;
        if random & 64 == 0 { e.primary.flags &= !16; }
        assert_step(&mut r, &mut s, e);
    }
}
#[test]
fn malformed_abi_state_and_unknown_flags_fail_closed_without_native_authority() {
    let (_, s) = issued_pair(); let closed = step(9, s, event(2, 10.0));
    assert_eq!(closed.status, 3); assert_eq!(closed.state.terminal, 1);
    assert_eq!(closed.effects, RETIRE_SENT | RETIRE_RECEIVED);
    let again = step(ABI, closed.state, event(2, 10.0)); assert_eq!(again.state, closed.state); assert_eq!(again.decision, 0);
    let mut e = event(5, 10.0); e.native_matches |= 1 << 63;
    let out = step(ABI, s, e); assert_eq!(out.status, 3); assert_eq!(out.state, s); assert_eq!(out.effects, 0);
    assert_eq!(core::mem::size_of::<State>(), 224); assert_eq!(core::mem::size_of::<Event>(), 200); assert_eq!(core::mem::size_of::<Result>(), 288);
}

#[test]
fn commit_header_and_current_primary_identity_are_independent() {
    let (mut r, mut s) = issued_pair();
    let mut source_changed = event(4, 10.1); source_changed.primary.native_matches &= !CONTEXT_EQUAL;
    let out = assert_step(&mut r, &mut s, source_changed);
    assert_eq!(out.retired_sent, 100); assert_eq!(out.decision, 0);
    assert_step(&mut r, &mut s, event(0, 10.2));
    let retried = assert_step(&mut r, &mut s, event(4, 10.2)); assert_eq!(retried.decision, 0);
    let (mut r, mut s) = issued_pair(); let before = s;
    let mut header_changed = event(4, 10.1); header_changed.native_matches &= !CONTEXT_EQUAL;
    let out = assert_step(&mut r, &mut s, header_changed);
    assert_eq!(out.effects, 0); assert_eq!(s, before);
}

#[test]
fn received_primary_matches_the_incoming_not_the_retired_receipt() {
    let (mut r, mut s) = issued_pair();
    let mut replacement = event(5, 10.1); replacement.envelope.sequence = 2; replacement.token = 101;
    // Current primary matches the incoming new envelope. Old binding is irrelevant.
    replacement.primary.native_matches = CONTEXT_EQUAL | VIDEO_EQUAL;
    let out = assert_step(&mut r, &mut s, replacement);
    assert_eq!(out.retired_received, 100); assert_eq!(out.minted_token, 101);
    assert_eq!(out.decision, Decision::ReceivedReady as u32);
    replacement.envelope.sequence = 3; replacement.token = 102; replacement.primary.native_matches = 0;
    let out = assert_step(&mut r, &mut s, replacement);
    assert_eq!(out.retired_received, 101); assert_eq!(out.decision, 0); assert_eq!(s.highest_received, 3);
}

#[test]
fn actual_double_adjacent_boundaries_have_expected_decisions() {
    for (observed, accepted) in [(9.25f64, true), (f64::from_bits(9.25f64.to_bits() - 1), false),
                                (f64::from_bits(9.25f64.to_bits() + 1), true)] {
        let (mut r, mut s) = issued_pair(); let mut e = event(7, 10.0); e.phone_observed_at = observed.to_bits();
        let out = assert_step(&mut r, &mut s, e); assert_eq!(out.decision != 0, accepted);
    }
    for (observed, accepted) in [(8.0f64, false), (f64::from_bits(8.0f64.to_bits() + 1), true),
                                (f64::from_bits(8.0f64.to_bits() - 1), false)] {
        let mut r = Reference::new(); let mut s = initial(); assert_step(&mut r, &mut s, event(0, observed));
        let out = assert_step(&mut r, &mut s, event(2, 10.0)); assert_eq!(out.decision != 0, accepted);
    }
    for (phone, accepted) in [(24.0f64, true), (f64::from_bits(24.0f64.to_bits() + 1), false)] {
        let (mut r, mut s) = issued_pair(); let mut e = event(4, 10.0); e.phone_position = phone.to_bits();
        let out = assert_step(&mut r, &mut s, e); assert_eq!(out.decision != 0, accepted); assert_eq!(out.retired_sent, 100);
    }
    for (now, accepted) in [(f64::from_bits(40.0f64.to_bits() - 1), true), (40.0f64, false)] {
        let (mut r, mut s) = issued_pair(); let mut observed = event(0, 39.0); observed.primary.position = 49.0f64.to_bits();
        assert_step(&mut r, &mut s, observed);
        let mut e = event(4, now); e.primary.position = 50.0f64.to_bits(); e.phone_position = 50.0f64.to_bits();
        let out = assert_step(&mut r, &mut s, e); assert_eq!(out.decision != 0, accepted); assert_eq!(out.retired_sent, 100);
    }
}

#[test]
fn maximum_received_sequence_does_not_wrap_or_disable_independent_send() {
    let (mut r, mut s) = issued_pair(); let mut e = event(5, 10.0); e.envelope.sequence = u64::MAX; e.token = 101;
    let out = assert_step(&mut r, &mut s, e); assert_eq!(out.decision, Decision::ReceivedReady as u32);
    assert_eq!(s.highest_received, u64::MAX); let before = s;
    e.envelope.sequence = 1; assert_eq!(assert_step(&mut r, &mut s, e).decision, 0); assert_eq!(s, before);
    assert_eq!(assert_step(&mut r, &mut s, event(4, 10.0)).decision, Decision::SentConsumed as u32);
    assert_eq!(s.highest_received, u64::MAX);
}

#[test]
fn tentative_scalar_layout_sizes_alignments_and_offsets_are_explicit() {
    use core::mem::{align_of, offset_of, size_of};
    assert_eq!((size_of::<Primary>(), align_of::<Primary>()), (48, 8));
    assert_eq!(offset_of!(Primary, flags), 0);
    assert_eq!(offset_of!(Primary, native_matches), 8);
    assert_eq!(offset_of!(Primary, revision), 16);
    assert_eq!(offset_of!(Primary, position), 24);
    assert_eq!(offset_of!(Primary, duration), 32);
    assert_eq!(offset_of!(Primary, rate), 40);
    assert_eq!((size_of::<Envelope>(), align_of::<Envelope>()), (56, 8));
    assert_eq!(offset_of!(Envelope, text_valid), 0);
    assert_eq!(offset_of!(Envelope, reserved), 4);
    assert_eq!(offset_of!(Envelope, sequence), 8);
    assert_eq!(offset_of!(Envelope, revision), 16);
    assert_eq!(offset_of!(Envelope, position), 24);
    assert_eq!(offset_of!(Envelope, duration), 32);
    assert_eq!(offset_of!(Envelope, rate), 40);
    assert_eq!(offset_of!(Envelope, lifetime), 48);
    assert_eq!((size_of::<Source>(), align_of::<Source>()), (48, 8));
    assert_eq!(offset_of!(Source, present), 0);
    assert_eq!(offset_of!(Source, video_equal), 4);
    assert_eq!(offset_of!(Source, position), 8);
    assert_eq!(offset_of!(Source, duration), 16);
    assert_eq!(offset_of!(Source, rate), 24);
    assert_eq!(offset_of!(Source, observed_at), 32);
    assert_eq!(offset_of!(Source, deadline), 40);
    assert_eq!((size_of::<TimelineWire>(), align_of::<TimelineWire>()), (88, 8));
    assert_eq!(offset_of!(TimelineWire, token), 0);
    assert_eq!(offset_of!(TimelineWire, sequence), 8);
    assert_eq!(offset_of!(TimelineWire, revision), 16);
    assert_eq!(offset_of!(TimelineWire, position), 24);
    assert_eq!(offset_of!(TimelineWire, duration), 32);
    assert_eq!(offset_of!(TimelineWire, rate), 40);
    assert_eq!(offset_of!(TimelineWire, lifetime), 48);
    assert_eq!(offset_of!(TimelineWire, origin), 56);
    assert_eq!(offset_of!(TimelineWire, deadline), 64);
    assert_eq!(offset_of!(TimelineWire, last_observation), 72);
    assert_eq!(offset_of!(TimelineWire, last_position), 80);
    assert_eq!((size_of::<State>(), align_of::<State>()), (224, 8));
    assert_eq!(offset_of!(State, abi), 0);
    assert_eq!(offset_of!(State, presence), 4);
    assert_eq!(offset_of!(State, terminal), 8);
    assert_eq!(offset_of!(State, reserved), 12);
    assert_eq!(offset_of!(State, next_sent), 16);
    assert_eq!(offset_of!(State, highest_received), 24);
    assert_eq!(offset_of!(State, sent_at), 32);
    assert_eq!(offset_of!(State, received_at), 40);
    assert_eq!(offset_of!(State, sent), 48);
    assert_eq!(offset_of!(State, received), 136);
    assert_eq!((size_of::<Event>(), align_of::<Event>()), (200, 8));
    assert_eq!(offset_of!(Event, opcode), 0);
    assert_eq!(offset_of!(Event, reserved), 4);
    assert_eq!(offset_of!(Event, token), 8);
    assert_eq!(offset_of!(Event, native_matches), 16);
    assert_eq!(offset_of!(Event, now), 24);
    assert_eq!(offset_of!(Event, phone_position), 32);
    assert_eq!(offset_of!(Event, phone_observed_at), 40);
    assert_eq!(offset_of!(Event, primary), 48);
    assert_eq!(offset_of!(Event, envelope), 96);
    assert_eq!(offset_of!(Event, source), 152);
    assert_eq!((size_of::<Result>(), align_of::<Result>()), (288, 8));
    assert_eq!(offset_of!(Result, state), 0);
    assert_eq!(offset_of!(Result, status), 224);
    assert_eq!(offset_of!(Result, decision), 228);
    assert_eq!(offset_of!(Result, effects), 232);
    assert_eq!(offset_of!(Result, reserved), 236);
    assert_eq!(offset_of!(Result, retired_sent), 240);
    assert_eq!(offset_of!(Result, retired_received), 248);
    assert_eq!(offset_of!(Result, minted_token), 256);
    assert_eq!(offset_of!(Result, sequence), 264);
    assert_eq!(offset_of!(Result, lifetime), 272);
    assert_eq!(offset_of!(Result, deadline), 280);
    println!("BELUGA_CORE_OFFERS_LAYOUT_PASS Primary48 Envelope56 Source48 Timeline88 State224 Event200 Result288 align8");
}

#[test]
fn nonfinite_events_preserve_order_but_nonfinite_owned_state_is_invalid() {
    for now in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let (mut r, mut s) = issued_pair();
        let recorded = assert_step(&mut r, &mut s, event(0, now));
        assert_eq!(recorded.retired_sent, 100); assert_eq!(s.presence & 4, 0); assert_eq!(s.sent_at, 0);
        assert_step(&mut r, &mut s, event(0, -0.0));
        assert_eq!(s.sent_at, (-0.0f64).to_bits());
    }
    let (_, valid) = issued_pair();
    for malformed in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        for field in 0..4 {
            let mut s = valid;
            match field {
                0 => s.sent.origin = malformed.to_bits(),
                1 => s.sent.last_observation = malformed.to_bits(),
                2 => s.sent.last_position = malformed.to_bits(),
                _ => s.sent.deadline = malformed.to_bits(),
            }
            let out = step(ABI, s, event(0, 10.0));
            assert_eq!(out.status, 3); assert_eq!(out.state.terminal, 1);
            assert_eq!(out.effects, RETIRE_SENT | RETIRE_RECEIVED);
        }
    }
    // Bounded positive lifetime cannot overflow this finite origin. It can round
    // away entirely, which is legitimate initial state, not malformed ABI.
    assert_eq!(f64::MAX + 30.0, f64::MAX);
    let mut r = Reference::new(); let mut s = initial();
    assert_step(&mut r, &mut s, event(0, f64::MAX));
    assert_step(&mut r, &mut s, event(2, f64::MAX));
    assert_eq!(s.sent.origin, s.sent.deadline); assert_eq!(s.terminal, 0);
    let out = assert_step(&mut r, &mut s, event(0, f64::MAX));
    assert_eq!(out.status, 0); assert_eq!(out.retired_sent, 100);
}

#[test]
fn unknown_operation_is_invalid_unchanged_without_retirement_or_success() {
    let (_, state) = issued_pair();
    for opcode in [10, 11, 100, u32::MAX] {
        let e = event(opcode, f64::INFINITY);
        let out = step(ABI, state, e);
        assert_eq!(out.status, 3); assert_eq!(out.state, state);
        assert_eq!(out.decision, 0); assert_eq!(out.effects, 0);
        assert_eq!(out.retired_sent, 0); assert_eq!(out.retired_received, 0);
        assert_eq!(out.minted_token, 0); assert_eq!(out.sequence, 0);
        assert_eq!(out.lifetime, 0); assert_eq!(out.deadline, 0);
    }
}

#[test]
fn wire_authorization_and_exact_numeric_identity_guard_slots() {
    let (mut r, mut s) = issued_pair(); let before = s;
    let mut wrong_auth = event(5, 10.0); wrong_auth.envelope.sequence = 2; wrong_auth.native_matches &= !AUTH_EQUAL;
    assert_step(&mut r, &mut s, wrong_auth); assert_eq!(s, before);
    for field in 0..4 {
        let (mut r, mut s) = issued_pair(); let before = s; let mut e = event(4, 10.0);
        match field { 0 => e.envelope.sequence = 2, 1 => e.envelope.duration = 201.0f64.to_bits(),
            2 => e.envelope.rate = 2.0f64.to_bits(), _ => e.envelope.text_valid = 0 }
        assert_step(&mut r, &mut s, e); assert_eq!(s, before);
    }
}

#[test]
fn exported_offer_functions_match_safe_reducer() {
    assert_eq!(beluga_core::beluga_core_handoff_offers_initial(), initial());
    let (_, s) = issued_pair();
    for opcode in 0..12 { let e = event(opcode, 10.1);
        assert_eq!(beluga_core::beluga_core_handoff_offers_step(ABI, s, e), step(ABI, s, e)); }
}
