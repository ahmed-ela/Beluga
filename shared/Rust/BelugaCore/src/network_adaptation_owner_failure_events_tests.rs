//! Public scalar API post-await failure fixtures. Manual full179 successors and raw
//! journals distinguish deliberately live semantic-error prefixes from shape
//! rejection. No reducer generates expectations; no native effect is exercised.
use core::{ffi::c_void, ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Reply, Metadata, Callback};
use crate::network_adaptation_owner_failure_events::*;
const MS:i128=1_000_000_000_000_000;

fn request()->FailureRequest {FailureRequest {abi:1,operation:703,invocation:93,current_generation:1,facts:511,reserved:0}}
fn owner()->Owner {
    let mut v=Owner::new(50_000_000,60,Dependencies::default());v.revision=57;
    v.fast_statistics_available=true;v.evidence_lane=Some(EvidenceLane::OrdinaryFallback);
    v.last_evidence=Some(-7_000_000_000_000_000_001);v.freshness.minimum=Some(31);
    v.applied=Some(Recommendation {tier:Tier::Balanced,maximum_video:1_234_567,
        maximum_total:2_345_678,fps:29,scale:Scalar::new(1.5)});
    let p=&mut v.policy;p.peer=Some(1);p.tier=Tier::AudioPriority;p.route_present=true;
    p.floor_show=Some(7);p.floor_reserved=true;p.floor_active=false;
    p.startup_peer=Some(1);p.startup_show=Some(7);p.startup_sparse_deadline=Some(46);
    p.floor_first_witness=Some(FloorWitness {observed_at:44,bandwidth:Scalar::new(306_000.0)});
    p.floor_cooldown_at=Some(45);p.consumed_sequence=Some(39);
    p.floor_regular_sequence=Some(39);p.floor_regular_timestamp=Some(Scalar::new(39_000_000.0));
    p.capacity_sequence=Some(39);p.capacity_timestamp=Some(Scalar::new(39_000_000.0));
    p.queue.packets=Some(30);p.queue.delay_bits=Some(0.0_f64.to_bits());
    p.queue.low_observation=Some(47);p.queue.soft_observation=Some(48);v
}
fn healthy(mut v:Owner)->Owner {
    let r=&mut v.policy.rtt.raw;r.baseline_present=1;r.baseline_bits=0.004_f64.to_bits();
    r.disposition=2;r.health=1;r.uses_native=1;r.permits_initial=0;r.distinct_count=3;
    r.last_measured_present=1;r.last_measured_bits=0.004_f64.to_bits();
    r.advancement_present=1;r.age_present=1;r.watermark_present=1;
    r.fence_present=1;r.fence_current_present=1;
    r.watermark=crate::rtt_evidence::RawMeasurement {fingerprint_words:[0x6161_6161_6161_6161;8],
        total_bits:0.012_f64.to_bits(),responses:3};
    r.fence=r.watermark;r.fence_current_bits=0.004_f64.to_bits();v.policy.rtt.last_advancement=Some(49);v
}
fn probe(mut v:Owner)->Owner {
    let p=&mut v.policy;p.tier=Tier::Survival;p.probe_origin=Some(Tier::AudioPriority);
    p.probe_deadline=Some(3_500*MS);p.probe_qualification_at=Some(43);
    p.probe_best=Some(Tier::Survival);p.probe_confirmed=Some(Tier::Survival);
    p.probe_maximum=Some(612_000);p.probe_healthy=1;p.probe_grace=7;
    p.floor_seed=Some(Scalar::new(306_000.0));
    p.promotion=Some(Promotion {tier:Tier::Survival,maximum_total:712_000,deadline:42});
    p.capacity_bandwidth_high=Some(Scalar::new(306_000.0));
    p.capacity_sample=Some(CapacitySample {packets:Some(30),delay:Some(Scalar::new(0.0))});
    p.healthy_upgrades=8;p.limited_upgrades=9;v
}
fn prepared(v:Owner)->Prepared {
    Prepared {policy:v.policy,source_generation:1,expected_revision:v.revision,
        applying_revision:v.revision,lane:ProposalLane::Regular,capture_active:true,
        capacity_only:false,changed:None,recommendation:Recommendation {tier:Tier::Survival,
            maximum_video:111_222,maximum_total:333_444,fps:5,scale:Scalar::new(4.0)},
        route_action:RouteAction::CopyIncoming,floor_diagnostics:None,capacity_diagnostics:None}
}
fn negative(mut p:Prepared)->Prepared {
    p.policy.startup_disproved=true;p.policy.floor_attempt_consumed=true;
    p.policy.floor_regular_sequence=Some(41);p.policy.floor_regular_timestamp=Some(Scalar::new(41_000_000.0));
    p.policy.probe_deadline=Some(9_999*MS);p.policy.queue.low_observation=Some(9_998*MS);
    p.policy.rtt.last_advancement=Some(9_997*MS);p.policy.probe_maximum=Some(999_999);p
}
fn negative_prefix(v:&mut Owner,p:Prepared) {
    v.policy.startup_disproved=true;v.policy.startup_sparse_deadline=None;
    v.policy.floor_attempt_consumed=true;v.policy.floor_first_witness=None;
    v.policy.floor_regular_sequence=p.policy.floor_regular_sequence;
    v.policy.floor_regular_timestamp=p.policy.floor_regular_timestamp;
}
fn before_q(p:&mut Policy) {
    p.floor_probe_cancelled=true;p.floor_seed=None;p.tier=Tier::AudioPriority;
    p.floor_first_witness=None;p.capacity_sample=None;p.capacity_bandwidth_high=None;p.promotion=None;
}
fn after_q(p:&mut Policy) {
    p.queue.pressure_count=0;p.queue.low_observation=None;p.queue.soft_observation=None;
    p.probe_origin=None;p.probe_confirmed=None;p.probe_qualification_at=None;
    p.probe_best=None;p.probe_maximum=None;p.probe_healthy=0;p.probe_grace=0;
    p.probe_deadline=None;p.promotion=None;p.startup_disproved=true;p.startup_sparse_deadline=None;
    p.healthy_upgrades=0;p.limited_upgrades=0;
}
fn values(p:Policy)->[Option<i128>;9] {
    [p.probe_deadline,p.probe_qualification_at,p.promotion.map(|v|v.deadline),
        p.floor_first_witness.map(|v|v.observed_at),p.floor_cooldown_at,p.startup_sparse_deadline,
        p.queue.low_observation,p.queue.soft_observation,p.rtt.last_advancement]
}
#[derive(Clone,Debug,PartialEq,Eq)]
struct Output {
    header:codec::Header,atoms:[codec::Atom;179],metadata:Metadata,outcome:FailureOutcome,
    edits:[Edit;13],coordinates:[Time;13],reads:[Reply;15],
}
fn sentinel()->Output {
    Output {header:codec::Header {abi:91,domain:92,phase:93,count:94},
        atoms:[codec::Atom {kind:91,present:92,high:-93,low:94};179],
        metadata:Metadata {abi:91,operation:92,scope:93,read_count:94,invocation:95,revision:96,
            peer:97,peer_present:98,bound:99,route:100,sample:101,enabled:102,lease:103,queue_fault:104,rtt_fault:105},
        outcome:FailureOutcome {abi:91,operation:92,invocation:93,disposition:94,route:95,semantic_error:96,attempted_reads:97},
        edits:[Edit {action:91,source:92,index:93,ordinal:94,high:-95,low:96};13],
        coordinates:[Time {present:91,reserved:92,high:-93,low:94};13],
        reads:[Reply {abi:91,status:92,site:93,ordinal:94,invocation:95,high:-96,low:97,reserved:98};15]}
}
#[derive(Default)]
struct Provider {calls:Vec<(u64,u32,u32)>,fault:Option<(u32,u32)>}
unsafe extern "C" fn callback(context:*mut c_void,invocation:u64,site:u32,ordinal:u32,out:*mut Reply)->u32 {
    let p=unsafe {&mut *context.cast::<Provider>()};p.calls.push((invocation,site,ordinal));
    let mode=p.fault.filter(|v|v.0==ordinal).map(|v|v.1);
    let value=(100+ordinal as i128)*MS;
    let mut reply=Reply {abi:1,status:1,site,ordinal,invocation,high:(value>>64)as i64,low:value as u64,reserved:0};
    match mode {Some(1)=>reply.abi=2,Some(2)=>reply.status=2,Some(3)=>reply.site=site^1,
        Some(4)=>reply.ordinal=ordinal+1,Some(5)=>reply.invocation=invocation^1,Some(6)=>reply.reserved=1,
        Some(7)=>{reply.high=i64::MAX;reply.low=u64::MAX;},_=>{}}
    unsafe {ptr::write(out,reply);}match mode {Some(0)=>0,Some(8)=>2,Some(9)=>u32::MAX,_=>1}
}
#[derive(Clone,Copy)]
enum Fault { Null(usize), Misaligned(usize), Alias { destination:usize, source:usize } }
fn invoke(r:FailureRequest,current:codec::Wire,prepared:codec::Wire,p:&mut Provider,
          cb:bool,counts:[u32;6],fault:Option<Fault>)->(u32,Output) {
    let before=(r,current.clone(),prepared.clone());let mut out=sentinel();
    let mut rp=&r as *const FailureRequest;let mut ch=&current.header as *const codec::Header;
    let mut ca=current.atoms.as_ptr();let mut ph=&prepared.header as *const codec::Header;let mut pa=prepared.atoms.as_ptr();
    let mut oh=&mut out.header as *mut codec::Header;let mut oa=out.atoms.as_mut_ptr();
    let mut m=&mut out.metadata as *mut Metadata;let mut o=&mut out.outcome as *mut FailureOutcome;
    let mut e=out.edits.as_mut_ptr();let mut c=out.coordinates.as_mut_ptr();let mut t=out.reads.as_mut_ptr();
    let original=[rp.cast::<u8>(),ch.cast::<u8>(),ca.cast::<u8>(),ph.cast::<u8>(),pa.cast::<u8>(),oh.cast::<u8>(),oa.cast::<u8>(),m.cast::<u8>(),o.cast::<u8>(),e.cast::<u8>(),c.cast::<u8>(),t.cast::<u8>()];
    if let Some(fault)=fault {
        let (index,address)=match fault {
            Fault::Null(index)=>(index,ptr::null_mut::<u8>()),
            Fault::Misaligned(index)=>(index,original[index].wrapping_add(1).cast_mut()),
            Fault::Alias {destination,source}=>(destination,original[source].cast_mut()),
        };
        match index {0=>rp=address.cast(),1=>ch=address.cast(),2=>ca=address.cast(),3=>ph=address.cast(),4=>pa=address.cast(),5=>oh=address.cast(),6=>oa=address.cast(),7=>m=address.cast(),8=>o=address.cast(),9=>e=address.cast(),10=>c=address.cast(),11=>t=address.cast(),_=>panic!("fixture pointer index")}
    }
    let cb:Option<Callback>=if cb{Some(callback)}else{None};
    let status=unsafe {beluga_core_network_adaptation_owner_finish_failure(rp,ch,ca,counts[0],ph,pa,counts[1],cb,
        (p as *mut Provider).cast(),oh,oa,counts[2],m,o,e,counts[3],c,counts[4],t,counts[5])};
    assert_eq!((r,current,prepared),before,"immutable request, full179 and full222 inputs");(status,out)
}
fn call(r:FailureRequest,v:Owner,p:Prepared,provider:&mut Provider)->(u32,Output) {
    invoke(r,codec::encode_owner_snapshot(v).unwrap(),codec::encode_prepared_continuation(p).unwrap(),
        provider,true,[179,222,179,13,13,15],None)
}
fn assert_output(out:&Output,r:FailureRequest,expected:Owner,disposition:u32,route:u32,error:u32,
                 accepted:&[u32],attempted:u32,clear:u16,import:bool) {
    let wire=codec::encode_owner(expected,codec::RESULT).unwrap();
    assert_eq!(out.header,codec::Header {abi:1,domain:2,phase:2,count:179});
    assert_eq!(out.atoms.as_slice(),wire.atoms.as_slice(),"manual failure full179 successor and live partial prefix");
    assert_eq!(out.metadata,Metadata {abi:1,operation:703,scope:2,read_count:accepted.len()as u32,
        invocation:r.invocation,revision:expected.revision,peer:expected.policy.peer.unwrap_or(0),
        peer_present:expected.policy.peer.is_some()as u32,route,queue_fault:expected.policy.queue.faulted as u32,
        rtt_fault:expected.policy.rtt.faulted as u32,..Metadata::default()});
    assert_eq!(out.outcome,FailureOutcome {abi:1,operation:703,invocation:r.invocation,
        disposition,route,semantic_error:error,attempted_reads:attempted});
    for (index,value) in values(expected.policy).into_iter().enumerate() {
        let edit=if import {if value.is_some(){Edit {action:3,source:2,index:index as u32,..Edit::default()}}
            else{Edit {action:2,..Edit::default()}}}
            else{Edit {action:if clear&(1<<index)!=0{2}else{1},..Edit::default()}};
        assert_eq!(out.edits[index],edit,"manual exact nine-slot Clear/Retain/import actions");
        assert_eq!(out.coordinates[index],Time::encode(value));
    }
    assert_eq!(&out.edits[9..],&[Edit::default();4]);assert_eq!(&out.coordinates[9..],&[Time::default();4]);
    let mut reads=[Reply::default();15];
    for (ordinal,site) in accepted.iter().copied().enumerate() {let value=(100+ordinal as i128)*MS;
        reads[ordinal]=Reply {abi:1,status:1,site,ordinal:ordinal as u32,invocation:r.invocation,
            high:(value>>64)as i64,low:value as u64,reserved:0};}
    assert_eq!(out.reads,reads,"accepted replies only; rejected attempts and unused tail are zero");
}
fn assert_calls(p:&Provider,r:FailureRequest,tags:&[u32]) {
    let calls:Vec<_>=tags.iter().copied().enumerate().map(|(i,site)|(r.invocation,site,i as u32)).collect();
    assert_eq!(p.calls,calls,"exact lazy attempted transcript, including one rejected cut");
}

