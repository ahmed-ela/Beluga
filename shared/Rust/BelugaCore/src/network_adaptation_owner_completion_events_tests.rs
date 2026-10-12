//! Public scalar API raw post-await fixtures. Expected successors are manual field
//! assignments serialized by the lossless codec, never a reducer/evaluator call.
//! Callback observations prove POD publication order, not native resource custody.
use core::{ffi::c_void, ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Metadata};
use crate::network_adaptation_owner_completion_events::*;

fn request(operation:u32)->CompletionRequest {
    CompletionRequest {abi:1,operation,invocation:93,current_generation:7,
        facts:if operation==702 {511}else{1},reserved:0}
}
fn recommendation(fps:i64)->Recommendation {
    Recommendation {tier:Tier::Balanced,maximum_video:1_234_567,
        maximum_total:2_345_678,fps,scale:Scalar(0x8000_0000_0000_0000)}
}
fn owner()->Owner {
    let mut v=Owner::new(50_000_000,60,Dependencies::default());
    v.revision=57;v.fast_statistics_available=true;
    v.evidence_lane=Some(EvidenceLane::OrdinaryFallback);
    v.last_evidence=Some(-7_000_000_000_000_000_001);
    v.freshness.minimum=Some(u64::MAX);v.applied=Some(recommendation(29));
    let p=&mut v.policy;p.peer=Some(7);p.tier=Tier::AudioPriority;p.route_present=true;
    p.probe_deadline=Some(101);p.probe_qualification_at=Some(202);
    p.promotion=Some(Promotion {tier:Tier::High,maximum_total:9_876_543,deadline:303});
    p.floor_first_witness=Some(FloorWitness {observed_at:404,bandwidth:Scalar::new(600_001.0)});
    p.floor_cooldown_at=Some(505);p.startup_sparse_deadline=Some(606);
    p.queue.low_observation=Some(707);p.queue.soft_observation=Some(808);
    p.rtt.last_advancement=Some(909);p.rtt.raw.advancement_present=1;
    p.probe_maximum=Some(3_456_789);p.probe_healthy=3;p.probe_grace=5;
    p.floor_regular_sequence=Some(41);p.floor_regular_timestamp=Some(Scalar::new(41_000_000.0));
    p.last_average_delay=Some(Scalar(0x7ff8_0000_0000_0042));v
}
fn prepared(v:Owner)->Prepared {
    let mut p=Prepared {policy:v.policy,source_generation:7,expected_revision:999,
        applying_revision:v.revision,lane:ProposalLane::Capacity,capture_active:false,
        capacity_only:true,changed:Some(recommendation(5)),recommendation:recommendation(5),
        route_action:RouteAction::CopyIncoming,floor_diagnostics:None,capacity_diagnostics:None};
    p.policy.peer=Some(77);p.policy.tier=Tier::Survival;p.policy.route_present=false;
    p.policy.floor_attempt_consumed=true;p.policy.startup_disproved=true;
    p.policy.probe_healthy=33;p.policy.probe_maximum=Some(123_456);p
}
fn times(p:Policy)->[Option<i128>;9] {
    [p.probe_deadline,p.probe_qualification_at,p.promotion.map(|v|v.deadline),
        p.floor_first_witness.map(|v|v.observed_at),p.floor_cooldown_at,
        p.startup_sparse_deadline,p.queue.low_observation,p.queue.soft_observation,
        p.rtt.last_advancement]
}
#[derive(Clone,Debug,PartialEq,Eq)]
struct Output {
    header:codec::Header,atoms:[codec::Atom;179],metadata:Metadata,
    outcome:CompletionOutcome,edits:[Edit;13],coordinates:[Time;13],
}
fn sentinel()->Output {
    Output {header:codec::Header {abi:91,domain:92,phase:93,count:94},
        atoms:[codec::Atom {kind:91,present:92,high:-93,low:94};179],
        metadata:Metadata {abi:91,operation:92,scope:93,read_count:94,invocation:95,
            revision:96,peer:97,peer_present:98,bound:99,route:100,sample:101,
            enabled:102,lease:103,queue_fault:104,rtt_fault:105},
        outcome:CompletionOutcome {abi:91,operation:92,invocation:93,disposition:94,
            route:95,fps_changed:96,reserved:97},
        edits:[Edit {action:91,source:92,index:93,ordinal:94,high:-95,low:96};13],
        coordinates:[Time {present:91,reserved:92,high:-93,low:94};13]}
}
struct NativeOutput {
    calls:Vec<(u64,i64)>,observed_unpublished:Vec<bool>,output:*const Output,
    validations:Vec<ValidationObservation>,trace:Vec<u32>,validator_present:bool,validator_reply:u32,
}
struct ValidationObservation {
    invocation:u64,counts:[u32;3],layout_valid:bool,bundle:Option<Output>,unpublished:bool,
}
impl Default for NativeOutput {
    fn default()->Self {Self {calls:Vec::new(),observed_unpublished:Vec::new(),output:ptr::null(),
        validations:Vec::new(),trace:Vec::new(),validator_present:true,validator_reply:1}}
}
unsafe extern "C" fn callback(context:*mut c_void,invocation:u64,fps:i64) {
    let native=unsafe {&mut *context.cast::<NativeOutput>()};
    native.trace.push(2);
    native.calls.push((invocation,fps));
    // Never assert/panic across extern C: an ordinary Rust assertion below checks
    // the captured observation and can distinguish a compiled ordering mutant.
    native.observed_unpublished.push(!native.output.is_null() &&
        unsafe {&*native.output}==&sentinel());
}
unsafe extern "C" fn validate_callback(context:*mut c_void,invocation:u64,
    header:*const codec::Header,atoms:*const codec::Atom,atom_count:u32,
    metadata:*const Metadata,outcome:*const CompletionOutcome,
    edits:*const Edit,edit_count:u32,coordinates:*const Time,coordinate_count:u32)->u32 {
    let native=unsafe {&mut *context.cast::<NativeOutput>()};
    let layout_valid=[
        (header as usize,core::mem::align_of::<codec::Header>()),
        (atoms as usize,core::mem::align_of::<codec::Atom>()),
        (metadata as usize,core::mem::align_of::<Metadata>()),
        (outcome as usize,core::mem::align_of::<CompletionOutcome>()),
        (edits as usize,core::mem::align_of::<Edit>()),
        (coordinates as usize,core::mem::align_of::<Time>()),
    ].into_iter().all(|(address,alignment)|address!=0 && address%alignment==0);
    let counts=[atom_count,edit_count,coordinate_count];
    let bundle=if layout_valid && counts==[179,13,13] {Some(unsafe {Output {
        header:ptr::read(header),atoms:ptr::read(atoms.cast::<[codec::Atom;179]>()),
        metadata:ptr::read(metadata),outcome:ptr::read(outcome),
        edits:ptr::read(edits.cast::<[Edit;13]>()),
        coordinates:ptr::read(coordinates.cast::<[Time;13]>()),
    }})}else{None};
    let unpublished=!native.output.is_null() && unsafe {&*native.output}==&sentinel();
    native.trace.push(1);
    native.validations.push(ValidationObservation {invocation,counts,layout_valid,bundle,unpublished});
    native.validator_reply
}
#[derive(Clone,Copy)]
enum Boundary {Success,ValidatedSuccess,FinalAdopt}
#[derive(Clone,Copy)]
enum Fault { Null(usize), Misaligned(usize), Alias { destination:usize, source:usize } }
fn invoke(boundary:Boundary,r:CompletionRequest,current:codec::Wire,
          prepared:codec::Wire,native:&mut NativeOutput,has_callback:bool,
          counts:[u32;5],fault:Option<Fault>)->(u32,Output) {
    let before=(r,current.clone(),prepared.clone());let mut out=sentinel();
    let mut rp=&r as *const CompletionRequest;let mut ch=&current.header as *const codec::Header;
    let mut ca=current.atoms.as_ptr();let mut ph=&prepared.header as *const codec::Header;
    let mut pa=prepared.atoms.as_ptr();let mut oh=&mut out.header as *mut codec::Header;
    let mut oa=out.atoms.as_mut_ptr();let mut m=&mut out.metadata as *mut Metadata;
    let mut o=&mut out.outcome as *mut CompletionOutcome;
    let mut e=out.edits.as_mut_ptr();let mut c=out.coordinates.as_mut_ptr();
    let original=[rp.cast::<u8>(),ch.cast::<u8>(),ca.cast::<u8>(),ph.cast::<u8>(),pa.cast::<u8>(),oh.cast::<u8>(),oa.cast::<u8>(),m.cast::<u8>(),o.cast::<u8>(),e.cast::<u8>(),c.cast::<u8>()];
    if let Some(fault)=fault {
        let (index,address)=match fault {
            Fault::Null(index)=>(index,ptr::null_mut::<u8>()),
            Fault::Misaligned(index)=>(index,original[index].wrapping_add(1).cast_mut()),
            Fault::Alias {destination,source}=>(destination,original[source].cast_mut()),
        };
        match index {0=>rp=address.cast(),1=>ch=address.cast(),2=>ca=address.cast(),3=>ph=address.cast(),4=>pa=address.cast(),5=>oh=address.cast(),6=>oa=address.cast(),7=>m=address.cast(),8=>o=address.cast(),9=>e=address.cast(),10=>c=address.cast(),_=>panic!("fixture pointer index")}
    }
    native.output=&out as *const Output;
    let cb:Option<OutputCallback>=if has_callback {Some(callback)}else{None};
    let validator:Option<ValidationCallback>=if native.validator_present {Some(validate_callback)}else{None};
    let status=unsafe {match boundary {
        Boundary::Success=>beluga_core_network_adaptation_owner_finish_success(rp,ch,ca,counts[0],ph,pa,counts[1],
            cb,(native as *mut NativeOutput).cast(),oh,oa,counts[2],m,o,e,counts[3],c,counts[4]),
        Boundary::ValidatedSuccess=>beluga_core_network_adaptation_owner_finish_success_validated(rp,ch,ca,counts[0],ph,pa,counts[1],
            validator,cb,(native as *mut NativeOutput).cast(),oh,oa,counts[2],m,o,e,counts[3],c,counts[4]),
        Boundary::FinalAdopt=>beluga_core_network_adaptation_owner_final_adopt(rp,ch,ca,counts[0],ph,pa,counts[1],
            oh,oa,counts[2],m,o,e,counts[3],c,counts[4]),
    }};
    native.output=ptr::null();
    assert_eq!((r,current,prepared),before,"all scalar inputs including both headers remain immutable");
    if status==2 || status==5 {
        assert!(native.validations.is_empty(),"invalid scalar/range result precedes validation");
        assert!(native.calls.is_empty(),"invalid scalar/range result precedes native output");
    }
    (status,out)
}
fn call(boundary:Boundary,r:CompletionRequest,v:Owner,p:Prepared,native:&mut NativeOutput)->(u32,Output) {
    invoke(boundary,r,codec::encode_owner_snapshot(v).unwrap(),
        codec::encode_prepared_continuation(p).unwrap(),native,true,[179,222,179,13,13],None)
}
fn assert_success(out:&Output,r:CompletionRequest,expected:Owner,disposition:u32,
                  route:u32,fps_changed:u32,import:bool) {
    let wire=codec::encode_owner(expected,codec::RESULT).unwrap();
    assert_eq!(out.header,codec::Header {abi:1,domain:2,phase:2,count:179});
    assert_eq!(out.atoms.as_slice(),wire.atoms.as_slice(),
        "manual full179 successor, IEEE payloads and all opaque tail fields");
    assert_eq!(out.metadata,Metadata {abi:1,operation:r.operation,scope:2,read_count:0,
        invocation:r.invocation,revision:expected.revision,peer:expected.policy.peer.unwrap_or(0),
        peer_present:expected.policy.peer.is_some()as u32,route,
        queue_fault:expected.policy.queue.faulted as u32,rtt_fault:expected.policy.rtt.faulted as u32,
        ..Metadata::default()});
    assert_eq!(out.outcome,CompletionOutcome {abi:1,operation:r.operation,invocation:r.invocation,
        disposition,route,fps_changed,reserved:0});
    for (index,value) in times(expected.policy).into_iter().enumerate() {
        let edit=if import {if value.is_some() {
            Edit {action:3,source:2,index:index as u32,..Edit::default()}
        }else{Edit {action:2,..Edit::default()}}}else{Edit {action:1,..Edit::default()}};
        assert_eq!(out.edits[index],edit,"exact corresponding-prepared provenance, not coordinate equality");
        assert_eq!(out.coordinates[index],Time::encode(value));
    }
    assert_eq!(&out.edits[9..],&[Edit::default();4]);
    assert_eq!(&out.coordinates[9..],&[Time::default();4],"evidence and cadence remain unowned sidecars");
}
fn route_code(route:RouteAction)->u32 {match route {RouteAction::Retain=>0,RouteAction::Clear=>1,RouteAction::CopyIncoming=>2}}

