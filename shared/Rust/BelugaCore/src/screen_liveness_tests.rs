use super::{RawOptional, RawSample, RawSnapshot, RawState, RawResult};

fn opt(value: Option<u64>) -> RawOptional {
    match value { Some(value) => RawOptional { present: 1, value }, None => RawOptional::default() }
}
fn number(raw: RawOptional) -> Option<u64> {
    if raw.present == 1 { Some(raw.value) } else { None }
}
fn original_counters(sample: RawSample) -> [Option<u64>; 6] {
    [number(sample.inbound_bytes), number(sample.inbound_packets), number(sample.decoded_frames),
     if sample.render_present == 1 { Some(sample.presented_frames) } else { None },
     if sample.render_present == 1 { Some(sample.content_samples) } else { None },
     if sample.render_present == 1 { Some(sample.content_changes) } else { None }]
}
/// Independent transcription of the fully pinned original Swift classifier.
/// It uses none of the production reducer/validation/delta/metadata helpers.
fn original(before: RawState, sample: RawSample) -> RawResult {
    let totals = original_counters(sample);
    let old = original_counters(before.previous);
    let reset = if before.previous_present == 0 { 1 }
        else if before.previous.generation != sample.generation { 2 }
        else if totals.iter().zip(old).any(|(a, b)| matches!((*a,b), (Some(a),Some(b)) if a < b)) { 3 }
        else { 0 };
    let deltas: [Option<u64>; 6] = std::array::from_fn(|i| {
        if reset != 0 { return None; }
        match (totals[i], old[i]) {
            (Some(current), Some(previous)) if current >= previous => Some(current - previous),
            _ => None,
        }
    });
    let changed_at = if reset != 0 { None }
        else if matches!(deltas[5], Some(value) if value > 0) { Some(sample.observed_at) }
        else { number(before.last_change_at) };
    let age = if sample.render_present == 0 { None } else {
        let elapsed = if sample.observed_at >= sample.presented_at {
            sample.observed_at - sample.presented_at
        } else { 0 };
        Some((elapsed / 1_000_000).min(86_400_000))
    };
    let live_content = matches!(changed_at, Some(change)
        if sample.observed_at >= change && sample.observed_at - change <= 2_500_000_000);
    let state = if sample.cover == 1 { 0 }
        else if sample.cover != 0 { 1 }
        else if sample.track_attached == 0 { 2 }
        else if reset != 0 { 3 }
        else if matches!(deltas[3], Some(value) if value > 0) {
            if matches!(deltas[5], Some(value) if value > 0) { 8 } else { 7 }
        } else if matches!(age, Some(value) if value <= 2_500) && sample.content_samples > 0 {
            if live_content { 8 } else { 7 }
        } else {
            let inbound: Vec<u64> = [deltas[0], deltas[1]].into_iter().flatten().collect();
            if !inbound.is_empty() && inbound.iter().all(|value| *value == 0) { 4 }
            else if inbound.iter().any(|value| *value > 0) {
                match deltas[2] { Some(value) if value > 0 => 6, Some(_) => 5, None => 3 }
            } else if matches!(deltas[2], Some(value) if value > 0) { 6 }
            else { 3 }
        };
    let valid_dimension = |raw: Option<u64>| raw.filter(|v| (1..=32_768).contains(&(*v as i64)));
    let width = valid_dimension(if sample.render_present == 1 { Some(sample.render_width_bits) } else { None })
        .or_else(|| valid_dimension(number(sample.inbound_width)));
    let height = valid_dimension(if sample.render_present == 1 { Some(sample.render_height_bits) } else { None })
        .or_else(|| valid_dimension(number(sample.inbound_height)));
    let fps = number(sample.frames_per_second_bits).filter(|bits| {
        let value = f64::from_bits(*bits);
        value.is_finite() && value >= 0.0 && value <= 1_000.0
    });
    RawResult {
        abi_version: 1, status: 0, reserved: 0,
        state: RawState { previous_present: 1, last_change_at: opt(changed_at), previous: sample },
        snapshot: RawSnapshot {
            liveness: state, reset_reason: reset, generation: sample.generation,
            track_attached: sample.track_attached, cover: sample.cover,
            inbound_bytes: opt(totals[0]), inbound_byte_delta: opt(deltas[0]),
            inbound_packets: opt(totals[1]), inbound_packet_delta: opt(deltas[1]),
            decoded_frames: opt(totals[2]), decoded_frame_delta: opt(deltas[2]),
            presented_frames: opt(totals[3]), presented_frame_delta: opt(deltas[3]),
            content_samples: opt(totals[4]), content_sample_delta: opt(deltas[4]),
            content_changes: opt(totals[5]), content_change_delta: opt(deltas[5]),
            presentation_age_ms: opt(age), frame_width: opt(width), frame_height: opt(height),
            frames_per_second_bits: opt(fps),
        }
    }
}