#[test]
fn active_failure_raw_layout_domains_and_offsets_are_literal() {
    assert_eq!((core::mem::size_of::<FailureRequest>(),core::mem::align_of::<FailureRequest>()),(32,8));
    assert_eq!((core::mem::size_of::<FailureOutcome>(),core::mem::align_of::<FailureOutcome>()),(32,8));
    assert_eq!(core::mem::offset_of!(FailureRequest,current_generation),16);
    assert_eq!(core::mem::offset_of!(FailureRequest,facts),24);
    assert_eq!(core::mem::offset_of!(FailureOutcome,semantic_error),24);
    assert_eq!(core::mem::offset_of!(FailureOutcome,attempted_reads),28);
    assert_eq!(codec::encode_owner_snapshot(owner()).unwrap().header,codec::Header {abi:1,domain:2,phase:1,count:179});
    assert_eq!(codec::encode_prepared_continuation(prepared(owner())).unwrap().header,codec::Header {abi:1,domain:4,phase:3,count:222});
}
#[test]
fn active_failure_raw_all_eleven_currentness_denials_skip_retention_and_clock_attempts() {
    let seed=healthy(probe(owner()));let mut p=negative(prepared(seed));p.capacity_only=true;p.policy.capacity_sequence=Some(42);
    for gate in 0..11 {let mut r=request();let mut incoming=p;
        match gate {0..=8=>r.facts&=!(1<<gate),9=>r.current_generation=2,_=>incoming.applying_revision=58}
        let mut provider=Provider::default();let(status,out)=call(r,seed,incoming,&mut provider);
        assert_eq!(status,1);assert_output(&out,r,seed,0,0,0,&[],0,0,false);assert_calls(&provider,r,&[]);
    }
}
#[test]
fn active_failure_raw_ordinary_uses_applying_and_retains_only_negative_prefix_without_clocks() {
    let seed=healthy(probe(owner()));let mut p=negative(prepared(seed));p.expected_revision=999;p.capture_active=false;
    p.route_action=RouteAction::CopyIncoming;p.policy.route_present=false;
    let mut expected=seed;negative_prefix(&mut expected,p);expected.revision=58;let r=request();
    let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,expected,1,0,0,&[],0,0x28,false);assert_calls(&provider,r,&[]);
}
#[test]
fn active_failure_raw_both_terminal_branches_import_complete_policy_and_literal_optional_routes() {
    for capacity in [false,true] {for route in [0,1,2] {for present in [false,true] {
        let seed=healthy(probe(owner()));let mut p=negative(prepared(seed));p.capacity_only=capacity;
        if capacity{p.policy.probe_origin=None;}else{p.policy.floor_probe_cancelled=true;}
        p.policy.route_present=present;p.route_action=match route {0=>RouteAction::Retain,1=>RouteAction::Clear,_=>RouteAction::CopyIncoming};
        p.policy.floor_cooldown_at=None;let mut expected=seed;expected.policy=p.policy;expected.revision=58;
        let r=request();let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
        assert_eq!(status,1);assert_output(&out,r,expected,3,route,0,&[],0,0,true);assert_calls(&provider,r,&[]);
    }}}
}
#[test]
fn active_failure_raw_fast_identity_and_independent_sequence_guards_skip_F_after_negative_retention() {
    let seed=healthy(probe(owner()));
    for gate in 0..6 {let mut p=negative(prepared(seed));p.capacity_only=true;p.policy.capacity_sequence=Some(42);
        match gate {0=>p.policy.capacity_sequence=None,1=>p.policy.peer=Some(2),
            2=>p.policy.probe_origin=Some(Tier::Survival),3=>p.policy.capacity_sequence=Some(39),
            4=>p.policy.capacity_sequence=Some(38),_=>p.policy.capacity_sequence=Some(0)}
        let mut expected=seed;if gate!=1{negative_prefix(&mut expected,p);}expected.revision=58;
        let r=request();let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
        assert_eq!(status,1);assert_output(&out,r,expected,2,0,0,&[],0,if gate==1{0}else{0x28},false);assert_calls(&provider,r,&[]);
    }
    for consumed in [false,true] {let mut seed=healthy(probe(owner()));
        seed.policy.consumed_sequence=Some(if consumed{40}else{38});seed.policy.capacity_sequence=Some(if consumed{38}else{40});
        let mut p=negative(prepared(seed));p.capacity_only=true;p.policy.capacity_sequence=Some(40);
        let mut expected=seed;negative_prefix(&mut expected,p);expected.revision=58;
        let r=request();let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
        assert_eq!(status,1);assert_output(&out,r,expected,2,0,0,&[],0,0x28,false);assert_calls(&provider,r,&[]);
    }
    let seed=healthy(owner());let mut p=negative(prepared(seed));p.capacity_only=true;p.policy.capacity_sequence=Some(42);
    p.policy.probe_origin=None;let mut expected=seed;negative_prefix(&mut expected,p);expected.revision=58;
    let r=request();let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,expected,2,0,0,&[],0,0x28,false);assert_calls(&provider,r,&[]);
}
#[test]
fn active_failure_raw_native_timestamp_max_preserves_nan_selection_and_signed_zero_ties() {
    for (current,incoming,selected) in [
        (0x7ff8_0000_0000_0042,42_000_000.0_f64.to_bits(),0x7ff8_0000_0000_0042),
        (39_000_000.0_f64.to_bits(),0x7ff8_0000_0000_0043,39_000_000.0_f64.to_bits()),
        (0,0x8000_0000_0000_0000,0x8000_0000_0000_0000),(0x8000_0000_0000_0000,0,0)] {
        let mut seed=owner();seed.policy.floor_regular_timestamp=Some(Scalar(current));
        let mut p=negative(prepared(seed));p.policy.floor_regular_timestamp=Some(Scalar(incoming));
        let mut expected=seed;negative_prefix(&mut expected,p);expected.policy.floor_regular_timestamp=Some(Scalar(selected));expected.revision=58;
        let r=request();let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
        assert_eq!(status,1);assert_output(&out,r,expected,1,0,0,&[],0,0x28,false);assert_calls(&provider,r,&[]);
    }
}
#[test]
fn active_failure_raw_F_denial_publishes_negative_and_capacity_prefix_without_demand_or_revision() {
    let seed=healthy(probe(owner()));let mut p=negative(prepared(seed));p.capacity_only=true;
    p.policy.capacity_sequence=Some(42);p.policy.capacity_timestamp=Some(Scalar::new(42_000_000.0));p.policy.demand.faulted=true;
    let mut expected=seed;negative_prefix(&mut expected,p);expected.policy.capacity_sequence=Some(42);expected.policy.capacity_timestamp=p.policy.capacity_timestamp;
    let r=request();let mut provider=Provider {fault:Some((0,0)),..Default::default()};let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,expected,4,0,3,&[],1,0x28,false);assert_calls(&provider,r,&[4]);
}
#[test]
fn active_failure_raw_successful_F_copies_only_fence_without_positive_times_or_budget() {
    let seed=healthy(probe(owner()));let mut p=negative(prepared(seed));p.capacity_only=true;p.policy.capacity_sequence=Some(42);
    p.policy.capacity_timestamp=Some(Scalar::new(-0.0));p.policy.rtt.raw.fence.fingerprint_words=[0x6262_6262_6262_6262;8];
    p.policy.rtt.raw.fence.total_bits=0.020_f64.to_bits();p.policy.rtt.raw.fence.responses=4;p.policy.rtt.raw.fence_current_bits=0.005_f64.to_bits();
    let mut expected=seed;negative_prefix(&mut expected,p);expected.policy.capacity_sequence=Some(42);expected.policy.capacity_timestamp=p.policy.capacity_timestamp;
    expected.policy.rtt.raw.fence=p.policy.rtt.raw.fence;expected.policy.rtt.raw.fence_current_bits=p.policy.rtt.raw.fence_current_bits;expected.revision=58;
    let r=request();let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,expected,2,0,0,&[4],1,0x28,false);assert_calls(&provider,r,&[4]);
}
#[test]
fn active_failure_raw_FQ_denials_keep_live_pre_Q_prefix_and_success_alone_finishes_cleanup() {
    let mut seed=healthy(probe(owner()));seed.policy.rtt.raw.advancement_present=0;
    let mut p=negative(prepared(seed));p.capacity_only=true;p.policy.capacity_sequence=Some(42);p.policy.capacity_timestamp=Some(Scalar::new(42_000_000.0));
    for ordinal in 0..2 {let mut expected=seed;negative_prefix(&mut expected,p);
        expected.policy.capacity_sequence=Some(42);expected.policy.capacity_timestamp=p.policy.capacity_timestamp;
        if ordinal==1{expected.policy.rtt.faulted=true;before_q(&mut expected.policy);}
        let r=request();let mut provider=Provider {fault:Some((ordinal,0)),..Default::default()};let(status,out)=call(r,seed,p,&mut provider);
        assert_eq!(status,1);assert_output(&out,r,expected,4,0,3,if ordinal==0{&[]}else{&[4]},ordinal+1,if ordinal==0{0x28}else{0x2c},false);
        assert_calls(&provider,r,&[4,2][..=ordinal as usize]);
    }
    let mut expected=seed;negative_prefix(&mut expected,p);expected.policy.capacity_sequence=Some(42);expected.policy.capacity_timestamp=p.policy.capacity_timestamp;
    expected.policy.rtt.faulted=true;before_q(&mut expected.policy);after_q(&mut expected.policy);expected.revision=58;
    let r=request();let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,expected,2,0,0,&[4,2],2,0xef,false);assert_calls(&provider,r,&[4,2]);
}
#[test]
fn active_failure_raw_observed_rtt_fault_skips_F_and_Q_denial_retains_its_live_prefix() {
    let seed=healthy(probe(owner()));let mut p=negative(prepared(seed));p.capacity_only=true;
    p.policy.capacity_sequence=Some(42);p.policy.capacity_timestamp=None;p.policy.rtt.faulted=true;
    let mut prefix=seed;negative_prefix(&mut prefix,p);prefix.policy.capacity_sequence=Some(42);prefix.policy.capacity_timestamp=None;
    prefix.policy.rtt.faulted=true;before_q(&mut prefix.policy);let r=request();
    let mut provider=Provider {fault:Some((0,0)),..Default::default()};let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,prefix,4,0,3,&[],1,0x2c,false);assert_calls(&provider,r,&[2]);
    let mut expected=prefix;after_q(&mut expected.policy);expected.revision=58;
    let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,expected,2,0,0,&[2],1,0xef,false);assert_calls(&provider,r,&[2]);
}
#[test]
fn active_failure_raw_demand_fault_is_live_only_after_accepted_F_and_before_Q() {
    let seed=healthy(probe(owner()));let mut p=negative(prepared(seed));p.capacity_only=true;
    p.policy.capacity_sequence=Some(42);p.policy.demand.faulted=true;
    for ordinal in 0..2 {let mut expected=seed;negative_prefix(&mut expected,p);
        expected.policy.capacity_sequence=Some(42);expected.policy.capacity_timestamp=p.policy.capacity_timestamp;
        if ordinal==1{expected.policy.demand.faulted=true;before_q(&mut expected.policy);}
        let r=request();let mut provider=Provider {fault:Some((ordinal,0)),..Default::default()};let(status,out)=call(r,seed,p,&mut provider);
        assert_eq!(status,1);assert_output(&out,r,expected,4,0,3,if ordinal==0{&[]}else{&[4]},ordinal+1,if ordinal==0{0x28}else{0x2c},false);
        assert_calls(&provider,r,&[4,2][..=ordinal as usize]);
    }
    let mut expected=seed;negative_prefix(&mut expected,p);expected.policy.capacity_sequence=Some(42);expected.policy.capacity_timestamp=p.policy.capacity_timestamp;
    expected.policy.demand.faulted=true;before_q(&mut expected.policy);after_q(&mut expected.policy);expected.revision=58;
    let r=request();let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,expected,2,0,0,&[4,2],2,0xef,false);assert_calls(&provider,r,&[4,2]);
}
#[test]
fn active_failure_raw_revision_wrap_waits_for_complete_retention_and_absent_timestamp_stays_absent() {
    let mut seed=healthy(probe(owner()));seed.revision=u64::MAX;
    let mut p=negative(prepared(seed));p.capacity_only=true;p.policy.capacity_sequence=Some(u64::MAX);p.policy.capacity_timestamp=None;
    let mut prefix=seed;negative_prefix(&mut prefix,p);prefix.policy.capacity_sequence=Some(u64::MAX);prefix.policy.capacity_timestamp=None;
    let r=request();let mut provider=Provider {fault:Some((0,0)),..Default::default()};let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,prefix,4,0,3,&[],1,0x28,false);assert_calls(&provider,r,&[4]);
    let mut expected=prefix;expected.revision=0;let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_output(&out,r,expected,2,0,0,&[4],1,0x28,false);assert_calls(&provider,r,&[4]);
}
#[test]
fn active_failure_raw_provider_denial_correlation_and_bad_coordinate_publish_not_discard_F_prefix() {
    let seed=healthy(probe(owner()));let mut p=negative(prepared(seed));p.capacity_only=true;p.policy.capacity_sequence=Some(42);
    p.policy.demand.faulted=true;let mut expected=seed;negative_prefix(&mut expected,p);expected.policy.capacity_sequence=Some(42);
    expected.policy.capacity_timestamp=p.policy.capacity_timestamp;
    for mode in 0..10 {let r=request();let mut provider=Provider {fault:Some((0,mode)),..Default::default()};let(status,out)=call(r,seed,p,&mut provider);
        let error=if mode==0||mode==8||mode==9{3}else if mode==7{2}else{4};
        assert_eq!(status,1);assert_output(&out,r,expected,4,0,error,&[],1,0x28,false);assert_calls(&provider,r,&[4]);
        assert_ne!(out,sentinel(),"semantic provider error publishes seven valid outputs");
    }
}
#[test]
fn active_failure_raw_second_rejected_cut_keeps_one_accepted_F_and_exact_pre_Q_state() {
    let mut seed=healthy(probe(owner()));seed.policy.rtt.raw.advancement_present=0;
    let mut p=negative(prepared(seed));p.capacity_only=true;p.policy.capacity_sequence=Some(42);
    let mut expected=seed;negative_prefix(&mut expected,p);expected.policy.capacity_sequence=Some(42);expected.policy.capacity_timestamp=p.policy.capacity_timestamp;
    expected.policy.rtt.faulted=true;before_q(&mut expected.policy);
    for mode in 0..10 {let r=request();let mut provider=Provider {fault:Some((1,mode)),..Default::default()};let(status,out)=call(r,seed,p,&mut provider);
        let error=if mode==0||mode==8||mode==9{3}else if mode==7{2}else{4};
        assert_eq!(status,1);assert_output(&out,r,expected,4,0,error,&[4],2,0x2c,false);assert_calls(&provider,r,&[4,2]);
    }
}
#[test]
fn active_failure_raw_same_peer_show_negative_retention_guards_are_independent_and_not_positive_imports() {
    for mode in 0..7 {let mut seed=owner();if mode==4{seed.policy.startup_disproved=true;}
        let mut p=negative(prepared(seed));match mode {0=>p.policy.peer=Some(2),1=>p.policy.floor_show=Some(8),
            2=>p.policy.startup_peer=Some(2),3=>p.policy.startup_show=Some(8),
            5=>p.policy.floor_attempt_consumed=false,6=>p.policy.startup_disproved=false,_=>{}}
        let mut expected=seed;let mut clear=0;
        if mode==5{expected.policy.startup_disproved=true;expected.policy.startup_sparse_deadline=None;clear=0x20;}
        else if mode>=2 {expected.policy.floor_attempt_consumed=true;expected.policy.floor_first_witness=None;
            expected.policy.floor_regular_sequence=Some(41);expected.policy.floor_regular_timestamp=Some(Scalar::new(41_000_000.0));clear=8;}
        expected.revision=58;let r=request();let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
        assert_eq!(status,1);assert_output(&out,r,expected,1,0,0,&[],0,clear,false);assert_calls(&provider,r,&[]);
    }
}
#[test]
fn active_failure_raw_strict_request_headers_and_all401_atoms_reject_before_any_semantic_prefix() {
    let seed=healthy(probe(owner()));let p=negative(prepared(seed));
    let current=codec::encode_owner_snapshot(seed).unwrap();let proposed=codec::encode_prepared_continuation(p).unwrap();let mut r=request();r.facts=0;
    for mode in 0..6 {let mut bad=r;match mode {0=>bad.abi=2,1=>bad.operation=702,2=>bad.invocation=0,
        3=>bad.facts=512,4=>bad.facts=u32::MAX,_=>bad.reserved=1};let mut provider=Provider::default();
        let(status,out)=invoke(bad,current.clone(),proposed.clone(),&mut provider,true,[179,222,179,13,13,15],None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert_calls(&provider,r,&[]);
    }
    for domain in 0..2 {for index in 0..if domain==0{179}else{222} {for mode in 0..2 {
        let mut a=current.clone();let mut b=proposed.clone();let atom=if domain==0{&mut a.atoms[index]}else{&mut b.atoms[index]};
        if mode==0{atom.kind=0;}else{atom.present=2;}let mut provider=Provider::default();
        let(status,out)=invoke(r,a,b,&mut provider,true,[179,222,179,13,13,15],None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert_calls(&provider,r,&[]);
    }}}
    for domain in 0..2 {for mode in 0..5 {let mut a=current.clone();let mut b=proposed.clone();let h=if domain==0{&mut a.header}else{&mut b.header};
        match mode {0=>h.abi=0,1=>h.domain=0,2=>h.phase=0,3=>h.count=0,_=>h.phase=if domain==0{2}else{1}}
        let mut provider=Provider::default();let(status,out)=invoke(r,a,b,&mut provider,true,[179,222,179,13,13,15],None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert_calls(&provider,r,&[]);
    }}
}
#[test]
fn active_failure_raw_counts_pointers_overlap_and_required_callback_fail_before_prefix_publication() {
    let seed=healthy(probe(owner()));let p=negative(prepared(seed));let current=codec::encode_owner_snapshot(seed).unwrap();let proposed=codec::encode_prepared_continuation(p).unwrap();
    for index in 0..6 {let valid=[179,222,179,13,13,15];for bad in [0,valid[index]-1,valid[index]+1,u32::MAX] {
        let mut counts=valid;counts[index]=bad;let r=request();let mut provider=Provider::default();
        let(status,out)=invoke(r,current.clone(),proposed.clone(),&mut provider,true,counts,None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert_calls(&provider,r,&[]);
    }}
    for fault in (0..12).map(Fault::Null).chain((0..12).map(Fault::Misaligned)).chain(
        (0..12).flat_map(|destination|(0..12).filter(move|source|*source!=destination)
            .map(move|source|Fault::Alias {destination,source}))) {
        let r=request();let mut provider=Provider::default();let(status,out)=invoke(r,current.clone(),proposed.clone(),&mut provider,true,[179,222,179,13,13,15],Some(fault));
        assert_eq!(status,2);assert_eq!(out,sentinel());assert_calls(&provider,r,&[]);
    }
    for stale in [false,true] {let mut r=request();if stale{r.facts=0;}let mut provider=Provider::default();
        let(status,out)=invoke(r,current.clone(),proposed.clone(),&mut provider,false,[179,222,179,13,13,15],None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert_calls(&provider,r,&[]);
    }
}