#[test]
fn active_completion_raw_layout_domains_and_offsets_are_literal() {
    assert_eq!((core::mem::size_of::<CompletionRequest>(),core::mem::align_of::<CompletionRequest>()),(32,8));
    assert_eq!((core::mem::size_of::<CompletionOutcome>(),core::mem::align_of::<CompletionOutcome>()),(32,8));
    assert_eq!(core::mem::offset_of!(CompletionRequest,current_generation),16);
    assert_eq!(core::mem::offset_of!(CompletionRequest,facts),24);
    assert_eq!(core::mem::offset_of!(CompletionOutcome,fps_changed),24);
    assert_eq!(codec::encode_owner_snapshot(owner()).unwrap().header,
        codec::Header {abi:1,domain:2,phase:1,count:179});
    assert_eq!(codec::encode_prepared_continuation(prepared(owner())).unwrap().header,
        codec::Header {abi:1,domain:4,phase:3,count:222});
}
#[test]
fn active_completion_raw_all_eleven_success_fences_rollback_without_effect_or_import() {
    let seed=owner();let p=prepared(seed);
    for gate in 0..11 {let mut r=request(702);let mut incoming=p;
        match gate {0..=8=>r.facts&=!(1<<gate),9=>r.current_generation=8,_=>incoming.applying_revision=58}
        let mut native=NativeOutput::default();let(status,out)=call(Boundary::Success,r,seed,incoming,&mut native);
        assert_eq!(status,1);assert_success(&out,r,seed,0,0,0,false);
        assert!(native.calls.is_empty());assert!(native.observed_unpublished.is_empty());
    }
}
#[test]
fn active_completion_raw_current_success_records_only_applied_without_policy_revision_or_import() {
    let seed=owner();let p=prepared(seed);let r=request(702);let mut expected=seed;
    expected.applied=Some(p.recommendation);let mut native=NativeOutput::default();
    let(status,out)=call(Boundary::Success,r,seed,p,&mut native);
    assert_eq!(status,1);assert_success(&out,r,expected,1,0,1,false);
    assert_eq!(native.calls,[(93,5)]);assert_eq!(native.observed_unpublished,[true]);
}
#[test]
fn active_completion_raw_same_fps_different_bitrate_records_without_output_callback() {
    let seed=owner();let mut p=prepared(seed);p.recommendation.fps=29;
    p.recommendation.maximum_video=9_000_001;p.recommendation.maximum_total=9_200_001;
    p.recommendation.scale=Scalar::new(7.5);let r=request(702);let mut expected=seed;
    expected.applied=Some(p.recommendation);let mut native=NativeOutput::default();
    let(status,out)=call(Boundary::Success,r,seed,p,&mut native);
    assert_eq!(status,1);assert_success(&out,r,expected,1,0,0,false);assert!(native.calls.is_empty());
}
#[test]
fn active_completion_raw_absent_applied_fps_requires_one_output_before_record() {
    let mut seed=owner();seed.applied=None;let mut p=prepared(seed);p.recommendation.fps=29;
    let r=request(702);let mut expected=seed;expected.applied=Some(p.recommendation);
    let mut native=NativeOutput::default();let(status,out)=call(Boundary::Success,r,seed,p,&mut native);
    assert_eq!(status,1);assert_success(&out,r,expected,1,0,1,false);
    assert_eq!(native.calls,[(93,29)]);assert_eq!(native.observed_unpublished,[true]);
}
#[test]
fn active_completion_raw_nan_payloads_signed_zero_and_negative_opaque_fields_are_not_normalized() {
    for bits in [0x7ff8_0000_0000_00a5,0x7ff0_0000_0000_0042,0x8000_0000_0000_0000,0] {
        let mut seed=owner();seed.policy.last_average_delay=Some(Scalar(bits));
        seed.policy.probe_failures=i64::MIN;seed.policy.probe_cooldown=i64::MAX;
        let mut p=prepared(seed);p.recommendation.scale=Scalar(bits);let r=request(702);
        let mut expected=seed;expected.applied=Some(p.recommendation);let mut native=NativeOutput::default();
        let(status,out)=call(Boundary::Success,r,seed,p,&mut native);
        assert_eq!(status,1);assert_success(&out,r,expected,1,0,1,false);
        assert_eq!(native.calls,[(93,5)]);assert_eq!(native.observed_unpublished,[true]);
    }
}
#[test]
fn active_completion_raw_uses_applying_not_expected_and_does_not_invent_capture_or_policy_guards() {
    let seed=owner();let mut p=prepared(seed);p.expected_revision=u64::MAX;
    p.capture_active=false;p.capacity_only=true;p.policy.peer=None;
    p.policy.queue.faulted=true;p.policy.rtt.faulted=true;p.changed=None;
    let r=request(702);let mut expected=seed;expected.applied=Some(p.recommendation);
    let mut native=NativeOutput::default();let(status,out)=call(Boundary::Success,r,seed,p,&mut native);
    assert_eq!(status,1);assert_success(&out,r,expected,1,0,1,false);
    assert_eq!(native.calls,[(93,5)]);assert_eq!(native.observed_unpublished,[true]);
}
#[test]
fn active_completion_raw_callback_carries_exact_invocation_and_fps_before_every_output_write() {
    let seed=owner();let mut p=prepared(seed);p.recommendation.fps=i32::MIN as i64;
    let mut r=request(702);r.invocation=u64::MAX;let mut expected=seed;expected.applied=Some(p.recommendation);
    let mut native=NativeOutput::default();let(status,out)=call(Boundary::Success,r,seed,p,&mut native);
    assert_eq!(status,1);assert_success(&out,r,expected,1,0,1,false);
    assert_eq!(native.calls,[(u64::MAX,i32::MIN as i64)]);assert_eq!(native.observed_unpublished,[true]);
}
#[test]
fn active_completion_raw_int32_conversion_is_only_for_reachable_changed_fps_effect() {
    for fps in [(i32::MIN as i64)-1,(i32::MAX as i64)+1] {
        let seed=owner();let mut p=prepared(seed);p.recommendation.fps=fps;
        let r=request(702);let mut native=NativeOutput::default();
        let(status,out)=call(Boundary::Success,r,seed,p,&mut native);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.calls.is_empty());
        assert!(native.observed_unpublished.is_empty());

        let mut same=seed;same.applied=Some(Recommendation {fps,..recommendation(29)});
        let mut expected=same;expected.applied=Some(p.recommendation);
        let mut native=NativeOutput::default();let(status,out)=call(Boundary::Success,r,same,p,&mut native);
        assert_eq!(status,1);assert_success(&out,r,expected,1,0,0,false);assert!(native.calls.is_empty());

        let mut stale=r;stale.facts=0;let mut native=NativeOutput::default();
        let(status,out)=call(Boundary::Success,stale,seed,p,&mut native);
        assert_eq!(status,1);assert_success(&out,stale,seed,0,0,0,false);assert!(native.calls.is_empty());
    }
    // Raw shape does not add a 1..240 policy guard. Sender admission is a
    // distinct actual-native boundary; these endpoint values grant no use.
    for fps in [i32::MIN as i64,i32::MAX as i64] {
        let seed=owner();let mut p=prepared(seed);p.recommendation.fps=fps;
        let r=request(702);let mut expected=seed;expected.applied=Some(p.recommendation);
        let mut native=NativeOutput::default();let(status,out)=call(Boundary::Success,r,seed,p,&mut native);
        assert_eq!(status,1);assert_success(&out,r,expected,1,0,1,false);
        assert_eq!(native.calls,[(93,fps)]);assert_eq!(native.observed_unpublished,[true]);
    }
}
#[test]
fn active_completion_raw_callback_is_required_even_for_stale_or_same_fps_result() {
    let seed=owner();
    for stale in [false,true] {let mut p=prepared(seed);p.recommendation.fps=29;
        let mut r=request(702);if stale {r.facts=0;}
        let mut native=NativeOutput::default();let(status,out)=invoke(Boundary::Success,r,
            codec::encode_owner_snapshot(seed).unwrap(),codec::encode_prepared_continuation(p).unwrap(),
            &mut native,false,[179,222,179,13,13],None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.calls.is_empty());
    }
}
#[test]
fn active_completion_raw_final_adopt_imports_all_nine_equal_coordinates_as_corresponding_prepared() {
    let seed=owner();let p=prepared(seed);let r=request(704);let mut expected=seed;
    expected.policy=p.policy;expected.revision=58;let mut native=NativeOutput::default();
    let(status,out)=call(Boundary::FinalAdopt,r,seed,p,&mut native);
    assert_eq!(status,1);assert_success(&out,r,expected,1,2,0,true);assert!(native.calls.is_empty());
    assert_eq!(times(seed.policy),times(p.policy),"fixture distinguishes assignment from numeric equality");
    assert_eq!(&out.atoms[169..],&codec::encode_owner_snapshot(seed).unwrap().atoms[169..]);
}
#[test]
fn active_completion_raw_final_adopt_absent_policy_times_clear_and_all_route_actions_remain_explicit() {
    let seed=owner();let mut p=prepared(seed);p.policy.probe_deadline=None;
    p.policy.probe_qualification_at=None;p.policy.promotion=None;p.policy.floor_first_witness=None;
    p.policy.floor_cooldown_at=None;p.policy.startup_sparse_deadline=None;
    p.policy.queue.low_observation=None;p.policy.queue.soft_observation=None;
    p.policy.rtt.last_advancement=None;p.policy.rtt.raw.advancement_present=0;
    for present in [false,true] {for route in [RouteAction::Retain,RouteAction::Clear,RouteAction::CopyIncoming] {
        p.route_action=route;p.policy.route_present=present;let r=request(704);let mut expected=seed;
        expected.policy=p.policy;expected.revision=58;let mut native=NativeOutput::default();
        let(status,out)=call(Boundary::FinalAdopt,r,seed,p,&mut native);
        assert_eq!(status,1);assert_success(&out,r,expected,1,route_code(route),0,true);
        assert!(native.calls.is_empty());
    }}
}
#[test]
fn active_completion_raw_final_adopt_three_stale_fences_preserve_every_owner_word() {
    let seed=owner();let p=prepared(seed);
    for gate in 0..3 {let mut r=request(704);let mut incoming=p;
        match gate {0=>r.facts=0,1=>r.current_generation=8,_=>incoming.applying_revision=58}
        let mut native=NativeOutput::default();let(status,out)=call(Boundary::FinalAdopt,r,seed,incoming,&mut native);
        assert_eq!(status,1);assert_success(&out,r,seed,0,0,0,false);assert!(native.calls.is_empty());
    }
}
#[test]
fn active_completion_raw_final_adopt_wraps_once_and_preserves_opaque_applied_ieee_tail() {
    let mut seed=owner();seed.revision=u64::MAX;
    seed.applied=Some(Recommendation {scale:Scalar(0x7ff8_0000_0000_007b),..recommendation(29)});
    let mut p=prepared(seed);p.expected_revision=0;p.capture_active=false;
    let r=request(704);let mut expected=seed;expected.policy=p.policy;expected.revision=0;
    let mut native=NativeOutput::default();let(status,out)=call(Boundary::FinalAdopt,r,seed,p,&mut native);
    assert_eq!(status,1);assert_success(&out,r,expected,1,2,0,true);
    assert_eq!(&out.atoms[169..],&codec::encode_owner_snapshot(seed).unwrap().atoms[169..]);
    assert!(native.calls.is_empty());
}
#[test]
fn active_completion_raw_closed_request_headers_and_all401_atoms_are_checked_even_stale() {
    let seed=owner();let p=prepared(seed);
    let current=codec::encode_owner_snapshot(seed).unwrap();let proposed=codec::encode_prepared_continuation(p).unwrap();
    for boundary in [Boundary::Success,Boundary::ValidatedSuccess,Boundary::FinalAdopt] {
        let operation=if matches!(boundary,Boundary::FinalAdopt){704}else{702};
        let mut r=request(operation);r.facts=0;
        for mode in 0..7 {let mut bad=r;
            match mode {0=>bad.abi=2,1=>bad.operation=703,2=>bad.invocation=0,
                3=>bad.facts=if operation==702{512}else{2},4=>bad.facts=u32::MAX,
                5=>bad.reserved=1,_=>bad.operation=if operation==702{704}else{702}}
            let mut native=NativeOutput::default();let(status,out)=invoke(boundary,bad,current.clone(),proposed.clone(),
                &mut native,true,[179,222,179,13,13],None);
            assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.calls.is_empty());
        }
        for domain in 0..2 {for index in 0..if domain==0{179}else{222} {for mode in 0..2 {
            let mut a=current.clone();let mut b=proposed.clone();
            let atom=if domain==0{&mut a.atoms[index]}else{&mut b.atoms[index]};
            if mode==0{atom.kind=0;}else{atom.present=2;}
            let mut native=NativeOutput::default();let(status,out)=invoke(boundary,r,a,b,&mut native,true,[179,222,179,13,13],None);
            assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.calls.is_empty());
        }}}
        for domain in 0..2 {for mode in 0..5 {let mut a=current.clone();let mut b=proposed.clone();
            let h=if domain==0{&mut a.header}else{&mut b.header};
            match mode {0=>h.abi=0,1=>h.domain=0,2=>h.phase=0,3=>h.count=0,
                _=>h.phase=if domain==0{2}else{1}}
            let mut native=NativeOutput::default();let(status,out)=invoke(boundary,r,a,b,&mut native,true,[179,222,179,13,13],None);
            assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.calls.is_empty());
        }}
    }
}
#[test]
fn active_completion_raw_pointer_count_overlap_and_late_shape_denials_never_call_output_or_publish() {
    let seed=owner();let p=prepared(seed);
    let current=codec::encode_owner_snapshot(seed).unwrap();let proposed=codec::encode_prepared_continuation(p).unwrap();
    for boundary in [Boundary::Success,Boundary::ValidatedSuccess,Boundary::FinalAdopt] {
        let r=request(if matches!(boundary,Boundary::FinalAdopt){704}else{702});
        for index in 0..5 {let valid=[179,222,179,13,13];
            for bad in [0,valid[index]-1,valid[index]+1,u32::MAX] {let mut counts=valid;counts[index]=bad;
            let mut native=NativeOutput::default();let(status,out)=invoke(boundary,r,current.clone(),proposed.clone(),
                &mut native,true,counts,None);
            assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.calls.is_empty());
        }}
        for fault in (0..11).map(Fault::Null).chain((0..11).map(Fault::Misaligned)).chain(
            (0..11).flat_map(|destination|(0..11).filter(move|source|*source!=destination)
                .map(move|source|Fault::Alias {destination,source}))) {
            let mut native=NativeOutput::default();let(status,out)=invoke(boundary,r,current.clone(),proposed.clone(),
                &mut native,true,[179,222,179,13,13],Some(fault));
            assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.calls.is_empty());
        }
        // The last prepared diagnostic word is malformed after every success
        // fence would pass; all decoding must nevertheless precede native output.
        let mut bad=proposed.clone();bad.atoms[221].present=2;
        let mut native=NativeOutput::default();let(status,out)=invoke(boundary,r,current.clone(),bad,
            &mut native,true,[179,222,179,13,13],None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.calls.is_empty());
    }
}