fn complete(generation: u64, now: u64, counters: [u64; 6], presented_at: u64) -> RawSample {
    RawSample {
        generation, observed_at: now, track_attached: 1, cover: 0, inbound_present: 1,
        inbound_bytes: opt(Some(counters[0])), inbound_packets: opt(Some(counters[1])),
        decoded_frames: opt(Some(counters[2])), inbound_width: opt(Some(1_280)),
        inbound_height: opt(Some(832)), frames_per_second_bits: opt(Some(30.0f64.to_bits())),
        render_present: 1, presented_frames: counters[3], content_samples: counters[4],
        content_changes: counters[5], presented_at, render_width_bits: 1_280,
        render_height_bits: 832,
    }
}
fn trace(samples: &[RawSample]) -> Vec<RawResult> {
    let mut actual_state = RawState::default();
    let mut reference_state = RawState::default();
    samples.iter().map(|sample| {
        // Actual production C export is called first, without altering its result.
        let actual = crate::beluga_core_screen_liveness_observe(1, actual_state, *sample);
        let reference = original(reference_state, *sample);
        assert_eq!(actual, reference, "complete output at {:?}", sample);
        actual_state = actual.state;
        reference_state = reference.state;
        actual
    }).collect()
}
fn all_deltas(snapshot: RawSnapshot) -> [RawOptional; 6] {
    [snapshot.inbound_byte_delta, snapshot.inbound_packet_delta, snapshot.decoded_frame_delta,
     snapshot.presented_frame_delta, snapshot.content_sample_delta, snapshot.content_change_delta]
}
fn without_render(mut sample: RawSample) -> RawSample {
    sample.render_present = 0;
    sample.presented_frames = 0; sample.content_samples = 0; sample.content_changes = 0;
    sample.presented_at = 0; sample.render_width_bits = 0; sample.render_height_bits = 0;
    sample
}

