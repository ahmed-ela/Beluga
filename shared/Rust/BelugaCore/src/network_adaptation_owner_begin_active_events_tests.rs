//! Ordinary public701 raw fixtures. Constructors/codec serialization seed inputs
//! and serialize manual full179/full222 expectations; no reducer/forwarding call
//! generates a successor oracle. No native resource or actor proof is claimed.
use core::{ffi::c_void, ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Reply, Metadata, Callback};
use crate::network_adaptation_owner_begin_active_events::*;
const MS: i128 = 1_000_000_000_000_000;
fn request() -> BeginActiveRequest { BeginActiveRequest { abi:1,operation:701,invocation:9,resource_flags:63,reserved:0 } }
fn owner() -> Owner {
    let mut v=Owner::new(50_000_000,60,Dependencies::default());
    v.revision=57;v.fast_statistics_available=true;v.evidence_lane=Some(EvidenceLane::OrdinaryFallback);
    v.last_evidence=Some(-7_000_000_000_000_000_001);v.freshness.minimum=Some(31);
    v.applied=Some(Recommendation {tier:Tier::Balanced,maximum_video:1_234_567,
        maximum_total:2_345_678,fps:29,scale:Scalar::new(1.5)});
    let p=&mut v.policy;p.peer=Some(1);p.tier=Tier::AudioPriority;p.route_present=true;
    p.floor_show=Some(7);p.floor_reserved=true;p.startup_peer=Some(1);p.startup_show=Some(7);
    p.startup_sparse_deadline=Some(46);p.floor_cooldown_at=Some(45);
    p.floor_first_witness=Some(FloorWitness {observed_at:44,bandwidth:Scalar::new(306_000.0)});
    p.floor_regular_sequence=Some(39);p.floor_regular_timestamp=Some(Scalar::new(39_000_000.0));
    p.consumed_sequence=Some(39);p.capacity_sequence=Some(39);p.capacity_timestamp=Some(Scalar::new(39_000_000.0));
    p.queue.packets=Some(30);p.queue.delay_bits=Some(0.0_f64.to_bits());
    p.queue.low_observation=Some(47);p.queue.soft_observation=Some(48);v
}
fn prepared(v:Owner)->Prepared {
    Prepared {policy:v.policy,source_generation:1,expected_revision:v.revision,applying_revision:v.revision,
        lane:ProposalLane::Regular,capture_active:true,capacity_only:false,changed:None,
        recommendation:Recommendation {tier:Tier::Survival,maximum_video:111_222,maximum_total:333_444,
            fps:5,scale:Scalar::new(4.0)},route_action:RouteAction::CopyIncoming,
        floor_diagnostics:None,capacity_diagnostics:None}
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
fn attempt(mut p:Prepared)->Prepared {
    p.policy.floor_attempt_consumed=true;p.policy.startup_disproved=true;
    p.policy.floor_regular_sequence=Some(41);p.policy.floor_regular_timestamp=Some(Scalar::new(41_000_000.0));
    // Positive proposed state may not be imported by attempt/fault retention.
    p.policy.probe_deadline=Some(9_999*MS);p.policy.queue.low_observation=Some(9_998*MS);
    p.policy.probe_maximum=Some(999_999);p
}
fn values(p:Policy)->[Option<i128>;9] {
    [p.probe_deadline,p.probe_qualification_at,p.promotion.map(|v|v.deadline),
        p.floor_first_witness.map(|v|v.observed_at),p.floor_cooldown_at,p.startup_sparse_deadline,
        p.queue.low_observation,p.queue.soft_observation,p.rtt.last_advancement]
}
#[derive(Clone,Debug,PartialEq,Eq)]
struct Output {
    owner_header:codec::Header,owner_atoms:[codec::Atom;179],prepared_header:codec::Header,
    prepared_atoms:[codec::Atom;222],metadata:Metadata,outcome:BeginActiveOutcome,
    edits:[Edit;13],coordinates:[Time;13],reads:[Reply;15],
}
fn sentinel()->Output {
    Output {owner_header:codec::Header {abi:91,domain:92,phase:93,count:94},
        owner_atoms:[codec::Atom {kind:91,present:92,high:-93,low:94};179],
        prepared_header:codec::Header {abi:95,domain:96,phase:97,count:98},
        prepared_atoms:[codec::Atom {kind:95,present:96,high:-97,low:98};222],
        metadata:Metadata {abi:91,operation:92,scope:93,read_count:94,invocation:95,revision:96,
            peer:97,peer_present:98,bound:99,route:100,sample:101,enabled:102,lease:103,queue_fault:104,rtt_fault:105},
        outcome:BeginActiveOutcome {abi:91,operation:92,invocation:93,disposition:94,route:95,prepared_present:96,reserved:97},
        edits:[Edit {action:91,source:92,index:93,ordinal:94,high:-95,low:96};13],
        coordinates:[Time {present:91,reserved:92,high:-93,low:94};13],
        reads:[Reply {abi:91,status:92,site:93,ordinal:94,invocation:95,high:-96,low:97,reserved:98};15]}
}
#[derive(Clone,Copy)]
enum ReplyFault {Abi,Status,Site,Ordinal,Reserved}
#[derive(Default)]
struct Provider {
    calls:Vec<(u64,u32,u32)>,deny:Option<u32>,wrong:bool,huge:bool,
    returned:Option<(u32,u32)>,corrupt:Option<ReplyFault>,
}
unsafe extern "C" fn callback(context:*mut c_void,invocation:u64,site:u32,ordinal:u32,out:*mut Reply)->u32 {
    let p=unsafe {&mut *context.cast::<Provider>()};p.calls.push((invocation,site,ordinal));
    if p.deny==Some(ordinal){return 0;}
    let value=(100+ordinal as i128)*MS;
    let mut reply=Reply {abi:1,status:1,site,ordinal,invocation:if p.wrong {invocation^1}else{invocation},
        high:if p.huge {i64::MAX}else{(value>>64)as i64},low:if p.huge {u64::MAX}else{value as u64},reserved:0};
    match p.corrupt {
        Some(ReplyFault::Abi)=>reply.abi=2,Some(ReplyFault::Status)=>reply.status=2,
        Some(ReplyFault::Site)=>reply.site^=1,Some(ReplyFault::Ordinal)=>reply.ordinal+=1,
        Some(ReplyFault::Reserved)=>reply.reserved=1,None=>{},
    }
    unsafe {ptr::write(out,reply);}
    p.returned.filter(|(at,_)|*at==ordinal).map(|(_,code)|code).unwrap_or(1)
}
#[derive(Clone,Copy)]
enum Fault {Null(usize),Misaligned(usize),Overlap(usize,usize)}
fn invoke(r:BeginActiveRequest,current:codec::Wire,prepared:codec::Wire,p:&mut Provider,
          cb:bool,counts:[u32;7],fault:Option<Fault>)->(u32,Output) {
    let before=(r,current.clone(),prepared.clone());let mut out=sentinel();
    let mut rp=&r as *const BeginActiveRequest;let mut ch=&current.header as *const codec::Header;
    let mut ca=current.atoms.as_ptr();let mut ph=&prepared.header as *const codec::Header;let mut pa=prepared.atoms.as_ptr();
    let mut oh=&mut out.owner_header as *mut codec::Header;let mut oa=out.owner_atoms.as_mut_ptr();
    let mut oph=&mut out.prepared_header as *mut codec::Header;let mut opa=out.prepared_atoms.as_mut_ptr();
    let mut m=&mut out.metadata as *mut Metadata;let mut o=&mut out.outcome as *mut BeginActiveOutcome;
    let mut e=out.edits.as_mut_ptr();let mut c=out.coordinates.as_mut_ptr();let mut t=out.reads.as_mut_ptr();
    // Every redirected pointer targets one of the initialized objects whose
    // entire scalar body is checked below and whose output sentinel is returned.
    // Invalid ranges must be refused before any pointed-to value is read/written.
    let bases=[rp as usize,ch as usize,ca as usize,ph as usize,pa as usize,
        oh as usize,oa as usize,oph as usize,opa as usize,m as usize,o as usize,
        e as usize,c as usize,t as usize];
    let redirect=match fault {
        Some(Fault::Null(i))=>Some((i,0)),
        Some(Fault::Misaligned(i))=>Some((i,bases[i].checked_add(1).unwrap())),
        Some(Fault::Overlap(i,j))=>Some((i,bases[j])),None=>None,
    };
    if let Some((i,address))=redirect {
        match i {
            0=>rp=address as *const BeginActiveRequest,1=>ch=address as *const codec::Header,
            2=>ca=address as *const codec::Atom,3=>ph=address as *const codec::Header,
            4=>pa=address as *const codec::Atom,5=>oh=address as *mut codec::Header,
            6=>oa=address as *mut codec::Atom,7=>oph=address as *mut codec::Header,
            8=>opa=address as *mut codec::Atom,9=>m=address as *mut Metadata,
            10=>o=address as *mut BeginActiveOutcome,11=>e=address as *mut Edit,
            12=>c=address as *mut Time,13=>t=address as *mut Reply,_=>panic!("fixture"),
        }
    }
    let cb:Option<Callback>=if cb{Some(callback)}else{None};
    let status=unsafe {beluga_core_network_adaptation_owner_begin_active(rp,ch,ca,counts[0],ph,pa,counts[1],cb,
        (p as *mut Provider).cast(),oh,oa,counts[2],oph,opa,counts[3],m,o,e,counts[4],c,counts[5],t,counts[6])};
    assert_eq!((r,current,prepared),before,"all five scalar inputs, including headers, unchanged");(status,out)
}
fn call(r:BeginActiveRequest,current:Owner,p:Prepared,provider:&mut Provider)->(u32,Output) {
    invoke(r,codec::encode_owner_snapshot(current).unwrap(),codec::encode_prepared_continuation(p).unwrap(),
        provider,true,[179,222,179,222,13,13,15],None)
}
fn assert_success(out:&Output,expected:Owner,prepared:Option<Prepared>,disposition:u32,route:u32,clear:u16,tags:&[u32],invocation:u64) {
    let owner=codec::encode_owner(expected,codec::RESULT).unwrap();
    assert_eq!(out.owner_header,codec::Header {abi:1,domain:2,phase:2,count:179});
    assert_eq!(out.owner_atoms.as_slice(),owner.atoms.as_slice(),"manual full179 successor and opaque owner tail");
    match prepared {Some(p)=>{let wire=codec::encode_prepared_continuation(p).unwrap();
        assert_eq!(out.prepared_header,codec::Header {abi:1,domain:4,phase:3,count:222});
        assert_eq!(out.prepared_atoms.as_slice(),wire.atoms.as_slice(),"manual full222; only applying may differ");},
        None=>{assert_eq!(out.prepared_header,codec::Header::default());assert_eq!(out.prepared_atoms,[codec::Atom::default();222]);}}
    assert_eq!(out.outcome,BeginActiveOutcome {abi:1,operation:701,invocation,disposition,route,prepared_present:prepared.is_some()as u32,reserved:0});
    assert_eq!(out.metadata,Metadata {abi:1,operation:701,scope:2,read_count:tags.len()as u32,invocation,
        revision:expected.revision,peer:expected.policy.peer.unwrap_or(0),peer_present:expected.policy.peer.is_some()as u32,
        route,queue_fault:expected.policy.queue.faulted as u32,rtt_fault:expected.policy.rtt.faulted as u32,..Metadata::default()});
    for (i,value) in values(expected.policy).into_iter().enumerate() {
        assert_eq!(out.edits[i],Edit {action:if clear&(1<<i)!=0{2}else{1},..Edit::default()});
        assert_eq!(out.coordinates[i],Time::encode(value));
    }
    assert_eq!(&out.edits[9..],&[Edit::default();4]);assert_eq!(&out.coordinates[9..],&[Time::default();4]);
    let mut reads=[Reply::default();15];
    for (ordinal,site) in tags.iter().copied().enumerate(){let value=(100+ordinal as i128)*MS;
        reads[ordinal]=Reply {abi:1,status:1,site,ordinal:ordinal as u32,invocation,high:(value>>64)as i64,low:value as u64,reserved:0};}
    assert_eq!(out.reads,reads,"exact successful transcript and zero unused tail");
}

#[test]
fn active_begin_raw_layout_domains_and_pod_offsets_are_literal() {
    assert_eq!((core::mem::size_of::<BeginActiveRequest>(),core::mem::align_of::<BeginActiveRequest>()),(24,8));
    assert_eq!((core::mem::size_of::<BeginActiveOutcome>(),core::mem::align_of::<BeginActiveOutcome>()),(32,8));
    assert_eq!(core::mem::offset_of!(BeginActiveRequest,resource_flags),16);
    assert_eq!(core::mem::offset_of!(BeginActiveOutcome,prepared_present),24);
    assert_eq!(codec::encode_owner_snapshot(owner()).unwrap().header,codec::Header{abi:1,domain:2,phase:1,count:179});
    assert_eq!(codec::encode_prepared_continuation(prepared(owner())).unwrap().header,codec::Header{abi:1,domain:4,phase:3,count:222});
}
#[test]
fn active_begin_raw_no_invented_revision_peer_or_active_fence_and_exact222() {
    let seed=owner();let mut p=prepared(seed);p.expected_revision=999;p.applying_revision=888;
    p.source_generation=u64::MAX;p.capture_active=false;p.policy.peer=None;
    let mut provider=Provider::default();let(status,out)=call(request(),seed,p,&mut provider);
    assert_eq!(status,1);assert!(provider.calls.is_empty());assert_success(&out,seed,Some(p),2,0,0,&[],9);
}
#[test]
fn active_begin_raw_no_native_apply_skips_resources_but_changed_forces_return() {
    let mut seed=owner();let p=prepared(seed);seed.applied=Some(p.recommendation);
    let mut r=request();r.resource_flags=0;let mut provider=Provider::default();
    let(status,out)=call(r,seed,p,&mut provider);assert_eq!(status,1);
    assert_success(&out,seed,Some(p),1,0,0,&[],9);
    let mut changed=p;changed.changed=Some(changed.recommendation);
    let(status,out)=call(r,seed,changed,&mut provider);assert_eq!(status,1);
    assert_success(&out,seed,None,0,0,0,&[],9);assert!(provider.calls.is_empty());
}
#[test]
fn active_begin_raw_each_missing_resource_returns_before_attempt_consumption() {
    let seed=owner();let p=attempt(prepared(seed));
    for bit in 0..6 {let mut r=request();r.resource_flags&=!(1<<bit);let mut provider=Provider::default();
        let(status,out)=call(r,seed,p,&mut provider);assert_eq!(status,1);assert!(provider.calls.is_empty());
        assert_success(&out,seed,None,0,0,0,&[],9);}
}
#[test]
fn active_begin_raw_attempt_only_changes_negative_fields_and_applying_revision() {
    let seed=probe(owner());let p=attempt(prepared(seed));let mut expected=seed;
    expected.policy.floor_attempt_consumed=true;expected.policy.floor_first_witness=None;
    expected.policy.floor_regular_sequence=Some(41);expected.policy.floor_regular_timestamp=Some(Scalar::new(41_000_000.0));
    expected.revision=58;let mut returned=p;returned.applying_revision=58;
    let mut provider=Provider::default();let(status,out)=call(request(),seed,p,&mut provider);assert_eq!(status,1);
    assert!(provider.calls.is_empty());assert_success(&out,expected,Some(returned),2,0,1<<3,&[],9);
}
#[test]
fn active_begin_raw_fault_retains_before_resource_return_without_positive_adoption() {
    let seed=owner();let mut p=prepared(seed);p.policy.rtt.faulted=true;
    let mut expected=seed;expected.policy.rtt.faulted=true;expected.policy.promotion=None;
    expected.policy.startup_disproved=true;expected.policy.startup_sparse_deadline=None;
    expected.policy.healthy_upgrades=0;expected.policy.limited_upgrades=0;expected.revision=58;
    let mut r=request();r.resource_flags=62;let mut provider=Provider::default();
    let(status,out)=call(r,seed,p,&mut provider);assert_eq!(status,1);assert!(provider.calls.is_empty());
    assert_success(&out,expected,None,0,0,(1<<2)|(1<<5),&[],9);
}
#[test]
fn active_begin_raw_fault_and_attempt_wrap_at_two_distinct_revision_sites() {
    let mut seed=owner();seed.revision=u64::MAX;let mut p=attempt(prepared(seed));p.policy.rtt.faulted=true;
    let mut expected=seed;expected.policy.rtt.faulted=true;expected.policy.promotion=None;
    expected.policy.startup_disproved=true;expected.policy.startup_sparse_deadline=None;
    expected.policy.healthy_upgrades=0;expected.policy.limited_upgrades=0;
    expected.policy.floor_attempt_consumed=true;expected.policy.floor_first_witness=None;
    expected.policy.floor_regular_sequence=Some(41);expected.policy.floor_regular_timestamp=Some(Scalar::new(41_000_000.0));
    expected.revision=1;let mut returned=p;returned.applying_revision=1;
    let mut provider=Provider::default();let(status,out)=call(request(),seed,p,&mut provider);assert_eq!(status,1);
    assert_success(&out,expected,Some(returned),2,0,(1<<2)|(1<<3)|(1<<5),&[],9);
}
#[test]
fn active_begin_raw_new_peer_binding_clears_all_nine_times_and_retained_route() {
    let mut seed=probe(owner());seed.policy.rtt.last_advancement=Some(49);
    seed.policy.rtt.raw.advancement_present=1;
    let mut p=prepared(seed);p.source_generation=2;p.policy.peer=Some(2);p.policy.demand.faulted=true;
    let mut expected=seed;let s=&mut expected.policy;
    s.startup_peer=None;s.startup_show=None;s.startup_disproved=false;s.startup_sparse_deadline=None;
    s.peer=Some(2);s.tier=Tier::from_ordinal(s.demand.initial).unwrap();s.route_present=false;
    s.floor_first_witness=None;s.probe_confirmed=None;s.probe_qualification_at=None;s.floor_seed=None;
    s.capacity_sample=None;s.capacity_bandwidth_high=None;s.promotion=None;
    s.healthy_upgrades=0;s.bandwidth_downgrades=0;s.queue.packets=None;s.queue.delay_bits=None;
    s.queue.pressure_count=0;s.queue.low_observation=None;s.queue.soft_observation=None;
    s.unavailable_samples=0;s.positive_bootstrap=0;s.limited_upgrades=0;s.probe_healthy=0;s.probe_grace=0;
    s.probe_deadline=None;s.probe_origin=None;s.probe_best=None;s.probe_maximum=None;s.below_reserve_disproved=false;
    s.resume_restoration=None;s.probe_cooldown=0;s.probe_failures=0;s.bandwidth_unavailable=false;
    s.last_latency_pressure=false;s.last_positive_suspension_pressure=false;s.last_average_delay=None;
    s.consumed_sequence=None;s.floor_show=None;s.floor_reserved=false;s.floor_active=false;
    s.floor_attempt_consumed=false;s.floor_probe_cancelled=false;s.floor_regular_sequence=None;s.floor_regular_timestamp=None;
    s.floor_cooldown_at=None;s.capacity_sequence=None;s.capacity_timestamp=None;
    s.suspension_pressure=0;s.stable_resume=0;s.maximum_resume=0;s.demand.faulted=true;
    // Input raw state is initial except advancement_present1. Original op4
    // retains that time; op5 clears it and otherwise restores these exact words.
    s.rtt.raw.advancement_present=0;s.rtt.last_advancement=None;expected.revision=58;
    let mut returned=p;returned.applying_revision=58;let mut provider=Provider::default();
    let(status,out)=call(request(),seed,p,&mut provider);assert_eq!(status,1);
    assert_success(&out,expected,Some(returned),2,1,0x1ff,&[2,0,1,0,1],9);
    let mut missing=request();missing.resource_flags=62;
    let mut incoming=p;incoming.policy.floor_attempt_consumed=true;
    incoming.policy.floor_regular_sequence=Some(u64::MAX);
    let mut provider=Provider::default();let(status,out)=call(missing,seed,incoming,&mut provider);
    assert_eq!(status,1);assert_success(&out,expected,None,0,1,0x1ff,&[2,0,1,0,1],9);
}
#[test]
fn active_begin_raw_same_peer_Q_success_and_all_five_new_peer_denial_prefixes() {
    let seed=probe(owner());let mut p=prepared(seed);p.policy.rtt.faulted=true;
    let mut expected=seed;let s=&mut expected.policy;s.rtt.faulted=true;s.floor_probe_cancelled=true;s.floor_seed=None;
    s.tier=Tier::AudioPriority;s.floor_first_witness=None;s.capacity_sample=None;s.capacity_bandwidth_high=None;s.promotion=None;
    s.queue.pressure_count=0;s.queue.low_observation=None;s.queue.soft_observation=None;
    s.probe_origin=None;s.probe_confirmed=None;s.probe_qualification_at=None;s.probe_best=None;s.probe_maximum=None;
    s.probe_healthy=0;s.probe_grace=0;s.probe_deadline=None;s.startup_disproved=true;s.startup_sparse_deadline=None;
    s.healthy_upgrades=0;s.limited_upgrades=0;expected.revision=58;
    let mut r=request();r.resource_flags=62;let mut provider=Provider::default();let(status,out)=call(r,seed,p,&mut provider);
    assert_eq!(status,1);assert_success(&out,expected,None,0,0,0xef,&[2],9);
    let mut provider=Provider {deny:Some(0),..Default::default()};let(status,out)=call(request(),seed,p,&mut provider);
    assert_eq!(status,3);assert_eq!(out,sentinel());assert_eq!(provider.calls,[(9,2,0)]);
    let mut seed=probe(owner());seed.policy.rtt.faulted=true;
    let mut p=prepared(seed);p.source_generation=2;p.policy.peer=Some(2);p.policy.demand.faulted=true;
    let tags=[2,0,1,0,1];
    for ordinal in 0..5 {let mut provider=Provider {deny:Some(ordinal),..Default::default()};
        let(status,out)=call(request(),seed,p,&mut provider);assert_eq!(status,3);assert_eq!(out,sentinel());
        let expected:Vec<_>=tags[..=ordinal as usize].iter().enumerate().map(|(i,tag)|(9,*tag,i as u32)).collect();
        assert_eq!(provider.calls,expected,"actual faulted-facade lazy prefix and no subsequent call");}
    // An otherwise exact reply cannot override the callback's denied status.
    for code in [0,2,u32::MAX] {for ordinal in 0..5 {
        let mut provider=Provider {returned:Some((ordinal,code)),..Default::default()};
        let(status,out)=call(request(),seed,p,&mut provider);
        assert_eq!(status,3);assert_eq!(out,sentinel());
        let expected:Vec<_>=tags[..=ordinal as usize].iter().enumerate().map(|(i,tag)|(9,*tag,i as u32)).collect();
        assert_eq!(provider.calls,expected,"valid reply plus denied return stops this exact prefix");
    }}
}
#[test]
fn active_begin_raw_nan_nonreflexivity_and_signed_zero_preserve_all_words() {
    for nan in [false,true] {let mut seed=owner();seed.policy.last_average_delay=Some(Scalar(if nan{0x7ff8_0000_0000_0042}else{0x8000_0000_0000_0000}));
        seed.policy.probe_failures=i64::MAX;seed.policy.probe_cooldown=i64::MIN;
        let p=prepared(seed);let mut expected=seed;if nan{expected.revision=58;}
        let mut returned=p;returned.applying_revision=expected.revision;let mut provider=Provider::default();
        let(status,out)=call(request(),seed,p,&mut provider);assert_eq!(status,1);assert!(provider.calls.is_empty());
        assert_success(&out,expected,Some(returned),2,0,0,&[],9);}
}
#[test]
fn active_begin_raw_callback_correlation_and_unrepresentable_time_leave_all_nine_outputs() {
    let seed=probe(owner());let mut p=prepared(seed);p.policy.rtt.faulted=true;
    for mode in 0..2 {let mut provider=Provider {wrong:mode==0,huge:mode==1,..Default::default()};
        let(status,out)=call(request(),seed,p,&mut provider);assert_eq!(status,if mode==0{4}else{2});
        assert_eq!(out,sentinel());assert_eq!(provider.calls,[(9,2,0)]);}
    for corrupt in [ReplyFault::Abi,ReplyFault::Status,ReplyFault::Site,ReplyFault::Ordinal,ReplyFault::Reserved] {
        let mut provider=Provider {corrupt:Some(corrupt),..Default::default()};
        let(status,out)=call(request(),seed,p,&mut provider);
        assert_eq!(status,4);assert_eq!(out,sentinel());assert_eq!(provider.calls,[(9,2,0)]);
    }
}
#[test]
fn active_begin_raw_complete_decode_closed_payload_and_pointer_count_denials() {
    let mut r=request();r.resource_flags=0;let seed=owner();let p=prepared(seed);
    let current=codec::encode_owner_snapshot(seed).unwrap();let prepared=codec::encode_prepared_continuation(p).unwrap();
    for mode in 0..6 {let mut bad=r;match mode{0=>bad.abi=2,1=>bad.operation=702,2=>bad.invocation=0,
        3=>bad.resource_flags=64,4=>bad.resource_flags=u32::MAX,_=>bad.reserved=1};let mut provider=Provider::default();
        let(status,out)=invoke(bad,current.clone(),prepared.clone(),&mut provider,true,[179,222,179,222,13,13,15],None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert!(provider.calls.is_empty());}
    for domain in 0..2 {for i in 0..(if domain==0{179}else{222}) {let mut a=current.clone();let mut b=prepared.clone();
        if domain==0{a.atoms[i].kind=0;}else{b.atoms[i].kind=0;}
        let mut provider=Provider::default();let(status,out)=invoke(r,a,b,&mut provider,true,[179,222,179,222,13,13,15],None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert!(provider.calls.is_empty());}}
    for domain in 0..2 {for mode in 0..4 {let mut a=current.clone();let mut b=prepared.clone();let h=if domain==0{&mut a.header}else{&mut b.header};
        match mode{0=>h.abi=0,1=>h.domain=0,2=>h.phase=0,_=>h.count=0};let mut provider=Provider::default();
        let(status,out)=invoke(r,a,b,&mut provider,true,[179,222,179,222,13,13,15],None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert!(provider.calls.is_empty());}}
    for index in 0..7 {let exact=[179,222,179,222,13,13,15];for bad in [0,u32::MAX,exact[index]-1,exact[index]+1] {let mut counts=exact;counts[index]=bad;
        let mut provider=Provider::default();let(status,out)=invoke(r,current.clone(),prepared.clone(),&mut provider,true,counts,None);
        assert_eq!(status,2);assert_eq!(out,sentinel());assert!(provider.calls.is_empty());}}
    let faults=(0..14).map(Fault::Null).chain((0..14).map(Fault::Misaligned))
        .chain((0..14).flat_map(|i|(0..14).filter(move |j|*j!=i).map(move |j|Fault::Overlap(i,j))));
    for fault in faults {
        let mut provider=Provider::default();let(status,out)=invoke(r,current.clone(),prepared.clone(),&mut provider,true,[179,222,179,222,13,13,15],Some(fault));
        assert_eq!(status,2);assert_eq!(out,sentinel());assert!(provider.calls.is_empty());}
    let mut provider=Provider::default();let(status,out)=invoke(r,current,prepared,&mut provider,false,[179,222,179,222,13,13,15],None);
    assert_eq!(status,2);assert_eq!(out,sentinel());assert!(provider.calls.is_empty());
}