fn assert_validation(native:&NativeOutput,r:CompletionRequest,expected:Owner,
                     disposition:u32,fps_changed:u32) {
    assert_eq!(native.validations.len(),1,"one actual private bundle per evaluated result");
    let observed=&native.validations[0];
    assert_eq!(observed.invocation,r.invocation);
    assert_eq!(observed.counts,[179,13,13]);assert!(observed.layout_valid);
    assert!(observed.unpublished,"six caller destinations remain sentinel during validation");
    assert_success(observed.bundle.as_ref().expect("complete borrowed private bundle"),
        r,expected,disposition,0,fps_changed,false);
}
#[test]
fn active_completion_validated_private_full_bundle_precedes_fps_and_all_publication() {
    for absent in [false,true] {for bits in [0x7ff8_0000_0000_00a5,0x7ff0_0000_0000_0042,
        0x8000_0000_0000_0000,0] {
        let mut seed=owner();if absent {seed.applied=None;}
        seed.policy.last_average_delay=Some(Scalar(bits));seed.policy.probe_failures=i64::MIN;
        let mut p=prepared(seed);p.recommendation.scale=Scalar(bits);
        let r=request(702);let mut expected=seed;expected.applied=Some(p.recommendation);
        let mut native=NativeOutput::default();
        let(status,out)=call(Boundary::ValidatedSuccess,r,seed,p,&mut native);
        assert_eq!(status,1);assert_success(&out,r,expected,1,0,1,false);
        assert_validation(&native,r,expected,1,1);
        assert_eq!(native.validations[0].bundle.as_ref(),Some(&out));
        assert_eq!(native.trace,[1,2]);assert_eq!(native.calls,[(93,5)]);
        assert_eq!(native.observed_unpublished,[true]);
        let mut legacy=NativeOutput::default();let(old_status,old)=call(Boundary::Success,r,seed,p,&mut legacy);
        assert_eq!(old_status,1);assert_eq!(old,out);assert_eq!(legacy.trace,[2]);
        assert!(legacy.validations.is_empty());
    }}
}
#[test]
fn active_completion_validated_stale_same_fps_and_missing_thunks_are_explicit() {
    let seed=owner();
    for gate in 0..12 {let mut r=request(702);let mut p=prepared(seed);
        match gate {0..=8=>r.facts&=!(1<<gate),9=>r.current_generation=8,
            10=>p.applying_revision=58,_=>p.recommendation.fps=29}
        let mut expected=seed;if gate==11 {expected.applied=Some(p.recommendation);}
        let mut native=NativeOutput::default();
        let(status,out)=call(Boundary::ValidatedSuccess,r,seed,p,&mut native);
        assert_eq!(status,1);assert_success(&out,r,expected,(gate==11)as u32,0,0,false);
        assert_validation(&native,r,expected,(gate==11)as u32,0);
        assert_eq!(native.trace,[1]);assert!(native.calls.is_empty());
    }
    for mode in 0..3 {let mut r=request(702);let mut p=prepared(seed);
        if mode==1 {r.facts=0;}if mode==2 {p.recommendation.fps=29;}
        for (has_validator,has_output) in [(false,true),(true,false),(false,false)] {
            let mut native=NativeOutput {validator_present:has_validator,..NativeOutput::default()};
            let(status,out)=invoke(Boundary::ValidatedSuccess,r,codec::encode_owner_snapshot(seed).unwrap(),
                codec::encode_prepared_continuation(p).unwrap(),&mut native,has_output,[179,222,179,13,13],None);
            assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.trace.is_empty());
        }
    }
}
#[test]
fn active_completion_validated_only_one_accepts_and_denial_never_effects_or_writes() {
    for reply in [0,2,u32::MAX] {for mode in 0..3 {
        let seed=owner();let mut r=request(702);let mut p=prepared(seed);
        if mode==1 {r.facts=0;}if mode==2 {p.recommendation.fps=29;}
        let mut expected=seed;if mode!=1 {expected.applied=Some(p.recommendation);}
        let mut native=NativeOutput {validator_reply:reply,..NativeOutput::default()};
        let(status,out)=call(Boundary::ValidatedSuccess,r,seed,p,&mut native);
        assert_eq!(status,3);assert_eq!(out,sentinel());
        assert_validation(&native,r,expected,(mode!=1)as u32,(mode==0)as u32);
        assert_eq!(native.trace,[1]);assert!(native.calls.is_empty());
        assert!(native.observed_unpublished.is_empty());
    }}
}
#[test]
fn active_completion_validated_int32_and_invocation_correlation_are_pre_effect() {
    for fps in [(i32::MIN as i64)-1,i32::MIN as i64,i32::MAX as i64,(i32::MAX as i64)+1] {
        for mode in 0..3 {let mut seed=owner();let mut p=prepared(seed);p.recommendation.fps=fps;
            let mut r=request(702);r.invocation=u64::MAX;
            if mode==1 {r.facts=0;}if mode==2 {seed.applied=Some(Recommendation {fps,..recommendation(29)});}
            let mut native=NativeOutput::default();
            let(status,out)=call(Boundary::ValidatedSuccess,r,seed,p,&mut native);
            if mode==0 && (fps<i32::MIN as i64 || fps>i32::MAX as i64) {
                assert_eq!(status,2);assert_eq!(out,sentinel());assert!(native.trace.is_empty());
                continue;
            }
            let mut expected=seed;if mode!=1 {expected.applied=Some(p.recommendation);}
            assert_eq!(status,1);assert_success(&out,r,expected,(mode!=1)as u32,0,(mode==0)as u32,false);
            assert_validation(&native,r,expected,(mode!=1)as u32,(mode==0)as u32);
            assert_eq!(native.trace,if mode==0 {vec![1,2]}else{vec![1]});
            assert_eq!(native.calls,if mode==0 {vec![(u64::MAX,fps)]}else{Vec::new()});
        }
    }
}