#[test]
fn cover_before_track_before_initial_and_reset_evidence() {
    for (cover, expected) in [(1,0),(2,1),(3,1),(4,1)] {
        let mut first = complete(1, 0, [10;6], 0);
        first.cover = cover; first.track_attached = 0;
        let mut second = complete(2, 1, [0;6], 1);
        second.cover = cover; second.track_attached = 0;
        let out = trace(&[first,second]);
        assert_eq!(out[0].snapshot.liveness, expected);
        assert_eq!(out[1].snapshot.liveness, expected);
        assert_eq!(out[1].snapshot.reset_reason, 2);
    }
}
#[test]
fn missing_track_precedes_initial_and_render_evidence() {
    let mut sample = complete(1, 0, [10;6], 0);
    sample.track_attached = 0;
    let out = trace(&[sample, complete(1,1,[11;6],1)]);
    assert_eq!(out[0].snapshot.liveness, 2);
    assert_eq!(out[1].snapshot.liveness, 8);
    assert_eq!(out[1].snapshot.reset_reason, 0);
}
#[test]
fn covered_samples_still_advance_floor_and_change_clock() {
    let first = complete(1,0,[10;6],0);
    let mut covered = complete(1,1,[11;6],1); covered.cover = 2;
    let unwrapped = complete(1,2,[11;6],1);
    let out = trace(&[first,covered,unwrapped]);
    assert_eq!(out[1].snapshot.liveness, 1);
    assert_eq!(out[1].state.last_change_at, opt(Some(1)));
    assert_eq!(out[2].snapshot.liveness, 8);
    assert_eq!(all_deltas(out[2].snapshot), [opt(Some(0));6]);
}
#[test]
fn missing_track_samples_still_advance_floor_and_change_clock() {
    let first = complete(1,0,[10;6],0);
    let mut missing = complete(1,1,[11;6],1); missing.track_attached = 0;
    let out = trace(&[first,missing,complete(1,2,[11;6],1)]);
    assert_eq!(out[1].snapshot.liveness, 2);
    assert_eq!(out[2].snapshot.liveness, 8);
    assert_eq!(all_deltas(out[2].snapshot), [opt(Some(0));6]);
}
#[test]
fn presented_progress_precedes_stale_age_and_inbound_decode_stalls() {
    let first = complete(1,0,[10;6],0);
    let second = complete(1,10_000_000_000,[10,10,10,11,0,10],0);
    // contentSamples regression would reset the whole comparison, so keep the floor zero.
    let first = RawSample { content_samples: 0, ..first };
    let out = trace(&[first,second]);
    assert_eq!(out[1].snapshot.liveness, 7);
    assert_eq!(out[1].snapshot.presentation_age_ms, opt(Some(10_000)));
    assert_eq!(out[1].snapshot.content_samples, opt(Some(0)));
}
#[test]
fn advancing_unchanged_frame_ignores_recent_content_clock_then_retained_frame_uses_it() {
    let out = trace(&[complete(1,0,[10;6],0), complete(1,1,[11;6],1),
        complete(1,2,[12,12,12,12,12,11],2), complete(1,3,[12,12,12,12,12,11],2)]);
    assert_eq!(out[1].snapshot.liveness, 8);
    assert_eq!(out[2].snapshot.liveness, 7);
    assert_eq!(out[3].snapshot.liveness, 8);
}
#[test]
fn presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct() {
    let first = complete(1,0,[10,10,10,10,10,5],0);
    let changed = complete(1,0,[10,10,10,10,10,6],0);
    let anchors = [(2_499_999_999,2_499,8),(2_500_000_000,2_500,8),
        (2_500_000_001,2_500,7),(2_500_999_999,2_500,7),(2_501_000_000,2_501,4)];
    let mut samples = vec![first,changed];
    samples.extend(anchors.iter().map(|(now,_,_)| complete(1,*now,[10,10,10,10,10,6],0)));
    let out = trace(&samples);
    assert_eq!(out[1].snapshot.liveness,8);
    for (index,(_,age,state)) in anchors.iter().enumerate() {
        assert_eq!(out[index+2].snapshot.presentation_age_ms,opt(Some(*age)));
        assert_eq!(out[index+2].snapshot.liveness,*state);
        assert_eq!(out[index+2].snapshot.reset_reason,0);
    }
}
#[test]
fn future_presentation_is_zero_age_but_future_content_change_is_not_fresh() {
    let out = trace(&[complete(1,10,[10;6],10), complete(1,20,[11;6],20),
        complete(1,15,[11;6],20)]);
    assert_eq!(out[2].snapshot.presentation_age_ms,opt(Some(0)));
    assert_eq!(out[2].snapshot.reset_reason,0);
    assert_eq!(out[2].snapshot.liveness,7);
    assert_eq!(out[2].state.last_change_at,opt(Some(20)));
    let future=trace(&[complete(1,0,[10;6],u64::MAX)]);
    assert_eq!(future[0].snapshot.presentation_age_ms,opt(Some(0)));
}
#[test]
fn each_single_counter_regression_clears_all_six_deltas_and_recent_clock() {
    for i in 0..6 {
        let first = complete(1,0,[10;6],0);
        let second = complete(1,1,[11;6],1);
        let mut counters = [12;6]; counters[i] = 9;
        let third = complete(1,2,counters,2);
        let out = trace(&[first,second,third,complete(1,3,[13;6],3)]);
        assert_eq!(out[2].snapshot.reset_reason,3,"counter {i}");
        assert_eq!(out[2].snapshot.liveness,3);
        assert_eq!(all_deltas(out[2].snapshot),[RawOptional::default();6]);
        assert_eq!(out[2].state.last_change_at,RawOptional::default());
        assert_eq!(out[3].snapshot.reset_reason,0);
        assert_eq!(all_deltas(out[3].snapshot)[i],opt(Some(4)));
    }
}
#[test]
fn generation_inequality_wins_over_regression_including_max_to_zero() {
    let out = trace(&[complete(u64::MAX,0,[u64::MAX;6],0),complete(0,1,[0;6],1)]);
    assert_eq!(out[1].snapshot.reset_reason,2);
    assert_eq!(all_deltas(out[1].snapshot),[RawOptional::default();6]);
}
#[test]
fn optional_counter_holes_only_break_adjacent_comparison() {
    let first = complete(1,0,[100;6],0);
    let mut hole = complete(1,1,[101;6],1); hole.inbound_bytes = RawOptional::default();
    let mut restored = complete(1,2,[102;6],2); restored.inbound_bytes = opt(Some(1));
    let out = trace(&[first,hole,restored]);
    assert_eq!(out[1].snapshot.inbound_byte_delta,RawOptional::default());
    assert_eq!(out[2].snapshot.inbound_byte_delta,RawOptional::default());
    assert_eq!(out[2].snapshot.inbound_packet_delta,opt(Some(1)));
    assert_eq!(out[2].snapshot.reset_reason,0);
}
#[test]
fn renderer_hole_discards_render_deltas_without_erasing_recent_change() {
    let first = complete(1,0,[10;6],0);
    let second = complete(1,1,[11;6],1);
    let third = without_render(complete(1,2,[12;6],2));
    let restored = complete(1,3,[13,13,13,1,1,1],1);
    let out = trace(&[first,second,third,restored]);
    assert_eq!(out[3].snapshot.reset_reason,0);
    assert_eq!(out[3].snapshot.presented_frame_delta,RawOptional::default());
    assert_eq!(out[3].snapshot.content_change_delta,RawOptional::default());
    assert_eq!(out[3].snapshot.liveness,8);
}
#[test]
fn zero_inbound_precedes_decoded_progress_and_optional_positive_order_is_original() {
    let base = without_render(complete(1,0,[10;6],0));
    for (bytes,packets,decoded,expected) in [
        (Some(10),None,Some(11),4),(None,Some(10),Some(11),4),
        (Some(10),Some(11),Some(10),5),(Some(11),None,None,3),
        (None,None,Some(11),6),(None,None,None,3),
    ] {
        let mut first = base;
        if bytes.is_none() { first.inbound_bytes = RawOptional::default(); }
        if packets.is_none() { first.inbound_packets = RawOptional::default(); }
        if decoded.is_none() { first.decoded_frames = RawOptional::default(); }
        let mut second = first;
        second.observed_at = 1; second.inbound_bytes=opt(bytes);
        second.inbound_packets=opt(packets); second.decoded_frames=opt(decoded);
        let out=trace(&[first,second]);
        assert_eq!(out[1].snapshot.liveness,expected);
    }
}
#[test]
fn full_width_counters_are_neither_truncated_rounded_nor_wrapped() {
    for n in [u32::MAX as u64, 1u64<<53, i64::MAX as u64, u64::MAX-1] {
        let out=trace(&[complete(u64::MAX,0,[n;6],0),complete(u64::MAX,1,[n+1;6],1)]);
        assert_eq!(all_deltas(out[1].snapshot),[opt(Some(1));6]);
        assert_eq!(out[1].snapshot.generation,u64::MAX);
    }
    let out=trace(&[complete(0,0,[0;6],0),complete(0,1,[u64::MAX;6],1),
        complete(0,2,[u64::MAX;6],1),complete(0,3,[0;6],3)]);
    assert_eq!(all_deltas(out[1].snapshot),[opt(Some(u64::MAX));6]);
    assert_eq!(all_deltas(out[2].snapshot),[opt(Some(0));6]);
    assert_eq!(out[3].snapshot.reset_reason,3);
}
#[test]
fn dimensions_choose_each_axis_independently_with_inclusive_original_bounds() {
    let mut sample=complete(1,0,[0;6],0);
    sample.render_width_bits=(-1i64) as u64; sample.render_height_bits=832;
    sample.inbound_width=opt(Some(1_920)); sample.inbound_height=opt(Some(1_080));
    let out=trace(&[sample]);
    assert_eq!(out[0].snapshot.frame_width,opt(Some(1_920)));
    assert_eq!(out[0].snapshot.frame_height,opt(Some(832)));
    for dimension in [0,1,32_768,32_769,(1i64<<32)+1,i64::MIN,i64::MAX] {
        let mut sample=complete(1,0,[0;6],0);
        sample.render_width_bits=dimension as u64;
        sample.inbound_width=RawOptional::default();
        let out=trace(&[sample]);
        let expected=match dimension { 1=>Some(1),32_768=>Some(32_768),_=>None };
        assert_eq!(out[0].snapshot.frame_width,opt(expected));
    }
}
#[test]
fn fps_option_preserves_raw_bits_and_filters_only_original_finite_range() {
    for (bits,valid) in [
        (0.0f64.to_bits(),true),((-0.0f64).to_bits(),true),(1_000.0f64.to_bits(),true),
        (1_000.0001f64.to_bits(),false),((-1.0f64).to_bits(),false),
        (f64::INFINITY.to_bits(),false),(f64::NEG_INFINITY.to_bits(),false),
        (0x7ff8_0000_0000_0011,false),(0xfff8_0000_0000_0011,false),
    ] {
        let mut sample=complete(1,0,[0;6],0); sample.frames_per_second_bits=opt(Some(bits));
        let out=trace(&[sample]);
        assert_eq!(out[0].state.previous.frames_per_second_bits,opt(Some(bits)));
        assert_eq!(out[0].snapshot.frames_per_second_bits,opt(if valid {Some(bits)} else {None}));
    }
}
#[test]
fn metadata_only_inbound_record_presence_is_not_fabricated_or_erased() {
    let sample=RawSample { generation:0, observed_at:u64::MAX, track_attached:1,
        inbound_present:1, inbound_width:opt(Some(1_920)), inbound_height:opt(Some(1_080)),
        frames_per_second_bits:opt(Some(24.0f64.to_bits())),..RawSample::default() };
    let out=trace(&[sample,sample]);
    assert_eq!(out[1].snapshot.liveness,3);
    assert_eq!(out[1].state.previous.inbound_present,1);
    assert_eq!(out[1].snapshot.frame_width,opt(Some(1_920)));
    assert_eq!(out[1].snapshot.frames_per_second_bits,opt(Some(24.0f64.to_bits())));
}
#[test]
fn presentation_age_saturates_after_safe_full_width_subtraction() {
    let out=trace(&[complete(0,u64::MAX,[0;6],0)]);
    assert_eq!(out[0].snapshot.presentation_age_ms,opt(Some(86_400_000)));
    assert_eq!(out[0].snapshot.reset_reason,1);
}
#[test]
fn zeroed_reset_state_clears_both_history_slots() {
    let old=trace(&[complete(1,0,[10;6],0),complete(1,1,[11;6],1)]);
    assert_eq!(old[1].state.last_change_at,opt(Some(1)));
    let sample=complete(1,2,[11;6],1);
    let actual=crate::beluga_core_screen_liveness_observe(1,RawState::default(),sample);
    assert_eq!(actual,original(RawState::default(),sample));
    assert_eq!(actual.snapshot.reset_reason,1);
    assert_eq!(actual.state.last_change_at,RawOptional::default());
}
#[test]
fn malformed_raw_shape_and_abi_are_rejected_without_state_mutation() {
    let state=trace(&[complete(1,0,[10;6],0)])[0].state;
    let sample=complete(1,1,[11;6],1);
    let unknown=crate::beluga_core_screen_liveness_observe(2,state,sample);
    assert_eq!(unknown.status,3); assert_eq!(unknown.state,state);
    for index in 0..7 {
        let mut malformed=sample;
        match index {
            0=>malformed.track_attached=2,1=>malformed.cover=5,2=>malformed.inbound_present=2,
            3=>malformed.render_present=2,4=>malformed.inbound_bytes.present=2,
            5=>{malformed.inbound_bytes.present=0;malformed.inbound_bytes.value=1;},
            _=>malformed.render_present=0,
        }
        let actual=crate::beluga_core_screen_liveness_observe(1,state,malformed);
        assert_eq!(actual.status,3);assert_eq!(actual.state,state);assert_eq!(actual.snapshot,RawSnapshot::default());
    }
    let invalid=RawState { previous_present:2,..state };
    let actual=crate::beluga_core_screen_liveness_observe(1,invalid,sample);
    assert_eq!(actual.status,3);assert_eq!(actual.state,invalid);
}
#[test]
fn copied_states_remain_independent_floors() {
    let floor=trace(&[complete(1,0,[10;6],0)])[0].state;
    let a=crate::beluga_core_screen_liveness_observe(1,floor,complete(1,1,[11;6],1));
    let b=crate::beluga_core_screen_liveness_observe(1,floor,complete(1,2,[12;6],2));
    assert_eq!(a,original(floor,complete(1,1,[11;6],1)));
    assert_eq!(b,original(floor,complete(1,2,[12;6],2)));
    assert_eq!(a.snapshot.inbound_byte_delta,opt(Some(1)));
    assert_eq!(b.snapshot.inbound_byte_delta,opt(Some(2)));
    assert_eq!(floor.previous.inbound_bytes,opt(Some(10)));
}

