//! Ordinary PUBLIC601 source tests; input encoders only, no reducer or result
//! encoder computes expected state. Scalar Prepared seeds are test inputs, not
//! genuine native seals/route/Instant/provider or actor publication authority.
use core::{ffi::c_void,mem::{size_of,align_of,offset_of},ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec::{self as codec,Atom,Header};
use crate::native_clock_assay::{Time,Edit,Reply,Metadata,Callback};
use crate::network_adaptation_owner_inactive_events::{
    beluga_core_network_adaptation_owner_adopt_inactive as event,
    InactiveAdoptionRequest,InactiveAdoptionOutcome};

const INV:u64=0x601_abcd_1234_5678;
const MS:i128=1_000_000_000_000_000;
const TIME_ATOMS:[usize;9]=[12,23,28,159,163,167,39,40,88];
const fn a(kind:u32,present:u32,high:i64,low:u64)->Atom{Atom{kind,present,high,low}}
fn request()->InactiveAdoptionRequest{InactiveAdoptionRequest{abi:1,operation:601,
    invocation:INV,current_generation:1,exact_peer:1,suspended:0}}
fn owner()->Owner{
    let mut v=Owner::new(50_000_000,60,Dependencies::default());
    v.revision=57;v.fast_statistics_available=true;v.evidence_lane=Some(EvidenceLane::OrdinaryFallback);
    v.last_evidence=Some(-7_000*MS-1);v.freshness.minimum=Some(u64::MAX);
    v.applied=Some(Recommendation{tier:Tier::Balanced,maximum_video:1_234_567,
        maximum_total:2_345_678,fps:29,scale:Scalar(0x7ff8_0000_0000_0042)});
    v.policy.peer=Some(1);v.policy.tier=Tier::AudioPriority;v.policy.route_present=true;
    v.policy.floor_show=Some(7);v.policy.floor_reserved=true;
    v.policy.startup_peer=Some(1);v.policy.startup_show=Some(7);
    v.policy.queue.packets=Some(30);v.policy.queue.delay_bits=Some(0x8000_0000_0000_0000);
    v.policy.suspension_pressure=13;v.policy.stable_resume=12;v.policy.maximum_resume=11;v
}
fn times(mut v:Owner)->Owner{
    v.policy.probe_deadline=Some(-3_500*MS-1);v.policy.probe_qualification_at=Some(-43);
    v.policy.promotion=Some(Promotion{tier:Tier::Survival,maximum_total:712_000,deadline:-42});
    v.policy.floor_first_witness=Some(FloorWitness{observed_at:-44,bandwidth:Scalar(0x7ff8_0000_0000_0043)});
    v.policy.floor_cooldown_at=Some(-45);v.policy.startup_sparse_deadline=Some(-46);
    v.policy.queue.low_observation=Some(-47);v.policy.queue.soft_observation=Some(-48);
    v.policy.rtt.last_advancement=Some(-49);v.policy.rtt.raw.advancement_present=1;v
}
fn healthy(mut v:Owner)->Owner{
    let r=&mut v.policy.rtt.raw;
    r.baseline_present=1;r.baseline_bits=0.004_f64.to_bits();r.disposition=2;r.health=1;
    r.uses_native=1;r.permits_initial=0;r.distinct_count=3;r.last_measured_present=1;
    r.last_measured_bits=0.004_f64.to_bits();r.advancement_present=1;r.age_present=1;
    r.watermark_present=1;r.fence_present=1;r.fence_current_present=1;
    r.watermark=crate::rtt_evidence::RawMeasurement{fingerprint_words:[0x6161_6161_6161_6161;8],
        total_bits:0.012_f64.to_bits(),responses:3};r.fence=r.watermark;r.fence_current_bits=0.004_f64.to_bits();
    v.policy.rtt.last_advancement=Some(-49);v
}
fn prepared(v:Owner)->Prepared{Prepared{policy:v.policy,source_generation:1,
    expected_revision:v.revision,applying_revision:999,lane:ProposalLane::Regular,
    capture_active:false,capacity_only:false,changed:None,
    recommendation:Recommendation{tier:Tier::Survival,maximum_video:111_222,
        maximum_total:333_444,fps:5,scale:Scalar(0x8000_0000_0000_0000)},
    route_action:RouteAction::Retain,floor_diagnostics:None,capacity_diagnostics:None}}
fn faulting(seed:Owner)->Prepared{
    let mut p=prepared(healthy(times(seed)));p.policy.rtt.raw.reserved=1;
    p.policy.probe_origin=Some(Tier::AudioPriority);p.policy.probe_best=Some(Tier::Survival);
    p.policy.probe_confirmed=Some(Tier::Survival);p.policy.probe_maximum=Some(612_000);
    p.policy.probe_healthy=1;p.policy.probe_grace=7;p.policy.floor_seed=Some(Scalar::new(306_000.));
    p.policy.capacity_bandwidth_high=Some(Scalar::new(306_000.));
    p.policy.capacity_sample=Some(CapacitySample{packets:Some(30),delay:Some(Scalar::new(0.))});
    p.policy.healthy_upgrades=8;p.policy.limited_upgrades=9;
    p.policy.suspension_pressure=9;p.policy.maximum_resume=2;p.policy.stable_resume=4;p
}
#[derive(Clone,Debug,PartialEq,Eq)]
struct Output{header:Header,atoms:[Atom;179],meta:Metadata,outcome:InactiveAdoptionOutcome,
    edits:[Edit;13],coordinates:[Time;13],reads:[Reply;15]}
impl Output{fn sentinel()->Self{Self{header:Header{abi:91,domain:92,phase:93,count:94},
    atoms:[a(91,92,-93,94);179],meta:Metadata{abi:91,operation:92,scope:93,read_count:94,
        invocation:95,revision:96,peer:97,peer_present:98,bound:99,route:100,sample:101,
        enabled:102,lease:103,queue_fault:104,rtt_fault:105},
    outcome:InactiveAdoptionOutcome{abi:91,operation:92,invocation:93,disposition:94,route:95},
    edits:[Edit{action:91,source:92,index:93,ordinal:94,high:-95,low:96};13],
    coordinates:[Time{present:91,reserved:92,high:-93,low:94};13],
    reads:[Reply{abi:91,status:92,site:93,ordinal:94,invocation:95,high:-96,low:97,reserved:98};15]}}}
struct Provider{seen:Vec<(u64,u32,u32)>,fail:usize,returned:u32,corrupt:u32}
impl Provider{fn new()->Self{Self{seen:vec![],fail:usize::MAX,returned:1,corrupt:0}}}
fn reply(ordinal:usize,site:u32)->Reply{
    let v=(100+ordinal as i128)*MS;
    Reply{abi:1,status:1,site,ordinal:ordinal as u32,invocation:INV,high:(v>>64) as i64,low:v as u64,reserved:0}
}
unsafe extern "C" fn callback(ctx:*mut c_void,inv:u64,site:u32,ordinal:u32,out:*mut Reply)->u32{
    let p=unsafe{&mut *ctx.cast::<Provider>()};let n=p.seen.len();p.seen.push((inv,site,ordinal));
    let mut r=reply(n,site);r.invocation=inv;r.ordinal=ordinal;
    match p.corrupt{1=>r.abi=2,2=>r.status=0,3=>r.site=site^1,4=>r.ordinal=ordinal+1,
        5=>r.invocation=inv^1,6=>r.reserved=1,7=>{r.high=i64::MAX;r.low=u64::MAX;},_=>{}}
    // Otherwise valid bytes are written even when return0/2/MAX denies.
    unsafe{ptr::write(out,r)};if n==p.fail{p.returned}else{1}
}
fn bytes<T>(v:&[T])->Vec<u8>{unsafe{core::slice::from_raw_parts(v.as_ptr().cast::<u8>(),
    core::mem::size_of_val(v)).to_vec()}}
#[derive(Clone,Copy)]
struct Args{p:[usize;12],n:[u32;6],cb:Option<Callback>,ctx:*mut c_void}
impl Args{
    fn new(r:&InactiveAdoptionRequest,c:&codec::Wire,p:&codec::Wire,o:&mut Output,v:&mut Provider)->Self{
        Self{p:[r as *const _ as usize,&c.header as *const _ as usize,c.atoms.as_ptr() as usize,
            &p.header as *const _ as usize,p.atoms.as_ptr() as usize,
            &mut o.header as *mut _ as usize,o.atoms.as_mut_ptr() as usize,
            &mut o.meta as *mut _ as usize,&mut o.outcome as *mut _ as usize,
            o.edits.as_mut_ptr() as usize,o.coordinates.as_mut_ptr() as usize,o.reads.as_mut_ptr() as usize],
            n:[179,222,179,13,13,15],cb:Some(callback),ctx:(v as *mut Provider).cast()}}
    unsafe fn run(self)->u32{unsafe{event(self.p[0] as *const InactiveAdoptionRequest,
        self.p[1] as *const Header,self.p[2] as *const Atom,self.n[0],
        self.p[3] as *const Header,self.p[4] as *const Atom,self.n[1],self.cb,self.ctx,
        self.p[5] as *mut Header,self.p[6] as *mut Atom,self.n[2],self.p[7] as *mut Metadata,
        self.p[8] as *mut InactiveAdoptionOutcome,self.p[9] as *mut Edit,self.n[3],
        self.p[10] as *mut Time,self.n[4],self.p[11] as *mut Reply,self.n[5])}}
}
fn call(r:InactiveAdoptionRequest,c:codec::Wire,p:codec::Wire,v:&mut Provider)->(u32,Output){
    let before=[bytes(core::slice::from_ref(&r)),bytes(core::slice::from_ref(&c.header)),bytes(&c.atoms),
        bytes(core::slice::from_ref(&p.header)),bytes(&p.atoms)];
    let mut o=Output::sentinel();let s=unsafe{Args::new(&r,&c,&p,&mut o,v).run()};
    assert_eq!(before,[bytes(core::slice::from_ref(&r)),bytes(core::slice::from_ref(&c.header)),bytes(&c.atoms),
        bytes(core::slice::from_ref(&p.header)),bytes(&p.atoms)]);(s,o)
}
fn current(v:Owner)->codec::Wire{codec::encode_owner_snapshot(v).unwrap()}
fn proposal(p:Prepared)->codec::Wire{codec::encode_prepared_continuation(p).unwrap()}
fn copy_expected(c:&codec::Wire,p:&codec::Wire,revision:u64,pressure:i64,stable:i64,maximum:i64)->Vec<Atom>{
    // The full replacement contract copies policy168, not a reducer/encoder oracle.
    let mut e=c.atoms.clone();e[..168].copy_from_slice(&p.atoms[..168]);e[168]=a(1,1,0,revision);
    e[29]=a(2,1,0,pressure as u64);e[30]=a(2,1,0,stable as u64);e[31]=a(2,1,0,maximum as u64);e
}
fn success(o:&Output,expected:&[Atom],disposition:u32,route:u32,tags:&[u32]){
    assert_eq!(o.header,Header{abi:1,domain:2,phase:2,count:179});assert_eq!(&o.atoms,expected);
    assert_eq!(o.meta,Metadata{abi:1,operation:601,scope:2,read_count:tags.len() as u32,invocation:INV,
        revision:expected[168].low,peer:expected[3].low,peer_present:expected[3].present,
        route,queue_fault:expected[41].low as u32,rtt_fault:expected[89].low as u32,..Metadata::default()});
    assert_eq!(o.outcome,InactiveAdoptionOutcome{abi:1,operation:601,invocation:INV,disposition,route});
    let mut reads=[Reply::default();15];for(n,&site)in tags.iter().enumerate(){reads[n]=reply(n,site);}
    assert_eq!(o.reads,reads);assert_eq!(o.edits[9..],[Edit::default();4]);
    assert_eq!(o.coordinates[9..],[Time::default();4]);
}
fn journals(o:&Output,input:&codec::Wire,stale:bool){
    for(i,&position)in TIME_ATOMS.iter().enumerate(){let v=input.atoms[position];
        assert_eq!(o.coordinates[i],Time{present:v.present,reserved:0,high:v.high,low:v.low});
        assert_eq!(o.edits[i],if stale{Edit{action:1,..Edit::default()}}
            else if v.present==1{Edit{action:3,source:2,index:i as u32,ordinal:0,high:0,low:0}}
            else{Edit{action:2,..Edit::default()}});
    }
}

#[test]
fn product_owner_inactive_pod_layout_and_distinct_domains(){
    assert_eq!((size_of::<InactiveAdoptionRequest>(),align_of::<InactiveAdoptionRequest>()),(32,8));
    assert_eq!([offset_of!(InactiveAdoptionRequest,abi),offset_of!(InactiveAdoptionRequest,operation),
        offset_of!(InactiveAdoptionRequest,invocation),offset_of!(InactiveAdoptionRequest,current_generation),
        offset_of!(InactiveAdoptionRequest,exact_peer),offset_of!(InactiveAdoptionRequest,suspended)],[0,4,8,16,24,28]);
    assert_eq!((size_of::<InactiveAdoptionOutcome>(),align_of::<InactiveAdoptionOutcome>()),(24,8));
    assert_eq!([offset_of!(InactiveAdoptionOutcome,abi),offset_of!(InactiveAdoptionOutcome,operation),
        offset_of!(InactiveAdoptionOutcome,invocation),offset_of!(InactiveAdoptionOutcome,disposition),
        offset_of!(InactiveAdoptionOutcome,route)],[0,4,8,16,20]);
    assert_eq!(current(owner()).header,Header{abi:1,domain:2,phase:1,count:179});
    assert_eq!(proposal(prepared(owner())).header,Header{abi:1,domain:4,phase:3,count:222});
}
#[test]
fn product_owner_inactive_stale_three_fences_preserve_full179_without_reads(){
    let c=current(times(owner()));for fence in 0..3{let mut r=request();r.suspended=1;
        let mut p=faulting(owner());p.applying_revision=57;
        match fence{0=>r.exact_peer=0,1=>r.current_generation=2,_=>p.expected_revision=58}
        let mut v=Provider::new();let(s,o)=call(r,c.clone(),proposal(p),&mut v);
        assert_eq!(s,1);assert!(v.seen.is_empty());success(&o,&c.atoms,0,0,&[]);journals(&o,&c,true);
    }
}
#[test]
fn product_owner_inactive_equal_coordinates_import_all_nine_prepared_origins(){
    let seed=times(owner());let c=current(seed);let p=proposal(prepared(seed));
    let expected=copy_expected(&c,&p,58,0,0,0);let mut v=Provider::new();
    let(s,o)=call(request(),c.clone(),p.clone(),&mut v);assert_eq!(s,1);assert!(v.seen.is_empty());
    success(&o,&expected,1,0,&[]);journals(&o,&p,false);assert_eq!(o.atoms[169..],c.atoms[169..]);
}
#[test]
fn product_owner_inactive_absent_prepared_times_clear_current_values(){
    let c=current(times(owner()));let p=proposal(prepared(owner()));
    let expected=copy_expected(&c,&p,58,0,0,0);let mut v=Provider::new();
    let(s,o)=call(request(),c.clone(),p,&mut v);assert_eq!(s,1);success(&o,&expected,1,0,&[]);
    assert_eq!(o.edits[..9],[Edit{action:2,..Edit::default()};9]);assert_eq!(o.coordinates[..9],[Time::default();9]);
    assert_eq!(o.atoms[169..],c.atoms[169..]);assert!(v.seen.is_empty());
}
#[test]
fn product_owner_inactive_expected_revision_not_applying_and_wrap_once(){
    for revision in [0,u64::MAX]{let mut seed=times(owner());seed.revision=revision;
        seed.policy.peer=Some(revision);seed.policy.probe_failures=i64::MAX;seed.policy.probe_cooldown=i64::MIN;
        seed.policy.last_average_delay=Some(Scalar(0x8000_0000_0000_0000));
        let c=current(seed);let mut p=prepared(seed);p.source_generation=revision;p.applying_revision=revision^1;
        let p=proposal(p);let expected=copy_expected(&c,&p,revision.wrapping_add(1),0,0,0);
        let mut r=request();r.current_generation=revision;let mut v=Provider::new();
        let(s,o)=call(r,c.clone(),p.clone(),&mut v);assert_eq!(s,1);
        success(&o,&expected,1,0,&[]);journals(&o,&p,false);assert_eq!(o.atoms[169..],c.atoms[169..]);
        assert!(v.seen.is_empty());
    }
}
#[test]
fn product_owner_inactive_route_action_and_presence_have_no_added_vote(){
    // These twelve typed scalar combinations are NOT twelve genuine native routes.
    for route in 0..3{for current_present in [false,true]{for proposed_present in [false,true]{
        let mut seed=times(owner());seed.policy.route_present=current_present;let c=current(seed);
        let mut p=prepared(times(owner()));p.policy.route_present=proposed_present;
        p.policy.configured_cap=32_123_456;p.policy.last_average_delay=Some(Scalar(0x7ff8_0000_0000_0044));
        p.route_action=match route{0=>RouteAction::Retain,1=>RouteAction::Clear,_=>RouteAction::CopyIncoming};
        let p=proposal(p);let expected=copy_expected(&c,&p,58,0,0,0);let mut v=Provider::new();
        let(s,o)=call(request(),c.clone(),p.clone(),&mut v);assert_eq!(s,1);
        success(&o,&expected,1,route,&[]);journals(&o,&p,false);
        assert_eq!(o.atoms[144],a(4,1,0,proposed_present as u64));assert_eq!(o.atoms[169..],c.atoms[169..]);
        assert!(v.seen.is_empty());
    }}}
}
#[test]
fn product_owner_inactive_clockless_suspension_short_circuit_has_literal_counters(){
    for branch in 0..6{let c=current(owner());let mut p=prepared(healthy(times(owner())));
        p.policy.suspension_pressure=9;p.policy.maximum_resume=2;p.policy.stable_resume=4;
        let mut r=request();r.suspended=1;
        match branch{0=>p.policy.rtt.faulted=true,1=>r.suspended=0,2=>p.policy.tier=Tier::Survival,
            3=>p.policy.maximum_resume=63,4=>p.policy.rtt.raw.health=0,_=>p.policy.rtt.raw.age_present=0}
        let p=proposal(p);let(pressure,stable,maximum,disposition)=match branch{
            0=>(9,4,2,1),1=>(0,0,0,1),2|3=>(0,0,0,2),_=>(0,0,3,1)};
        let expected=copy_expected(&c,&p,58,pressure,stable,maximum);let mut v=Provider::new();
        let(s,o)=call(r,c,p.clone(),&mut v);assert_eq!(s,1);success(&o,&expected,disposition,0,&[]);
        journals(&o,&p,false);assert!(v.seen.is_empty());
    }
}
#[test]
fn product_owner_inactive_healthy_L_read_adopts_or_requests_resume(){
    for stable in [4,15]{let c=current(owner());let mut p=prepared(healthy(times(owner())));
        p.policy.maximum_resume=2;p.policy.stable_resume=stable;p.policy.suspension_pressure=9;
        let p=proposal(p);let expected=copy_expected(&c,&p,58,0,if stable==15{0}else{5},3);
        let mut r=request();r.suspended=1;let mut v=Provider::new();let(s,o)=call(r,c,p.clone(),&mut v);
        assert_eq!(s,1);assert_eq!(v.seen,[(INV,3,0)]);success(&o,&expected,if stable==15{2}else{1},0,&[3]);
        journals(&o,&p,false);
    }
}
#[test]
fn product_owner_inactive_LQ_fault_preserves_native_prefix_and_original_journals(){
    let c=current(owner());let p=proposal(faulting(owner()));let mut r=request();r.suspended=1;
    let mut v=Provider::new();let(s,o)=call(r,c.clone(),p.clone(),&mut v);
    assert_eq!(s,1);assert_eq!(v.seen,[(INV,3,0),(INV,2,1)]);
    assert_eq!(o.header,Header{abi:1,domain:2,phase:2,count:179});
    assert_eq!(o.meta,Metadata{abi:1,operation:601,scope:2,read_count:2,invocation:INV,revision:58,
        peer:1,peer_present:1,rtt_fault:1,..Metadata::default()});
    assert_eq!(o.outcome,InactiveAdoptionOutcome{abi:1,operation:601,invocation:INV,disposition:1,route:0});
    let mut reads=[Reply::default();15];reads[0]=reply(0,3);reads[1]=reply(1,2);assert_eq!(o.reads,reads);
    assert_eq!(&o.atoms[169..],&c.atoms[169..]);assert_eq!(o.atoms[168],a(1,1,0,58));
    assert_eq!(&o.atoms[36..38],&p.atoms[36..38]);assert_eq!(&o.atoms[42..89],&p.atoms[42..89]);
    assert_eq!([o.atoms[29],o.atoms[30],o.atoms[31]],[a(2,1,0,0),a(2,1,0,4),a(2,1,0,3)]);
    assert_eq!(o.atoms[89],a(4,1,0,1));assert_eq!(o.atoms[38],a(2,1,0,0));
    for i in 0..9{if 0x00efu16&(1<<i)!=0{
        assert_eq!(o.edits[i],Edit{action:2,..Edit::default()});assert_eq!(o.coordinates[i],Time::default());
    }else{let a=p.atoms[TIME_ATOMS[i]];
        assert_eq!(o.edits[i],Edit{action:3,source:2,index:i as u32,ordinal:0,high:0,low:0});
        assert_eq!(o.coordinates[i],Time{present:a.present,reserved:0,high:a.high,low:a.low});
    }}
    assert_eq!(o.edits[9..],[Edit::default();4]);assert_eq!(o.coordinates[9..],[Time::default();4]);
    assert!(codec::validate_result(o.header,&o.atoms).is_ok()); // shape only; not a full LQ golden
}
#[test]
fn product_owner_inactive_each_provider_and_reply_denial_refuses_seven_outputs(){
    let c=current(owner());let mut r=request();r.suspended=1;
    for faulting_lane in [false,true]{let p=proposal(if faulting_lane{faulting(owner())}else{prepared(healthy(times(owner())))});
        let tags=if faulting_lane{vec![3,2]}else{vec![3]};
        for fail in 0..tags.len(){for returned in [0,2,u32::MAX]{
            let mut v=Provider::new();v.fail=fail;v.returned=returned;
            let(s,o)=call(r,c.clone(),p.clone(),&mut v);assert_eq!(s,3);assert_eq!(o,Output::sentinel());
            assert_eq!(v.seen,tags[..=fail].iter().enumerate().map(|(n,&site)|(INV,site,n as u32)).collect::<Vec<_>>());
        }}
        for corrupt in 1..=7{let mut v=Provider::new();v.corrupt=corrupt;
            let(s,o)=call(r,c.clone(),p.clone(),&mut v);
            assert_eq!(s,if corrupt==7{2}else{4});assert_eq!(o,Output::sentinel());assert_eq!(v.seen,[(INV,3,0)]);
        }
    }
}
#[test]
fn product_owner_inactive_closed_shapes_decode_both_inputs_before_stale(){
    let c=current(owner());let p=proposal(prepared(owner()));
    for field in 0..5{let mut r=request();match field{0=>r.abi=2,1=>r.operation=501,
        2=>r.invocation=0,3=>r.exact_peer=2,_=>r.suspended=2}
        let mut v=Provider::new();let(s,o)=call(r,c.clone(),p.clone(),&mut v);
        assert_eq!(s,2);assert_eq!(o,Output::sentinel());assert!(v.seen.is_empty());
    }
    let mut r=request();r.exact_peer=0;
    for domain in 0..2{for index in 0..(if domain==0{179}else{222}){
        let mut c=c.clone();let mut p=p.clone();if domain==0{c.atoms[index].kind=99}else{p.atoms[index].kind=99}
        let mut v=Provider::new();let(s,o)=call(r,c,p,&mut v);
        assert_eq!(s,2);assert_eq!(o,Output::sentinel());assert!(v.seen.is_empty());
    }}
    for field in 0..6{let mut c=c.clone();let mut p=p.clone();
        match field{0=>c.header.phase=2,1=>p.header.phase=1,2=>c.header.domain=4,
            3=>p.header.domain=2,4=>p.atoms[185].low=3,_=>p.atoms[144].low=2}
        let mut v=Provider::new();let(s,o)=call(r,c,p,&mut v);assert_eq!(s,2);
        assert_eq!(o,Output::sentinel());assert!(v.seen.is_empty());
    }
}
#[test]
fn product_owner_inactive_exact_ranges_counts_and_callback_required(){
    let c=current(owner());let p=proposal(prepared(owner()));let r=request();
    for which in 0..37{let mut o=Output::sentinel();let mut v=Provider::new();
        let mut args=Args::new(&r,&c,&p,&mut o,&mut v);
        match which{0..=11=>args.p[which]=0,12..=23=>args.p[which-12]+=1,
            24..=29=>args.n[which-24]-=1,30..=35=>args.n[which-30]+=1,_=>args.cb=None}
        assert_eq!(unsafe{args.run()},2);assert_eq!(o,Output::sentinel());assert!(v.seen.is_empty());
    }
    let mut o=Output::sentinel();let mut v=Provider::new();let mut args=Args::new(&r,&c,&p,&mut o,&mut v);
    args.p[6]=args.p[2];assert_eq!(unsafe{args.run()},2);assert_eq!(o,Output::sentinel());assert!(v.seen.is_empty());
}
