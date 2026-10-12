use beluga_core::{beluga_core_screen_suspension_step as step,
    beluga_core_screen_suspension_result_is_valid as verify};
use beluga_core::screen_suspension::{RawScreenSuspensionState as S,
    RawScreenSuspensionEvent as E, RawScreenSuspensionResult as R};
use std::mem::{align_of, offset_of, size_of};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Binding(u64, u64, u64);
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Notice(u64, u64);
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum NativePhase {
    Idle,
    Active(u64, Binding, Option<Notice>),
    Suspending(Notice, Binding, Option<Notice>, bool, bool),
    Suspended(Notice, Binding),
    Marker(Notice, Binding),
    MarkerPresentation(Notice, Binding),
    RealFrame(Notice, Binding),
    RealPresentation(Notice, Binding),
    Finalization(Notice, Binding),
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct OriginalOwner { next: u64, phase: NativePhase }

// Independent transcription of the frozen native enum/method algebra.
// No production transition, validation, projection, mask helper or wrapping helper is used.
impl OriginalOwner {
    fn from_raw(s: S) -> Self {
        let b = Binding(s.peer_generation, s.visibility_epoch, s.recovery_epoch);
        let n = Notice(s.screen_request_id, s.suspension_generation);
        let phase = match s.phase {
            0 => NativePhase::Idle,
            1 => NativePhase::Active(s.screen_request_id, b,
                if s.suspension_generation == 0 { None } else { Some(n) }),
            2 => NativePhase::Suspending(n, b,
                if s.prior_suspension_generation == 0 { None }
                else { Some(Notice(s.prior_screen_request_id, s.prior_suspension_generation)) },
                s.cover_confirmed == 1, s.inactive_confirmed == 1),
            3 => NativePhase::Suspended(n, b),
            4 => NativePhase::Marker(n, b),
            5 => NativePhase::MarkerPresentation(n, b),
            6 => NativePhase::RealFrame(n, b),
            7 => NativePhase::RealPresentation(n, b),
            8 => NativePhase::Finalization(n, b),
            _ => panic!("malformed states never enter frozen original algebra"),
        };
        Self { next: s.next_generation, phase }
    }

    fn binding(self) -> Option<Binding> {
        match self.phase {
            NativePhase::Idle => None,
            NativePhase::Active(_, b, _) | NativePhase::Suspending(_, b, _, _, _)
            | NativePhase::Suspended(_, b) | NativePhase::Marker(_, b)
            | NativePhase::MarkerPresentation(_, b) | NativePhase::RealFrame(_, b)
            | NativePhase::RealPresentation(_, b) | NativePhase::Finalization(_, b) => Some(b),
        }
    }

    fn owned_notice(self) -> Option<Notice> {
        match self.phase {
            NativePhase::Idle | NativePhase::Active(_, _, None) => None,
            NativePhase::Active(_, _, n) => n,
            NativePhase::Suspending(n, _, _, _, _) | NativePhase::Suspended(n, _)
            | NativePhase::Marker(n, _) | NativePhase::MarkerPresentation(n, _)
            | NativePhase::RealFrame(n, _) | NativePhase::RealPresentation(n, _)
            | NativePhase::Finalization(n, _) => Some(n),
        }
    }

    fn raw(self) -> S {
        let mut s = empty(self.next);
        let (tag, screen, generation, binding, mask) = match self.phase {
            NativePhase::Idle => return s,
            NativePhase::Active(screen, b, n) => (1, screen, n.map_or(0, |x| x.1), b,
                if n.is_some() { 1 } else { 0 }),
            NativePhase::Suspending(n, b, prior, cover, inactive) => {
                if let Some(p) = prior {
                    s.prior_screen_request_id = p.0;
                    s.prior_suspension_generation = p.1;
                }
                s.cover_confirmed = u32::from(cover);
                s.inactive_confirmed = u32::from(inactive);
                (2, n.0, n.1, b, if prior.is_some() { 3 } else { 1 })
            },
            NativePhase::Suspended(n, b) => (3, n.0, n.1, b, 1),
            NativePhase::Marker(n, b) => (4, n.0, n.1, b, 5),
            NativePhase::MarkerPresentation(n, b) => (5, n.0, n.1, b, 13),
            NativePhase::RealFrame(n, b) => (6, n.0, n.1, b, 21),
            NativePhase::RealPresentation(n, b) => (7, n.0, n.1, b, 37),
            NativePhase::Finalization(n, b) => (8, n.0, n.1, b, 69),
        };
        s.phase = tag; s.screen_request_id = screen; s.suspension_generation = generation;
        s.peer_generation = binding.0; s.visibility_epoch = binding.1; s.recovery_epoch = binding.2;
        s.custody_mask = mask;
        s
    }

    fn diagnostic_flags(self) -> u32 {
        match self.phase {
            NativePhase::Idle => 0,
            NativePhase::Active(_, _, None) => 72,
            NativePhase::Active(_, _, Some(_)) => 248,
            NativePhase::Suspending(..) => 250,
            NativePhase::Suspended(..) => 249,
            NativePhase::Marker(..) | NativePhase::MarkerPresentation(..)
            | NativePhase::RealFrame(..) | NativePhase::RealPresentation(..)
            | NativePhase::Finalization(..) => 253,
        }
    }

    fn apply(mut self, e: E) -> R {
        let b = Binding(e.peer_generation, e.visibility_epoch, e.recovery_epoch);
        let n = Notice(e.notice_screen_request_id, e.notice_generation);
        let has = |bit: u32| (e.native_facts / (1 << bit)) % 2 == 1;
        let mut accepted = false;
        let mut action = 0;
        let mut produced = None;
        match (e.opcode, self.phase) {
            (0, _) => accepted = true,
            (1, _) if e.screen_request_id != 0 && b.0 != 0 && b.1 != 0 => {
                self.phase = NativePhase::Active(e.screen_request_id, b, None);
                accepted = true; action = 1;
            },
            (2, _) => { self.phase = NativePhase::Idle; accepted = true; action = 2; },
            (3, NativePhase::Suspending(current, current_b, prior, _, false)) if b == current_b => {
                self.phase = NativePhase::Active(current.0, b, prior); accepted = true; action = 4;
            },
            (4, NativePhase::Active(screen, current_b, prior))
                if e.flags == 1 && b.0 != 0 && b.1 != 0 && b == current_b => {
                let fresh = Notice(screen, self.next);
                self.next = if self.next == u64::MAX { 1 } else { self.next + 1 };
                self.phase = NativePhase::Suspending(fresh, b, prior, false, false);
                accepted = true; action = 3; produced = Some(fresh);
            },
            (5, NativePhase::Suspending(current, current_b, prior, false, inactive))
                if b == current_b && n == current && has(1) => {
                self.phase = if inactive { NativePhase::Suspended(current, current_b) }
                    else { NativePhase::Suspending(current, current_b, prior, true, false) };
                accepted = true; if inactive { action = 5; }
            },
            (6, NativePhase::Suspending(current, current_b, prior, cover, false))
                if b.0 == current_b.0 && b.2 == current_b.2 && b.1 >= current_b.1
                    && n == current && has(0) => {
                self.phase = if cover { NativePhase::Suspended(current, b) }
                    else { NativePhase::Suspending(current, b, prior, false, true) };
                accepted = true; if cover { action = 5; }
            },
            (7, NativePhase::Suspended(current, current_b)) if b == current_b && has(2) => {
                self.phase = NativePhase::Marker(current, b); accepted = true; action = 6;
            },
            (8, NativePhase::Marker(current, current_b))
                if b == current_b && n == current && has(3) && has(4) => {
                self.phase = NativePhase::MarkerPresentation(current, b); accepted = true; action = 7;
            },
            (9, NativePhase::MarkerPresentation(current, current_b))
                if b == current_b && n == current && has(5) => {
                self.phase = NativePhase::RealFrame(current, b); accepted = true; action = 8;
            },
            (10, NativePhase::RealFrame(current, current_b))
                if b == current_b && n == current && has(3) && has(6) && has(7) => {
                self.phase = NativePhase::RealPresentation(current, b); accepted = true; action = 9;
            },
            (11, NativePhase::RealPresentation(current, current_b))
                if b == current_b && n == current && has(3) && has(8) && has(9) => {
                self.phase = NativePhase::Finalization(current, b); accepted = true; action = 10;
            },
            (12, NativePhase::Finalization(current, current_b))
                if b == current_b && n == current && has(10) => {
                self.phase = NativePhase::Active(current.0, b, Some(current)); accepted = true; action = 11;
            },
            (13, NativePhase::Active(screen, current_b, Some(current)))
                if b == current_b && screen == n.0 && current == n && has(0) && has(11) => {
                self.phase = NativePhase::Suspended(n, b); accepted = true; action = 14;
            },
            (14, _) if self.binding() == Some(b) && self.owned_notice().is_some() => {
                self.phase = if e.flags == 1 { NativePhase::Suspended(self.owned_notice().unwrap(), b) }
                    else { NativePhase::Idle };
                accepted = true; action = if e.flags == 1 { 12 } else { 13 };
            },
            (15, _) => accepted = self.binding() == Some(b),
            (16, NativePhase::Finalization(current, current_b)) =>
                accepted = b == current_b && n == current && has(3) && has(10),
            (17, _) => accepted = b.0 != 0 && b.1 != 0,
            _ => {},
        }
        R { abi_version: 1, status: 1, accepted: u32::from(accepted), custody_action: action,
            state: self.raw(), query_flags: self.diagnostic_flags(), reserved: 0,
            produced_notice_screen_request_id: produced.map_or(0, |p| p.0),
            produced_notice_generation: produced.map_or(0, |p| p.1) }
    }
}

fn empty(next: u64) -> S {
    S { abi_version: 1, phase: 0, next_generation: next, screen_request_id: 0,
        suspension_generation: 0, peer_generation: 0, visibility_epoch: 0, recovery_epoch: 0,
        prior_screen_request_id: 0, prior_suspension_generation: 0, cover_confirmed: 0,
        inactive_confirmed: 0, custody_mask: 0, reserved: 0 }
}
fn native(phase: NativePhase, next: u64) -> S { OriginalOwner { next, phase }.raw() }
fn fixture(phase: u32) -> S {
    let b = Binding(2, 3, 0); let n = Notice(7, 11);
    native(match phase {
        0 => NativePhase::Idle, 1 => NativePhase::Active(7, b, None),
        2 => NativePhase::Suspending(n, b, None, false, false),
        3 => NativePhase::Suspended(n, b), 4 => NativePhase::Marker(n, b),
        5 => NativePhase::MarkerPresentation(n, b), 6 => NativePhase::RealFrame(n, b),
        7 => NativePhase::RealPresentation(n, b), 8 => NativePhase::Finalization(n, b),
        _ => panic!("finite fixture phase"),
    }, 123)
}
fn samples() -> Vec<S> {
    let b = Binding(2, 3, 0); let n = Notice(7, 11);
    let mut all: Vec<S> = (0..=8).map(fixture).collect();
    all.push(native(NativePhase::Active(7, b, Some(n)), 123));
    for prior in [None, Some(Notice(7, 5))] {
        for (cover, inactive) in [(true, false), (false, true)] {
            all.push(native(NativePhase::Suspending(n, b, prior, cover, inactive), 123));
        }
    }
    all.push(native(NativePhase::Suspending(n, b, Some(Notice(7, 5)), false, false), 123));
    all
}
fn event(s: S, opcode: u32) -> E {
    let mut e = E { opcode, flags: 0, native_facts: 0, reserved: 0, screen_request_id: 0,
        peer_generation: s.peer_generation, visibility_epoch: s.visibility_epoch,
        recovery_epoch: s.recovery_epoch, notice_screen_request_id: 0, notice_generation: 0 };
    match opcode {
        0 | 2 => { e.peer_generation = 0; e.visibility_epoch = 0; e.recovery_epoch = 0; },
        1 => { e.screen_request_id = 9; e.peer_generation = 2; e.visibility_epoch = 3; },
        4 | 14 => e.flags = 1,
        5 => e.native_facts = 2,
        6 => e.native_facts = 1,
        7 => e.native_facts = 4,
        8 => e.native_facts = 24,
        9 => e.native_facts = 32,
        10 => e.native_facts = 200,
        11 => e.native_facts = 776,
        12 => e.native_facts = 1024,
        13 => e.native_facts = 2049,
        16 => e.native_facts = 1032,
        _ => {},
    }
    if [5,6,8,9,10,11,12,13,16].contains(&opcode) {
        e.notice_screen_request_id = s.screen_request_id;
        e.notice_generation = s.suspension_generation;
    }
    e
}
fn checked(s: S, e: E) -> R {
    let actual = step(s, e); // Always the actual exported C producer before expected algebra.
    let expected = OriginalOwner::from_raw(s).apply(e);
    assert_eq!(actual, expected, "before={s:?}, event={e:?}");
    assert_eq!(verify(s, e, actual), 1);
    actual
}
fn refused(s: S, e: E) {
    let actual = checked(s, e);
    assert_eq!((actual.accepted, actual.custody_action, actual.state), (0, 0, s));
    assert_eq!((actual.produced_notice_screen_request_id, actual.produced_notice_generation), (0, 0));
}
fn denial() -> R {
    R { abi_version: 1, status: 0, accepted: 0, custody_action: 0, state: empty(1),
        query_flags: 0, reserved: 0, produced_notice_screen_request_id: 0, produced_notice_generation: 0 }
}
fn malformed(s: S, e: E) {
    let actual = step(s, e);
    assert_eq!(actual, denial());
    assert_eq!(verify(s, e, actual), 0);
}

#[test]
fn screen_suspension_three_layouts_and_all_thirty_three_offsets_are_literal() {
    assert_eq!((size_of::<S>(), align_of::<S>()), (88, 8));
    assert_eq!((size_of::<E>(), align_of::<E>()), (64, 8));
    assert_eq!((size_of::<R>(), align_of::<R>()), (128, 8));
    assert_eq!(offset_of!(S, abi_version),0); assert_eq!(offset_of!(S, phase),4);
    assert_eq!(offset_of!(S, next_generation),8); assert_eq!(offset_of!(S, screen_request_id),16);
    assert_eq!(offset_of!(S, suspension_generation),24); assert_eq!(offset_of!(S, peer_generation),32);
    assert_eq!(offset_of!(S, visibility_epoch),40); assert_eq!(offset_of!(S, recovery_epoch),48);
    assert_eq!(offset_of!(S, prior_screen_request_id),56); assert_eq!(offset_of!(S, prior_suspension_generation),64);
    assert_eq!(offset_of!(S, cover_confirmed),72); assert_eq!(offset_of!(S, inactive_confirmed),76);
    assert_eq!(offset_of!(S, custody_mask),80); assert_eq!(offset_of!(S, reserved),84);
    assert_eq!(offset_of!(E, opcode),0); assert_eq!(offset_of!(E, flags),4);
    assert_eq!(offset_of!(E, native_facts),8); assert_eq!(offset_of!(E, reserved),12);
    assert_eq!(offset_of!(E, screen_request_id),16); assert_eq!(offset_of!(E, peer_generation),24);
    assert_eq!(offset_of!(E, visibility_epoch),32); assert_eq!(offset_of!(E, recovery_epoch),40);
    assert_eq!(offset_of!(E, notice_screen_request_id),48); assert_eq!(offset_of!(E, notice_generation),56);
    assert_eq!(offset_of!(R, abi_version),0); assert_eq!(offset_of!(R, status),4);
    assert_eq!(offset_of!(R, accepted),8); assert_eq!(offset_of!(R, custody_action),12);
    assert_eq!(offset_of!(R, state),16); assert_eq!(offset_of!(R, query_flags),104);
    assert_eq!(offset_of!(R, reserved),108); assert_eq!(offset_of!(R, produced_notice_screen_request_id),112);
    assert_eq!(offset_of!(R, produced_notice_generation),120);
}

#[test]
fn screen_suspension_initial_and_all_phase_projections_match_frozen_diagnostics() {
    for s in samples() {
        let actual = checked(s, event(s, 0));
        assert_eq!((actual.accepted, actual.custody_action, actual.state), (1,0,s));
        assert_eq!(actual.query_flags, match s.phase {
            0 => 0, 1 if s.suspension_generation == 0 => 72, 1 => 248,
            2 => 250, 3 => 249, _ => 253,
        });
    }
    let finalization = checked(fixture(8), event(fixture(8), 0));
    assert_eq!((finalization.state.custody_mask, finalization.query_flags), (69,253));
}

#[test]
fn screen_suspension_activate_all_phases_clears_provenance_without_rewinding_counter() {
    for s in samples() {
        let mut e = event(s,1); e.recovery_epoch=u64::MAX;
        let actual=checked(s,e);
        assert_eq!(actual.state, native(NativePhase::Active(9,Binding(2,3,u64::MAX),None),123));
        assert_eq!((actual.accepted,actual.custody_action,actual.query_flags),(1,1,72));
    }
}

#[test]
fn screen_suspension_retire_every_phase_preserves_full_generator() {
    for s in samples() {
        for next in [1,123,u64::MAX] {
            let before=S {next_generation:next,..s};
            let actual=checked(before,event(before,2));
            assert_eq!((actual.state,actual.custody_action),(empty(next),2));
        }
    }
}

#[test]
fn screen_suspension_zero_or_stale_activation_and_unnegotiated_begin_leave_state_exact() {
    for s in samples() {
        for field in 0..3 {
            let mut e=event(s,1);
            match field {0=>e.screen_request_id=0,1=>e.peer_generation=0,_=>e.visibility_epoch=0};
            refused(s,e);
        }
    }
    let s=fixture(1);
    let mut e=event(s,4); e.flags=0; refused(s,e);
    for field in 0..3 {
        let mut e=event(s,4);
        match field {0=>e.peer_generation+=1,1=>e.visibility_epoch+=1,_=>e.recovery_epoch+=1};
        refused(s,e);
    }
}

#[test]
fn screen_suspension_begin_wraps_full_uint64_and_skips_only_zero() {
    for next in [1,2,u64::MAX-1,u64::MAX] {
        let s=S {next_generation:next,..fixture(1)};
        let actual=checked(s,event(s,4));
        let expected_next=if next==u64::MAX {1}else{next+1};
        assert_eq!((actual.state.suspension_generation,actual.state.next_generation),(next,expected_next));
        assert_eq!((actual.produced_notice_screen_request_id,actual.produced_notice_generation),(7,next));
        assert_eq!((actual.state.phase,actual.state.custody_mask,actual.custody_action),(2,1,3));
    }
}

#[test]
fn screen_suspension_new_generation_retains_prior_completed_provenance_in_full() {
    for generation in [1,u64::MAX] {
        let before=native(NativePhase::Active(7,Binding(2,3,0),Some(Notice(7,generation))),generation);
        let actual=checked(before,event(before,4));
        assert_eq!((actual.state.prior_screen_request_id,actual.state.prior_suspension_generation),(7,generation));
        assert_eq!((actual.state.suspension_generation,actual.state.custody_mask),(generation,3));
    }
}

#[test]
fn screen_suspension_cover_first_then_inactive_joins_and_rebinds_entire_scalar_state() {
    let before=fixture(2);
    let cover=checked(before,event(before,5));
    assert_eq!(cover.state,S {cover_confirmed:1,..before});
    assert_eq!((cover.accepted,cover.custody_action,cover.query_flags),(1,0,250));
    let mut e=event(cover.state,6); e.visibility_epoch=41;
    let joined=checked(cover.state,e);
    assert_eq!(joined.state,native(NativePhase::Suspended(Notice(7,11),Binding(2,41,0)),123));
    assert_eq!((joined.custody_action,joined.query_flags),(5,249));
}

#[test]
fn screen_suspension_inactive_first_partial_none_action_publishes_rebinding_and_rejects_stale_cover() {
    let before=fixture(2);
    let mut inactive=event(before,6); inactive.visibility_epoch=41;
    let partial=checked(before,inactive);
    assert_eq!(partial.state,S {visibility_epoch:41,inactive_confirmed:1,..before});
    assert_eq!((partial.accepted,partial.custody_action,partial.query_flags),(1,0,250));
    let mut stale=event(partial.state,5); stale.visibility_epoch=3;
    refused(partial.state,stale);
    let joined=checked(partial.state,event(partial.state,5));
    assert_eq!(joined.state,native(NativePhase::Suspended(Notice(7,11),Binding(2,41,0)),123));
    assert_eq!(joined.custody_action,5);
}

#[test]
fn screen_suspension_inactive_inclusive_visibility_and_each_foreign_axis_remain_exact() {
    let s=fixture(2);
    let same=checked(s,event(s,6)); assert_eq!(same.accepted,1);
    for field in 0..3 {
        let mut e=event(s,6);
        match field {0=>e.visibility_epoch=2,1=>e.peer_generation=3,_=>e.recovery_epoch=1};
        refused(s,e);
    }
    let mut e=event(s,6); e.visibility_epoch=u64::MAX;
    assert_eq!(checked(s,e).state.visibility_epoch,u64::MAX);
}

#[test]
fn screen_suspension_duplicate_confirmations_refuse_every_field_without_advancing_generator() {
    let before=fixture(2);
    let cover=checked(before,event(before,5)).state;
    refused(cover,event(cover,5));
    let inactive=checked(before,event(before,6)).state;
    refused(inactive,event(inactive,6));
}

#[test]
fn screen_suspension_abort_restores_prior_with_or_without_cover_but_not_after_inactive() {
    for prior in [None,Some(Notice(7,u64::MAX))] {
        for cover in [false,true] {
            let s=native(NativePhase::Suspending(Notice(7,11),Binding(2,3,0),prior,cover,false),123);
            let actual=checked(s,event(s,3));
            assert_eq!(actual.state,native(NativePhase::Active(7,Binding(2,3,0),prior),123));
            assert_eq!(actual.custody_action,4);
        }
        let s=native(NativePhase::Suspending(Notice(7,11),Binding(2,3,0),prior,false,true),123);
        refused(s,event(s,3));
    }
}

#[test]
fn screen_suspension_exact_resume_sequence_preserves_full_state_and_final_mask_sixty_nine() {
    let mut s=fixture(3);
    for (op,phase,mask,action) in [(7,4,5,6),(8,5,13,7),(9,6,21,8),(10,7,37,9),(11,8,69,10)] {
        let actual=checked(s,event(s,op));
        assert_eq!((actual.accepted,actual.state.phase,actual.state.custody_mask,actual.custody_action),(1,phase,mask,action));
        assert_eq!((actual.state.next_generation,actual.state.screen_request_id,
            actual.state.suspension_generation,actual.state.peer_generation,
            actual.state.visibility_epoch,actual.state.recovery_epoch),(123,7,11,2,3,0));
        s=actual.state;
    }
    let authority=checked(s,event(s,16)); assert_eq!((authority.accepted,authority.state),(1,s));
    let completed=checked(s,event(s,12));
    assert_eq!(completed.state,native(NativePhase::Active(7,Binding(2,3,0),Some(Notice(7,11))),123));
    assert_eq!((completed.custody_action,completed.query_flags),(11,248));
}

#[test]
fn screen_suspension_each_resume_fact_is_required_independently_not_only_notice_pairs() {
    for (phase,op,bits) in [(3,7,vec![2]),(4,8,vec![3,4]),(5,9,vec![5]),
        (6,10,vec![3,6,7]),(7,11,vec![3,8,9]),(8,12,vec![10]),(8,16,vec![3,10])] {
        let s=fixture(phase);
        for bit in bits {let mut e=event(s,op);e.native_facts&=!(1<<bit);refused(s,e);}
    }
    let s=fixture(2);
    for op in [5,6] {let mut e=event(s,op);e.native_facts=0;refused(s,e);}
}

#[test]
fn screen_suspension_scalar_notice_pairs_remain_rust_owned_even_with_all_native_facts_true() {
    for (phase,op) in [(2,5),(2,6),(4,8),(5,9),(6,10),(7,11),(8,12),(8,16)] {
        let s=fixture(phase);
        for axis in 0..2 {
            let mut e=event(s,op);
            if axis==0 {e.notice_screen_request_id+=1;}else{e.notice_generation+=1;}
            refused(s,e);
        }
    }
}

#[test]
fn screen_suspension_commit_has_original_request_fact_without_added_attempt_guard() {
    let s=fixture(8);
    let e=event(s,12);
    assert_eq!(e.native_facts,1024);
    assert_eq!(checked(s,e).accepted,1);
    let mut invalid=e; invalid.native_facts|=8; malformed(s,invalid);
}

#[test]
fn screen_suspension_completed_active_and_every_suspension_owned_phase_cancel_exactly() {
    for s in samples() {
        if s.custody_mask&1==0 {continue;}
        let actual=checked(s,event(s,14));
        assert_eq!(actual.state,native(NativePhase::Suspended(Notice(7,11),Binding(2,3,0)),123));
        assert_eq!(actual.custody_action,12);
        let mut e=event(s,14);e.flags=0;
        let retired=checked(s,e);assert_eq!((retired.state,retired.custody_action),(empty(123),13));
    }
}

#[test]
fn screen_suspension_ordinary_active_and_idle_have_no_cancellation_provenance() {
    for s in [fixture(0),fixture(1)] {
        for requested in [0,1] {let mut e=event(s,14);e.flags=requested;refused(s,e);}
    }
}

#[test]
fn screen_suspension_stale_cleanup_cannot_retire_or_suspend_any_foreign_binding() {
    for s in samples() {
        for axis in 0..3 {
            for requested in [0,1] {
                let mut e=event(s,14);e.flags=requested;
                match axis {0=>e.peer_generation+=1,1=>e.visibility_epoch+=1,_=>e.recovery_epoch+=1};
                refused(s,e);
            }
        }
    }
}

#[test]
fn screen_suspension_rollback_requires_completed_active_exact_binding_notice_and_validity() {
    let s=native(NativePhase::Active(7,Binding(2,3,0),Some(Notice(7,11))),123);
    let actual=checked(s,event(s,13));
    assert_eq!((actual.state,actual.custody_action),(fixture(3),14));
    for bit in [0,11] {let mut e=event(s,13);e.native_facts&=!(1<<bit);refused(s,e);}
    for axis in 0..5 {
        let mut e=event(s,13);
        match axis {0=>e.peer_generation+=1,1=>e.visibility_epoch+=1,2=>e.recovery_epoch+=1,
            3=>e.notice_screen_request_id+=1,_=>e.notice_generation+=1};
        refused(s,e);
    }
    refused(fixture(1),event(fixture(1),13));
}

#[test]
fn screen_suspension_owns_and_authorizes_are_exact_nonmutating_full_state_queries() {
    for s in samples() {
        let actual=checked(s,event(s,15));
        assert_eq!((actual.state,actual.custody_action,actual.accepted),(s,0,u32::from(s.phase!=0)));
        for axis in 0..3 {
            let mut e=event(s,15);
            match axis {0=>e.peer_generation+=1,1=>e.visibility_epoch+=1,_=>e.recovery_epoch+=1};
            refused(s,e);
        }
        let authority=checked(s,event(s,16));
        assert_eq!((authority.state,authority.custody_action,authority.accepted),(s,0,u32::from(s.phase==8)));
    }
}

#[test]
fn screen_suspension_full_uint64_bindings_and_recovery_zero_never_narrow_or_reorder() {
    for b in [Binding(1,1,0),Binding(u64::MAX,u64::MAX,0),
        Binding(1<<63,(1<<63)+7,u64::MAX)] {
        let s=native(NativePhase::Active(u64::MAX,b,None),u64::MAX);
        let begun=checked(s,event(s,4));
        assert_eq!((begun.state.peer_generation,begun.state.visibility_epoch,begun.state.recovery_epoch),(b.0,b.1,b.2));
        assert_eq!(begun.produced_notice_screen_request_id,u64::MAX);
        let suspended=checked(begun.state,event(begun.state,14)).state;
        assert_eq!(checked(suspended,event(suspended,7)).accepted,1);
        assert_eq!(checked(s,event(s,15)).accepted,1);
    }
}

#[test]
fn screen_suspension_binding_predicate_ignores_recovery_but_rejects_zero_peer_or_visibility() {
    for peer in [0,1,u64::MAX] {for vis in [0,1,u64::MAX] {for recovery in [0,u64::MAX] {
        let s=fixture(0);let mut e=event(s,17);
        e.peer_generation=peer;e.visibility_epoch=vis;e.recovery_epoch=recovery;
        let actual=checked(s,e);
        assert_eq!((actual.accepted,actual.state),(u32::from(peer!=0&&vis!=0),s));
    }}}
}

#[test]
fn screen_suspension_invalid_state_words_masks_and_join_flags_have_canonical_denial() {
    let s=fixture(2);
    let mutations=[
        S {abi_version:0,..s},S {phase:9,..s},S {next_generation:0,..s},
        S {screen_request_id:0,..s},S {suspension_generation:0,..s},
        S {peer_generation:0,..s},S {visibility_epoch:0,..s},
        S {cover_confirmed:2,..s},S {inactive_confirmed:2,..s},
        S {cover_confirmed:1,inactive_confirmed:1,..s},S {custody_mask:3,..s},
        S {custody_mask:0,..s},S {custody_mask:129,..s},S {reserved:1,..s},
        S {prior_screen_request_id:7,..s},S {prior_suspension_generation:1,..s},
    ];
    for bad in mutations {malformed(bad,event(s,0));}
    for phase in 1..=8 {
        let s=fixture(phase);
        for bad in [S {cover_confirmed:1,..s},S {inactive_confirmed:1,..s},
            S {prior_screen_request_id:7,prior_suspension_generation:1,..s}] {
            if phase!=2 {malformed(bad,event(s,0));}
        }
        for mask in [0,1,3,5,13,21,37,69,u32::MAX] {
            if mask!=s.custody_mask {malformed(S {custody_mask:mask,..s},event(s,0));}
        }
    }
    let idle=fixture(0);
    for bad in [S {screen_request_id:1,..idle},S {suspension_generation:1,..idle},
        S {peer_generation:1,..idle},S {visibility_epoch:1,..idle},S {recovery_epoch:1,..idle},
        S {custody_mask:1,..idle},S {prior_screen_request_id:1,..idle}] {malformed(bad,event(idle,0));}
}

#[test]
fn screen_suspension_prior_pair_canonicality_keeps_equal_generations_and_full_width_legal() {
    let s=native(NativePhase::Suspending(Notice(7,u64::MAX),Binding(2,3,0),
        Some(Notice(7,u64::MAX)),false,false),u64::MAX);
    assert_eq!(checked(s,event(s,0)).state,s);
    for bad in [S {prior_screen_request_id:8,..s},S {prior_screen_request_id:0,..s},
        S {prior_suspension_generation:0,..s},S {custody_mask:1,..s}] {
        malformed(bad,event(s,0));
    }
}

#[test]
fn screen_suspension_each_opcode_rejects_only_noncanonical_unused_payload() {
    let s=fixture(8);
    for opcode in 0..=17 {
        let e=event(s,opcode);
        checked(s,e);
        let mut reserved=e;reserved.reserved=1;malformed(s,reserved);
        let mut flags=e;flags.flags|=2;malformed(s,flags);
        if ![4,14].contains(&opcode) {let mut bad=e;bad.flags=1;malformed(s,bad);}
        if opcode!=1 {let mut bad=e;bad.screen_request_id=1;malformed(s,bad);}
        if [0,2].contains(&opcode) {
            for axis in 0..3 {let mut bad=e;match axis {0=>bad.peer_generation=1,
                1=>bad.visibility_epoch=1,_=>bad.recovery_epoch=1};malformed(s,bad);}
        }
        if ![5,6,8,9,10,11,12,13,16].contains(&opcode) {
            for axis in 0..2 {let mut bad=e;if axis==0 {bad.notice_screen_request_id=1;}
                else{bad.notice_generation=1;}malformed(s,bad);}
        }
        let allowed=e.native_facts;
        for bit in 0..32 {
            if allowed&(1<<bit)==0 {let mut bad=e;bad.native_facts|=1<<bit;malformed(s,bad);}
        }
    }
}

#[test]
fn screen_suspension_unknown_operations_and_denial_never_validate_as_reset_or_grant() {
    let s=fixture(8);
    for opcode in [18,19,u32::MAX] {
        let e=E {opcode,..event(s,0)};malformed(s,e);
        let mut fake=denial();fake.status=1;fake.accepted=1;
        assert_eq!(verify(s,e,fake),0);
    }
    let e=event(s,0);
    assert_eq!(verify(s,e,denial()),0);
}

#[test]
fn screen_suspension_verifier_rejects_every_one_of_all_128_copied_result_bytes() {
    for s in samples() {
        for opcode in 0..=17 {
            let e=event(s,opcode);
            let actual=step(s,e);
            assert_eq!(actual,OriginalOwner::from_raw(s).apply(e));
            assert_eq!(verify(s,e,actual),1);
            for byte in 0..128 {
                let mut forged=actual;
                // All fields are fixed-width integers and the literal ABI has no padding.
                unsafe {*((&mut forged as *mut R).cast::<u8>().add(byte))^=1;}
                assert_eq!(verify(s,e,forged),0,"phase {} op {} byte {}",s.phase,opcode,byte);
            }
        }
    }
}

#[test]
fn screen_suspension_full_phase_event_refusal_matrix_snapshots_all_fields() {
    for s in samples() {
        for opcode in 0..=17 {
            let e=event(s,opcode);
            let actual=checked(s,e);
            if actual.accepted==0 {
                assert_eq!((actual.state,actual.custody_action),(s,0));
                assert_eq!((actual.produced_notice_screen_request_id,actual.produced_notice_generation),(0,0));
            }
            if [0,15,16,17].contains(&opcode) {assert_eq!(actual.state,s);}
        }
    }
}

#[test]
fn screen_suspension_every_out_of_order_proof_and_stale_binding_is_ordinary_refusal() {
    for phase in 0..=8 {
        let s=fixture(phase);
        for opcode in 7..=12 {
            let admitted_phase=opcode-4;
            if phase!=admitted_phase {refused(s,event(s,opcode));}
            else {
                for axis in 0..3 {
                    let mut e=event(s,opcode);
                    match axis {0=>e.peer_generation+=1,1=>e.visibility_epoch+=1,_=>e.recovery_epoch+=1};
                    refused(s,e);
                }
            }
        }
    }
}

#[test]
fn screen_suspension_fixed_complete_cycles_preserve_provenance_abort_rollback_and_generator() {
    let mut s=fixture(1);
    for _ in 0..8 {
        s=checked(s,event(s,4)).state;
        let mut inactive=event(s,6);inactive.visibility_epoch+=1;
        s=checked(s,inactive).state;
        s=checked(s,event(s,5)).state;
        for opcode in 7..=12 {s=checked(s,event(s,opcode)).state;}
        let completed=s;
        s=checked(s,event(s,4)).state;
        s=checked(s,event(s,5)).state;
        s=checked(s,event(s,3)).state;
        assert_eq!(s.suspension_generation,completed.suspension_generation);
        s=checked(s,event(s,13)).state;
        for opcode in 7..=12 {s=checked(s,event(s,opcode)).state;}
        let next=s.next_generation;
        s=checked(s,event(s,2)).state;assert_eq!(s.next_generation,next);
        s=checked(s,event(s,1)).state;
    }
}

#[test]
fn screen_suspension_fixed_seeded_churn_matches_independent_native_enum_algebra() {
    let mut s=fixture(0);
    let mut seed=0x5eed_5375_7370_656e_u64;
    for turn in 0..4096 {
        seed=((u128::from(seed)*6364136223846793005_u128+1442695040888963407_u128)
            & u128::from(u64::MAX)) as u64;
        let opcode=(seed%18) as u32;
        let mut e=event(s,opcode);
        if [4,14].contains(&opcode) {e.flags=(seed>>9&1) as u32;}
        if ![0,2].contains(&opcode) && turn%7==0 {e.visibility_epoch=e.visibility_epoch.saturating_add(1);}
        if turn%11==0 {e.native_facts=0;}
        s=checked(s,e).state;
    }
}