#[test]
fn fresh_presentation_still_requires_positive_content_samples() {
    let first=complete(1,0,[10,10,10,10,0,5],0);
    let second=complete(1,1,[10,10,10,10,0,5],0);
    let out=trace(&[first,second]);
    assert_eq!(out[1].snapshot.liveness,4);
}
#[test]
fn exact_all_copied_layout_sizes_alignments_and_field_offsets() {
    let actual=crate::beluga_core_screen_liveness_observe(1,RawState::default(),RawSample::default());
    assert_eq!(actual.status,0);assert_eq!(actual.snapshot.liveness,2);
    assert_eq!(std::mem::size_of::<RawOptional>(),16);
    assert_eq!(std::mem::size_of::<RawSample>(),192);
    assert_eq!(std::mem::size_of::<RawState>(),216);
    assert_eq!(std::mem::size_of::<RawSnapshot>(),296);
    assert_eq!(std::mem::size_of::<RawResult>(),536);
    assert_eq!(std::mem::align_of::<RawOptional>(),8);
    assert_eq!(std::mem::align_of::<RawSample>(),8);
    assert_eq!(std::mem::align_of::<RawState>(),8);
    assert_eq!(std::mem::align_of::<RawSnapshot>(),8);
    assert_eq!(std::mem::align_of::<RawResult>(),8);
    assert_eq!(std::mem::offset_of!(RawOptional,present),0);
    assert_eq!(std::mem::offset_of!(RawOptional,value),8);
    assert_eq!(std::mem::offset_of!(RawSample,generation),0);
    assert_eq!(std::mem::offset_of!(RawSample,observed_at),8);
    assert_eq!(std::mem::offset_of!(RawSample,track_attached),16);
    assert_eq!(std::mem::offset_of!(RawSample,cover),24);
    assert_eq!(std::mem::offset_of!(RawSample,inbound_present),32);
    assert_eq!(std::mem::offset_of!(RawSample,inbound_bytes),40);
    assert_eq!(std::mem::offset_of!(RawSample,inbound_packets),56);
    assert_eq!(std::mem::offset_of!(RawSample,decoded_frames),72);
    assert_eq!(std::mem::offset_of!(RawSample,inbound_width),88);
    assert_eq!(std::mem::offset_of!(RawSample,inbound_height),104);
    assert_eq!(std::mem::offset_of!(RawSample,frames_per_second_bits),120);
    assert_eq!(std::mem::offset_of!(RawSample,render_present),136);
    assert_eq!(std::mem::offset_of!(RawSample,presented_frames),144);
    assert_eq!(std::mem::offset_of!(RawSample,content_samples),152);
    assert_eq!(std::mem::offset_of!(RawSample,content_changes),160);
    assert_eq!(std::mem::offset_of!(RawSample,presented_at),168);
    assert_eq!(std::mem::offset_of!(RawSample,render_width_bits),176);
    assert_eq!(std::mem::offset_of!(RawSample,render_height_bits),184);
    assert_eq!(std::mem::offset_of!(RawState,previous_present),0);
    assert_eq!(std::mem::offset_of!(RawState,last_change_at),8);
    assert_eq!(std::mem::offset_of!(RawState,previous),24);
    assert_eq!(std::mem::offset_of!(RawSnapshot,liveness),0);
    assert_eq!(std::mem::offset_of!(RawSnapshot,reset_reason),8);
    assert_eq!(std::mem::offset_of!(RawSnapshot,generation),16);
    assert_eq!(std::mem::offset_of!(RawSnapshot,track_attached),24);
    assert_eq!(std::mem::offset_of!(RawSnapshot,cover),32);
    assert_eq!(std::mem::offset_of!(RawSnapshot,inbound_bytes),40);
    assert_eq!(std::mem::offset_of!(RawSnapshot,inbound_byte_delta),56);
    assert_eq!(std::mem::offset_of!(RawSnapshot,inbound_packets),72);
    assert_eq!(std::mem::offset_of!(RawSnapshot,inbound_packet_delta),88);
    assert_eq!(std::mem::offset_of!(RawSnapshot,decoded_frames),104);
    assert_eq!(std::mem::offset_of!(RawSnapshot,decoded_frame_delta),120);
    assert_eq!(std::mem::offset_of!(RawSnapshot,presented_frames),136);
    assert_eq!(std::mem::offset_of!(RawSnapshot,presented_frame_delta),152);
    assert_eq!(std::mem::offset_of!(RawSnapshot,content_samples),168);
    assert_eq!(std::mem::offset_of!(RawSnapshot,content_sample_delta),184);
    assert_eq!(std::mem::offset_of!(RawSnapshot,content_changes),200);
    assert_eq!(std::mem::offset_of!(RawSnapshot,content_change_delta),216);
    assert_eq!(std::mem::offset_of!(RawSnapshot,presentation_age_ms),232);
    assert_eq!(std::mem::offset_of!(RawSnapshot,frame_width),248);
    assert_eq!(std::mem::offset_of!(RawSnapshot,frame_height),264);
    assert_eq!(std::mem::offset_of!(RawSnapshot,frames_per_second_bits),280);
    assert_eq!(std::mem::offset_of!(RawResult,abi_version),0);
    assert_eq!(std::mem::offset_of!(RawResult,status),8);
    assert_eq!(std::mem::offset_of!(RawResult,reserved),16);
    assert_eq!(std::mem::offset_of!(RawResult,state),24);
    assert_eq!(std::mem::offset_of!(RawResult,snapshot),240);
}

#[test]
fn bounded_seeded_native_value_traces_match_frozen_original_at_every_event() {
    let mut seed=0x1a7e_f047_63c0_b5d9u64;
    let mut next=|| { seed ^= seed<<13; seed ^= seed>>7; seed ^= seed<<17; seed };
    let mut samples=Vec::with_capacity(1_536);
    for index in 0..1_536 {
        let generation=if index%7==0 {next()} else {1};
        let now=next();
        let mut sample=complete(generation,now,[next(),next(),next(),next(),next(),next()],next());
        sample.cover=next()%5; sample.track_attached=next()%2;
        if next()%3==0 {
            sample.inbound_present=0;sample.inbound_bytes=RawOptional::default();
            sample.inbound_packets=RawOptional::default();sample.decoded_frames=RawOptional::default();
            sample.inbound_width=RawOptional::default();sample.inbound_height=RawOptional::default();
            sample.frames_per_second_bits=RawOptional::default();
        } else {
            if next()%2==0 {sample.inbound_bytes=RawOptional::default();}
            if next()%2==0 {sample.inbound_packets=RawOptional::default();}
            if next()%2==0 {sample.decoded_frames=RawOptional::default();}
            sample.inbound_width=opt((next()%2==0).then(||next()));
            sample.inbound_height=opt((next()%2==0).then(||next()));
            sample.frames_per_second_bits=opt((next()%2==0).then(||next()));
        }
        sample.render_width_bits=next();sample.render_height_bits=next();
        if next()%3==0 {sample=without_render(sample);}
        samples.push(sample);
    }
    let out=trace(&samples);
    assert_eq!(out.len(),1_536);
}


// Additive raw-envelope witnesses. No successful native/reference classifier is used.
fn copied_envelope_refusal(abi: u64, before: RawState, sample: RawSample) {
    let before_copy = before;
    let sample_copy = sample;
    // First action at the boundary is the actual production export.
    let actual = crate::beluga_core_screen_liveness_observe(abi, before, sample);
    let expected = RawResult {
        abi_version: 1, status: 3, reserved: 0, state: before_copy,
        snapshot: RawSnapshot::default(),
    };
    assert_eq!(actual, expected, "complete refusal envelope for ABI {abi}");
    assert_eq!(before, before_copy, "every copied before-state field is unchanged");
    assert_eq!(sample, sample_copy, "every copied sample field is unchanged");
}

fn copied_envelope_before() -> RawState {
    RawState {
        previous_present: 1,
        last_change_at: RawOptional::some(u64::MAX),
        previous: RawSample {
            generation: u64::MAX - 31, observed_at: u64::MAX - 1,
            track_attached: 1, cover: 3, inbound_present: 1,
            inbound_bytes: RawOptional::some(0xfefd_fcfb_faf9_f8f7),
            inbound_packets: RawOptional::some(0x8000_0000_0000_0021),
            decoded_frames: RawOptional::some(0x0020_0000_0000_0023),
            inbound_width: RawOptional::some(0x8000_0000_0000_0003),
            inbound_height: RawOptional::some(32_768),
            frames_per_second_bits: RawOptional::some(0xfff8_0000_0000_0042),
            render_present: 1, presented_frames: u64::MAX - 30,
            content_samples: 0x8000_0000_0000_0037,
            content_changes: 0x0020_0000_0000_0041,
            presented_at: u64::MAX - 2, render_width_bits: 1_920,
            render_height_bits: 0x7fff_ffff_ffff_fffa,
        },
    }
}

#[test]
fn unknown_zero_and_full_width_abi_refuse_complete_copied_state() {
    let before = copied_envelope_before();
    for abi in [0, 2, u64::MAX] {
        copied_envelope_refusal(abi, before, before.previous);
    }
}

#[test]
fn absent_inbound_record_rejects_each_nonzero_optional_payload_unchanged() {
    let before = copied_envelope_before();
    let payloads = [u64::MAX, 0x8000_0000_0000_0021, 0x0020_0000_0000_0023,
        i64::MIN as u64, i64::MAX as u64, 0xfff8_0000_0000_0042];
    for (index, payload) in payloads.into_iter().enumerate() {
        let mut sample = RawSample { track_attached: 1, ..RawSample::default() };
        let present = RawOptional::some(payload);
        match index {
            0 => sample.inbound_bytes = present,
            1 => sample.inbound_packets = present,
            2 => sample.decoded_frames = present,
            3 => sample.inbound_width = present,
            4 => sample.inbound_height = present,
            5 => sample.frames_per_second_bits = present,
            _ => unreachable!(),
        }
        // The inner optional is canonical; refusal specifically anchors absent-object payload.
        copied_envelope_refusal(1, before, sample);
    }
}

#[test]
fn malformed_recent_change_option_refuses_complete_before_state_unchanged() {
    let sample = copied_envelope_before().previous;
    for raw in [
        RawOptional { present: 2, value: 17 },
        RawOptional { present: u64::MAX, value: u64::MAX },
        RawOptional { present: 0, value: 1 },
    ] {
        let mut before = copied_envelope_before();
        before.last_change_at = raw;
        copied_envelope_refusal(1, before, sample);
    }
}

#[test]
fn absent_previous_sample_and_change_payloads_refuse_complete_before_state_unchanged() {
    let sample = copied_envelope_before().previous;
    let mut hidden_previous = RawState::default();
    hidden_previous.previous.generation = 1;
    copied_envelope_refusal(1, hidden_previous, sample);
    let mut hidden_full_previous = copied_envelope_before();
    hidden_full_previous.previous_present = 0;
    hidden_full_previous.last_change_at = RawOptional::default();
    copied_envelope_refusal(1, hidden_full_previous, sample);
    for value in [0, u64::MAX] {
        let before = RawState {
            previous_present: 0, last_change_at: RawOptional::some(value),
            previous: RawSample::default(),
        };
        copied_envelope_refusal(1, before, sample);
    }
}

