//! Ordinary source tests of the PUBLIC501 function. Input seeds may use the
//! stored-state encoder; expected results never call a reducer/result encoder.
//! No native Instant, route object, actor, producer identity or effect proof.
use crate::network_adaptation_owner_prepare_events::{
    beluga_core_network_adaptation_owner_prepare_event as event,
    PrepareRequest, PrepareOutcome, ReportWire,
};
use crate::native_clock_assay::{Callback, Edit, Metadata, Reply, Time};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec::{self as codec, Atom, Header};
use core::{ffi::c_void, mem::{size_of,align_of,offset_of},ptr};

const INV:u64=0x501_abcd_1234_5678;
const fn a(kind:u32,present:u32,high:i64,low:u64)->Atom {Atom{kind,present,high,low}}
fn request()->PrepareRequest {PrepareRequest {abi:1,operation:501,invocation:INV,
    source_generation:42,expected_revision:57,current_generation:42,entry_flags:127,
    capacity_only:0,allows_resume:0,report_present:0}}
fn seed(fault:bool)->codec::Wire {
    let mut owner=Owner::new(12_000_000,60,Dependencies::default());
    owner.policy.tier=Tier::Full;owner.policy.peer=Some(42);owner.policy.route_present=true;
    owner.policy.rtt.faulted=fault;owner.revision=57;owner.fast_statistics_available=true;
    owner.evidence_lane=Some(EvidenceLane::FastSender);owner.last_evidence=Some(-123);
    owner.freshness.minimum=Some(999);
    codec::encode_owner_snapshot(owner).unwrap()
}
fn rich_expiry()->codec::Wire {
    let mut owner=codec::decode_owner_snapshot(seed(true).header,&seed(true).atoms).unwrap();
    owner.policy.probe_deadline=Some(-10);owner.policy.probe_qualification_at=Some(-20);
    owner.policy.floor_first_witness=Some(FloorWitness{observed_at:-30,bandwidth:Scalar(0x7ff8_0000_0000_0030)});
    owner.policy.floor_cooldown_at=Some(-40);owner.policy.startup_sparse_deadline=Some(-50);
    owner.policy.queue.low_observation=Some(-60);owner.policy.queue.soft_observation=Some(-70);
    owner.policy.queue.faulted=true;owner.policy.queue.pressure_count=-7;
    owner.policy.rtt.last_advancement=Some(-80);owner.policy.rtt.raw.advancement_present=1;
    owner.policy.rtt.raw.reserved=0xdead;owner.policy.rtt.raw.baseline_bits=0x7ff8_0000_0000_0080;
    owner.applied=Some(Recommendation{tier:Tier::Critical,maximum_video:-91,
        maximum_total:765_432,fps:17,scale:Scalar(0x7ff8_0000_0000_0099)});
    codec::encode_owner_snapshot(owner).unwrap()
}
#[derive(Clone,Debug,PartialEq,Eq)]
struct Output {header:Header,atoms:[Atom;222],meta:Metadata,outcome:PrepareOutcome,
    edits:[Edit;13],coordinates:[Time;13],reads:[Reply;15]}
impl Output {fn sentinel()->Self {Self {
    header:Header{abi:701,domain:702,phase:703,count:704},atoms:[a(711,712,-713,714);222],
    meta:Metadata{abi:721,operation:722,scope:723,read_count:724,invocation:725,
        revision:726,peer:727,peer_present:728,bound:729,route:730,sample:731,
        enabled:732,lease:733,queue_fault:734,rtt_fault:735},
    outcome:PrepareOutcome{abi:741,operation:742,invocation:743,prepared_present:744,reserved:745},
    edits:[Edit{action:751,source:752,index:753,ordinal:754,high:-755,low:756};13],
    coordinates:[Time{present:761,reserved:762,high:-763,low:764};13],
    reads:[Reply{abi:771,status:772,site:773,ordinal:774,invocation:775,high:-776,low:777,reserved:778};15],
}}}
struct Clock {seen:Vec<u32>,fail:usize,returned:u32,corrupt:u32,bad_request:bool}
impl Clock {fn new()->Self {Self{seen:vec![],fail:usize::MAX,returned:1,corrupt:0,bad_request:false}}}
unsafe extern "C" fn callback(ctx:*mut c_void,inv:u64,site:u32,ordinal:u32,out:*mut Reply)->u32 {
    let clock=unsafe{&mut *ctx.cast::<Clock>()};let n=clock.seen.len();clock.seen.push(site);
    clock.bad_request|=inv!=INV||ordinal!=n as u32||site>4;
    let mut reply=Reply{abi:1,status:1,site,ordinal,invocation:inv,high:0,low:1_000_000+n as u64,reserved:0};
    match clock.corrupt {1=>reply.abi=2,2=>reply.status=0,3=>reply.site=site^1,
        4=>reply.ordinal=ordinal+1,5=>reply.invocation=inv^1,6=>reply.reserved=1,
        7=>{reply.high=i64::MAX;reply.low=u64::MAX;},_=>{}}
    // Write the otherwise valid reply even for non1 return-code tests. This
    // independently isolates provider-return admission from reply admission.
    unsafe{ptr::write(out,reply)};
    if n==clock.fail {clock.returned} else {1}
}
fn bytes<T>(v:&[T])->Vec<u8> {unsafe{
    core::slice::from_raw_parts(v.as_ptr().cast::<u8>(),core::mem::size_of_val(v)).to_vec()}}
#[derive(Clone,Copy)]
struct Args {p:[usize;12],n:[u32;5],cb:Option<Callback>,ctx:*mut c_void}
impl Args {
    fn new(r:&PrepareRequest,w:&codec::Wire,report:&ReportWire,t:&Time,o:&mut Output,c:&mut Clock)->Self {
        Self{p:[r as *const _ as usize,&w.header as *const _ as usize,w.atoms.as_ptr() as usize,
            report as *const _ as usize,t as *const _ as usize,&mut o.header as *mut _ as usize,
            o.atoms.as_mut_ptr() as usize,&mut o.meta as *mut _ as usize,&mut o.outcome as *mut _ as usize,
            o.edits.as_mut_ptr() as usize,o.coordinates.as_mut_ptr() as usize,o.reads.as_mut_ptr() as usize],
            n:[179,222,13,13,15],cb:Some(callback),ctx:(c as *mut Clock).cast()}
    }
    unsafe fn run(self)->u32 {unsafe{event(self.p[0] as *const PrepareRequest,self.p[1] as *const Header,
        self.p[2] as *const Atom,self.n[0],self.p[3] as *const ReportWire,self.p[4] as *const Time,
        self.cb,self.ctx,self.p[5] as *mut Header,self.p[6] as *mut Atom,self.n[1],
        self.p[7] as *mut Metadata,self.p[8] as *mut PrepareOutcome,self.p[9] as *mut Edit,self.n[2],
        self.p[10] as *mut Time,self.n[3],self.p[11] as *mut Reply,self.n[4])}}
}
fn call(r:&PrepareRequest,w:&codec::Wire,report:&ReportWire,t:Time,c:&mut Clock)->(u32,Output) {
    let before=[bytes(core::slice::from_ref(r)),bytes(core::slice::from_ref(&w.header)),bytes(&w.atoms),
        bytes(core::slice::from_ref(report)),bytes(core::slice::from_ref(&t))];
    let mut out=Output::sentinel();let status=unsafe{Args::new(r,w,report,&t,&mut out,c).run()};
    assert_eq!(before,[bytes(core::slice::from_ref(r)),bytes(core::slice::from_ref(&w.header)),bytes(&w.atoms),
        bytes(core::slice::from_ref(report)),bytes(core::slice::from_ref(&t))]);
    assert!(!c.bad_request);(status,out)
}
fn none(out:&Output,reads:&[u32],fault:bool) {
    assert_eq!(out.header,Header::default());assert_eq!(out.atoms,[Atom::default();222]);
    assert_eq!(out.edits,[Edit::default();13]);assert_eq!(out.coordinates,[Time::default();13]);
    assert_eq!(out.outcome,PrepareOutcome{abi:1,operation:501,invocation:INV,prepared_present:0,reserved:0});
    assert_eq!(out.meta,Metadata{abi:1,operation:501,scope:1,read_count:reads.len() as u32,
        invocation:INV,revision:57,peer:42,peer_present:1,rtt_fault:fault as u32,..Metadata::default()});
    for (n,&site) in reads.iter().enumerate() {assert_eq!(out.reads[n],Reply{abi:1,status:1,site,
        ordinal:n as u32,invocation:INV,high:0,low:1_000_000+n as u64,reserved:0});}
    assert_eq!(&out.reads[reads.len()..],&[Reply::default();15][reads.len()..]);
}
fn binding()->(PrepareRequest,codec::Wire,ReportWire) {
    let mut r=request();r.source_generation=43;r.current_generation=43;r.report_present=1;
    (r,seed(true),ReportWire::default())
}

#[test]
fn product_owner_prepare_pod_layout_and_counts() {
    assert_eq!((size_of::<PrepareRequest>(),align_of::<PrepareRequest>()),(56,8));
    assert_eq!([offset_of!(PrepareRequest,abi),offset_of!(PrepareRequest,operation),offset_of!(PrepareRequest,invocation),
        offset_of!(PrepareRequest,source_generation),offset_of!(PrepareRequest,expected_revision),offset_of!(PrepareRequest,current_generation),
        offset_of!(PrepareRequest,entry_flags),offset_of!(PrepareRequest,capacity_only),offset_of!(PrepareRequest,allows_resume),offset_of!(PrepareRequest,report_present)],
        [0,4,8,16,24,32,40,44,48,52]);
    assert_eq!((size_of::<PrepareOutcome>(),align_of::<PrepareOutcome>()),(24,8));
    assert_eq!((size_of::<ReportWire>(),align_of::<ReportWire>()),(192,8));
    assert_eq!((codec::OWNER_COUNT,codec::PREPARED_COUNT),(179,222));
}
#[test]
fn product_owner_prepare_zero_read_entry_none() {
    for vote in 0..5 {let mut r=request();match vote {0=>r.entry_flags&=!1,1=>r.entry_flags&=!2,
        2=>r.current_generation=43,3=>r.expected_revision=58,_=>r.entry_flags&=!4};
        let mut c=Clock::new();let(s,o)=call(&r,&seed(true),&ReportWire::default(),Time::default(),&mut c);
        assert_eq!(s,1);assert!(c.seen.is_empty());none(&o,&[],true);
    }
}
#[test]
fn product_owner_prepare_structural_validation_precedes_entry_none() {
    let mut r=request();r.entry_flags=0;let mut w=seed(true);w.atoms[178].kind=2;
    let mut c=Clock::new();let(s,o)=call(&r,&w,&ReportWire::default(),Time::default(),&mut c);
    assert_eq!(s,2);assert_eq!(o,Output::sentinel());assert!(c.seen.is_empty());
    w=seed(true);r.report_present=1;let bad=ReportWire{reserved:1,..ReportWire::default()};
    let(s,o)=call(&r,&w,&bad,Time::default(),&mut c);assert_eq!(s,2);assert_eq!(o,Output::sentinel());
}
#[test]
fn product_owner_prepare_expiry_full222_literal_tail_and_journals() {
    let w=rich_expiry();let mut c=Clock::new();let(s,o)=call(&request(),&w,&ReportWire::default(),Time::encode(Some(1)),&mut c);
    assert_eq!(s,1);assert!(c.seen.is_empty());assert_eq!(o.header,Header{abi:1,domain:4,phase:3,count:222});
    assert_eq!(&o.atoms[..168],&w.atoms[..168]);
    let mut tail=vec![a(1,1,0,42),a(1,1,0,57),a(1,1,0,57),a(6,1,0,2),a(4,1,0,1),a(4,1,0,0),a(4,1,0,0)];
    tail.extend([a(7,0,0,0),a(2,0,0,0),a(2,0,0,0),a(2,0,0,0),a(3,0,0,0)]);
    tail.extend([a(7,1,0,0),a(2,1,0,9_344_000),a(2,1,0,12_000_000),a(2,1,0,60),a(3,1,0,1f64.to_bits()),a(6,1,0,0),a(4,1,0,0)]);
    for kind in [1,4,4,4,4,2,1,1,1,1,1,3,3,1,2,2,6,6,6,6,1,6,4] {tail.push(a(kind,0,0,0));}
    tail.push(a(4,1,0,0));for kind in [6,7,1,1,1,2,2,1,1,1,1] {tail.push(a(kind,0,0,0));}
    assert_eq!(tail.len(),54);assert_eq!(&o.atoms[168..],tail);
    assert_eq!(o.outcome,PrepareOutcome{abi:1,operation:501,invocation:INV,prepared_present:1,reserved:0});
    assert_eq!(o.meta,Metadata{abi:1,operation:501,scope:1,invocation:INV,revision:57,
        peer:42,peer_present:1,queue_fault:1,rtt_fault:1,..Metadata::default()});
    for (i,index) in [Some(12),Some(23),Some(28),Some(159),Some(163),Some(167),Some(39),Some(40),Some(88),None,None,None,Some(171)].into_iter().enumerate() {
        if 0x00efu16&(1<<i)==0 {assert_eq!(o.edits[i],Edit::default());assert_eq!(o.coordinates[i],Time::default());continue;}
        assert_eq!(o.edits[i],Edit{action:if i==2 {2}else{1},..Edit::default()});
        let atom=w.atoms[index.unwrap()];assert_eq!(o.coordinates[i],Time{present:atom.present,reserved:0,high:atom.high,low:atom.low});
    }
    assert_eq!(o.reads,[Reply::default();15]);
}
#[test]
fn product_owner_prepare_late_none_preserves_real_read_transcript() {
    let mut owner=codec::decode_owner_snapshot(seed(false).header,&seed(false).atoms).unwrap();
    owner.policy.probe_origin=Some(Tier::Full);owner.policy.probe_deadline=Some(0);owner.policy.probe_maximum=Some(12_000_000);
    owner.applied=Some(Recommendation{tier:Tier::Full,maximum_video:9_344_000,maximum_total:12_000_000,fps:60,scale:Scalar::new(1.)});
    let w=codec::encode_owner_snapshot(owner).unwrap();let mut c=Clock::new();
    let(s,o)=call(&request(),&w,&ReportWire::default(),Time::encode(Some(1)),&mut c);
    assert_eq!(s,1);assert_eq!(c.seen,vec![2]);none(&o,&[2],false);
}
#[test]
fn product_owner_prepare_regular_binding_is_proposal_not_owner_publication() {
    let(r,w,report)=binding();let mut c=Clock::new();let(s,o)=call(&r,&w,&report,Time::encode(Some(1)),&mut c);
    assert_eq!(s,1);assert_eq!(c.seen,vec![2,0,1,0,1]);assert_eq!(o.outcome.prepared_present,1);
    assert_eq!(o.atoms[3],a(1,1,0,43));assert_eq!(o.atoms[144],a(4,1,0,0));
    assert_eq!(o.atoms[168],a(1,1,0,43));assert_eq!(o.atoms[169],a(1,1,0,57));assert_eq!(o.atoms[170],a(1,1,0,57));
    assert_eq!(o.atoms[171],a(6,1,0,0));assert_eq!(o.atoms[185],a(6,1,0,1));assert_eq!(o.meta.route,1);
    assert_eq!(o.meta.revision,57);assert_eq!(o.atoms[186],a(4,1,0,1));assert_eq!(o.atoms[210],a(4,1,0,0));
    assert!(codec::decode_prepared_continuation(o.header,&o.atoms).is_ok());
    // Real ReportWire input selects CopyIncoming; no proposed-policy preview is
    // supplied. Presence is only scalar evidence, not actual native route custody.
    let mut r=request();r.report_present=1;let report=ReportWire{incoming_present:1,
        collection_sequence_present:1,collection_sequence:1,..ReportWire::default()};
    let mut c=Clock::new();let(s,o)=call(&r,&seed(false),&report,Time::encode(Some(1)),&mut c);
    assert_eq!(s,1);assert_eq!(c.seen,vec![2,0,1]);assert_eq!(o.meta.route,2);
    assert_eq!(o.atoms[144],a(4,1,0,1));assert_eq!(o.atoms[185],a(6,1,0,2));
    assert!(codec::decode_prepared_continuation(o.header,&o.atoms).is_ok());
}
#[test]
fn product_owner_prepare_capacity_lane_retains_route_and_no_eager_read() {
    let mut r=request();r.capacity_only=1;r.report_present=1;let mut c=Clock::new();
    let(s,o)=call(&r,&seed(true),&ReportWire::default(),Time::encode(Some(1)),&mut c);
    assert_eq!(s,1);assert!(c.seen.is_empty());assert_eq!(o.atoms[171],a(6,1,0,1));
    assert_eq!(o.atoms[173],a(4,1,0,1));assert_eq!(o.atoms[185],a(6,1,0,0));
    assert_eq!(o.atoms[186],a(4,1,0,0));assert_eq!(o.atoms[210],a(4,1,0,1));
    assert_eq!(o.meta.route,0);assert!(codec::decode_prepared_continuation(o.header,&o.atoms).is_ok());
    // Entry facts, not untrusted report capture/peer flags, own preparation's
    // active state. allows_resume admits the original inactive branch.
    r.entry_flags=3;r.allows_resume=1;let report=ReportWire{peer:999,capture_active:1,..ReportWire::default()};
    let mut c=Clock::new();let(s,o)=call(&r,&seed(true),&report,Time::encode(Some(1)),&mut c);
    assert_eq!(s,1);assert_eq!(o.atoms[172],a(4,1,0,0));assert_eq!(o.atoms[168],a(1,1,0,42));
    assert!(c.seen.is_empty());
}
#[test]
fn product_owner_prepare_provider_denial_all_seven_outputs_untouched() {
    let(r,w,report)=binding();for fail in 0..5 {for returned in [0,2,u32::MAX] {
        let mut c=Clock::new();c.fail=fail;c.returned=returned;
        let(s,o)=call(&r,&w,&report,Time::encode(Some(1)),&mut c);
        assert_eq!(s,3);assert_eq!(o,Output::sentinel());assert_eq!(c.seen.len(),fail+1);
    }}
}
#[test]
fn product_owner_prepare_reply_denial_all_seven_outputs_untouched() {
    let(r,w,report)=binding();for corrupt in 1..=7 {let mut c=Clock::new();c.corrupt=corrupt;
        let(s,o)=call(&r,&w,&report,Time::encode(Some(1)),&mut c);
        assert_eq!(s,if corrupt==7 {2}else{4});assert_eq!(o,Output::sentinel());assert_eq!(c.seen,vec![2]);
    }
}
#[test]
fn product_owner_prepare_closed_request_and_report_shape() {
    let w=seed(true);for field in 0..8 {let mut r=request();match field {0=>r.abi=2,1=>r.operation=401,
        2=>r.invocation=0,3=>r.entry_flags|=256,4=>r.capacity_only=2,5=>r.allows_resume=2,6=>r.report_present=2,_=>r.operation=601};
        let mut c=Clock::new();let(s,o)=call(&r,&w,&ReportWire::default(),Time::encode(Some(1)),&mut c);
        assert_eq!(s,2);assert_eq!(o,Output::sentinel());assert!(c.seen.is_empty());
    }
    let mut c=Clock::new();let(s,o)=call(&request(),&w,&ReportWire{peer:42,..ReportWire::default()},Time::encode(Some(1)),&mut c);
    assert_eq!(s,2);assert_eq!(o,Output::sentinel());
    let(s,o)=call(&request(),&w,&ReportWire::default(),Time::default(),&mut c);assert_eq!(s,2);assert_eq!(o,Output::sentinel());
}
#[test]
fn product_owner_prepare_report_bits_lossless_and_nonmeasurement_canonical() {
    let report=ReportWire{peer:42,observation_kind:2,fingerprint_length:65,fingerprint:[0x1234;8],
        measurement_total_bits:0x7ff8_0000_0000_0011,measurement_responses:9,
        bandwidth_present:1,bandwidth_bits:0x8000_0000_0000_0000,current_rtt_present:1,
        current_rtt_bits:0x7ff8_0000_0000_0022,native_timestamp_present:1,native_timestamp_bits:0x7ff8_0000_0000_0033,
        ..ReportWire::default()};
    let decoded=report.decode(-123).unwrap();assert_eq!(decoded.observed_at,-123);
    assert_eq!(decoded.bandwidth.unwrap().0,0x8000_0000_0000_0000);assert_eq!(decoded.current_rtt.unwrap().0,0x7ff8_0000_0000_0022);
    assert_eq!(decoded.native_timestamp.unwrap().0,0x7ff8_0000_0000_0033);
    assert_eq!(decoded.observation,Observation::Measurement{fingerprint:[0x1234;8],fingerprint_length:65,
        total_bits:0x7ff8_0000_0000_0011,responses:9});
    assert!(ReportWire{observation_kind:1,..report}.decode(0).is_err());
    assert!(ReportWire{bandwidth_present:0,..report}.decode(0).is_err());
}
#[test]
fn product_owner_prepare_exact_ranges_counts_and_callback_required() {
    let w=seed(true);let r=request();let report=ReportWire::default();let t=Time::encode(Some(1));
    for which in 0..30 {let mut c=Clock::new();let mut o=Output::sentinel();let before=o.clone();
        let mut args=Args::new(&r,&w,&report,&t,&mut o,&mut c);
        match which {0..=11=>args.p[which]=0,12..=23=>args.p[which-12]+=1,
            24..=28=>args.n[which-24]-=1,_=>args.cb=None};
        assert_eq!(unsafe{args.run()},2);assert_eq!(o,before);assert!(c.seen.is_empty());
    }
    let mut c=Clock::new();let mut o=Output::sentinel();let mut args=Args::new(&r,&w,&report,&t,&mut o,&mut c);
    args.p[6]=args.p[2];assert_eq!(unsafe{args.run()},2);assert_eq!(o,Output::sentinel());assert!(c.seen.is_empty());
}

// One additive complete222 golden for the reviewed native Regular [] branch.
// Input-only encoding is allowed; no result encoder, decoder or reducer computes
// expectations. The policy prefix is the input plus the specified literal
// terminal-helper deltas; every continuation/diagnostic atom is named below.
#[test]
fn product_owner_prepare_bound_terminal_regular_full222_zero_reads() {
    const OBSERVED:i128=1_000_000_000_000_000_123;
    const WITNESS:i128=750_000_000_000_000_123;
    for demand_fault in [false,true] {
        let mut owner=Owner::new(12_000_000,60,Dependencies::default());
        owner.revision=57;owner.fast_statistics_available=true;
        owner.evidence_lane=Some(EvidenceLane::FastSender);owner.last_evidence=Some(-123);
        owner.freshness.minimum=Some(80);
        owner.applied=Some(Recommendation{tier:Tier::Critical,maximum_video:765_431,
            maximum_total:765_432,fps:17,scale:Scalar(0x7ff8_0000_0000_0099)});
        let p=&mut owner.policy;
        p.peer=Some(42);p.tier=Tier::Full;p.route_present=true;
        p.rtt.faulted=!demand_fault;p.demand.faulted=demand_fault;
        p.healthy_upgrades=8;p.limited_upgrades=9;p.probe_cooldown=9;
        p.probe_origin=None;p.probe_deadline=Some(-10);p.probe_qualification_at=Some(-20);
        p.promotion=Some(Promotion{tier:Tier::Full,maximum_total:11_000_000,deadline:-42});
        p.below_reserve_disproved=true;p.last_average_delay=Some(Scalar(0x8000_0000_0000_0000));
        p.queue.packets=Some(77);p.queue.delay_bits=Some(0.25f64.to_bits());
        p.queue.pressure_count=4;p.queue.low_observation=Some(-60);p.queue.soft_observation=Some(-70);
        p.rtt.last_advancement=Some(-80);p.rtt.raw.advancement_present=1;
        p.consumed_sequence=Some(85);p.capacity_sequence=Some(86);
        p.capacity_timestamp=Some(Scalar::new(123.75));
        p.floor_show=Some(7);p.floor_reserved=true;p.floor_active=true;p.floor_attempt_consumed=true;
        p.floor_first_witness=Some(FloorWitness{observed_at:WITNESS,bandwidth:Scalar::new(300_000.)});
        p.floor_regular_sequence=Some(87);p.floor_regular_timestamp=Some(Scalar::new(120.25));
        p.floor_cooldown_at=Some(-40);
        p.startup_peer=Some(42);p.startup_show=Some(7);p.startup_disproved=false;
        p.startup_sparse_deadline=Some(-50);
        let w=codec::encode_owner_snapshot(owner).unwrap();
        let mut r=request();r.report_present=1;
        // Same input shape as native report capture: entry fields remain zero
        // here; genuine 501 sets peer/active/suspended, and Regular sets strict.
        // Incoming is different from retained, but terminal return precedes route
        // selection: Retain must keep the original route, not CopyIncoming.
        let report=ReportWire{incoming_present:1,equal_to_retained:0,observation_kind:1,
            collection_sequence_present:1,collection_sequence:88,
            bandwidth_present:1,bandwidth_bits:500_000f64.to_bits(),
            current_rtt_present:1,current_rtt_bits:0.004f64.to_bits(),
            packets_present:1,packets:999,delay_present:1,delay_bits:0.125f64.to_bits(),
            native_timestamp_present:1,native_timestamp_bits:42_000.5f64.to_bits(),
            ..ReportWire::default()};
        // A zero-permission native frame denies the first unexpected cut. The
        // actual invocation must not reach this callback, not merely hide reads.
        let mut c=Clock::new();c.fail=0;c.returned=0;
        let(s,o)=call(&r,&w,&report,Time{present:1,reserved:0,high:0,low:OBSERVED as u64},&mut c);
        assert_eq!(s,1);assert_eq!(c.seen,Vec::<u32>::new());

        // Full168 policy copy contract, with only the original terminal helper's
        // literal changes. These positions are copied from the named codec
        // ledger, never obtained by executing try_update/try_prepare.
        let mut expected=w.atoms[..168].to_vec();
        expected[5]=a(2,1,0,0); // healthy_upgrades
        expected[9]=a(2,1,0,0); // limited_upgrades
        expected[25]=a(4,1,0,0); // promotion absent
        expected[26]=a(7,0,0,0); // promotion tier
        expected[27]=a(2,0,0,0); // promotion maximum_total
        expected[28]=a(10,0,0,0); // promotion deadline
        expected[166]=a(4,1,0,1); // startup_disproved
        expected[167]=a(10,0,0,0); // startup_sparse_deadline

        // Full54 continuation tail. Floors are present complete diagnostics,
        // captured before the terminal helper except proposed_total afterward.
        expected.extend([
            a(1,1,0,42), //168 source_generation
            a(1,1,0,57), //169 expected_revision
            a(1,1,0,57), //170 applying_revision
            a(6,1,0,0), //171 Regular lane
            a(4,1,0,1), //172 capture_active from entry
            a(4,1,0,0), //173 capacity_only
            a(4,1,0,1), //174 changed present: removal of11M promotion
            a(7,1,0,0), //175 changed Full
            a(2,1,0,9_344_000), //176 changed maximum_video
            a(2,1,0,12_000_000), //177 changed maximum_total
            a(2,1,0,60), //178 changed fps
            a(3,1,0,0x3ff0_0000_0000_0000), //179 changed scale1
            a(7,1,0,0), //180 recommendation Full
            a(2,1,0,9_344_000), //181 recommendation maximum_video
            a(2,1,0,12_000_000), //182 recommendation maximum_total
            a(2,1,0,60), //183 recommendation fps
            a(3,1,0,0x3ff0_0000_0000_0000), //184 recommendation scale1
            a(6,1,0,0), //185 Retain route
            a(4,1,0,1), //186 floor_diagnostics present
            a(1,1,0,7), //187 show_epoch
            a(4,1,0,1), //188 reserved
            a(4,1,0,1), //189 active
            a(4,1,0,1), //190 consumed
            a(4,1,0,1), //191 disproved (below_reserve, not startup flag)
            a(2,1,0,9), //192 cooldown_remaining
            a(1,1,0,88), //193 collection_sequence
            a(1,1,0,87), //194 previous_regular_sequence
            a(1,1,0,120), //195 previous_regular_report_microseconds round120.25
            a(1,1,0,124), //196 capacity_report_microseconds round123.75
            a(1,1,0,42_001), //197 native_report_microseconds round42000.5
            a(3,1,0,500_000f64.to_bits()), //198 current_bandwidth
            a(3,1,0,300_000f64.to_bits()), //199 first_bandwidth
            a(1,1,0,250_000), //200 witness_age: original observed time minus witness
            a(2,1,0,11_000_000), //201 before_total includes retained promotion
            a(2,1,0,12_000_000), //202 proposed_total after promotion removal
            a(6,1,0,3), //203 Rising trend
            a(6,1,0,0), //204 identity NotChecked
            a(6,1,0,0), //205 reason NotEvaluated
            a(6,1,0,0), //206 queue_kind NotChecked
            a(1,0,0,0), //207 queue_microseconds absent
            a(6,0,0,0), //208 rtt_disposition absent
            a(4,0,0,0), //209 rtt_allows_upgrade absent
            a(4,1,0,0), //210 capacity_diagnostics absent
            a(6,0,0,0), //211 capacity reason
            a(7,0,0,0), //212 capacity origin
            a(1,0,0,0), //213 capacity collection_sequence
            a(1,0,0,0), //214 capacity previous_native_microseconds
            a(1,0,0,0), //215 capacity native_microseconds
            a(2,0,0,0), //216 capacity before_total
            a(2,0,0,0), //217 capacity proposed_total
            a(1,0,0,0), //218 collapse_threshold
            a(1,0,0,0), //219 delta_packets
            a(1,0,0,0), //220 delta_delay_microseconds
            a(1,0,0,0), //221 average_queue_microseconds
        ]);
        assert_eq!(expected.len(),222);
        let expected=Output{header:Header{abi:1,domain:4,phase:3,count:222},
            atoms:expected.try_into().unwrap(),
            meta:Metadata{abi:1,operation:501,scope:1,invocation:INV,revision:57,
                peer:42,peer_present:1,rtt_fault:(!demand_fault) as u32,..Metadata::default()},
            outcome:PrepareOutcome{abi:1,operation:501,invocation:INV,prepared_present:1,reserved:0},
            edits:[
                Edit{action:1,..Edit::default()}, //0 retain probe deadline
                Edit{action:1,..Edit::default()}, //1 retain probe qualification
                Edit{action:2,..Edit::default()}, //2 clear promotion
                Edit{action:1,..Edit::default()}, //3 retain witness
                Edit{action:1,..Edit::default()}, //4 retain cooldown
                Edit{action:2,..Edit::default()}, //5 clear disproved startup sparse
                Edit{action:1,..Edit::default()}, //6 retain queue low
                Edit{action:1,..Edit::default()}, //7 retain queue soft
                Edit{action:1,..Edit::default()}, //8 retain RTT advancement
                Edit::default(),Edit::default(),Edit::default(),Edit::default(),
            ],
            coordinates:[
                Time{present:1,reserved:0,high:-1,low:u64::MAX-9},
                Time{present:1,reserved:0,high:-1,low:u64::MAX-19},
                Time::default(),
                Time{present:1,reserved:0,high:0,low:750_000_000_000_000_123},
                Time{present:1,reserved:0,high:-1,low:u64::MAX-39},
                Time::default(),
                Time{present:1,reserved:0,high:-1,low:u64::MAX-59},
                Time{present:1,reserved:0,high:-1,low:u64::MAX-69},
                Time{present:1,reserved:0,high:-1,low:u64::MAX-79},
                Time::default(),Time::default(),Time::default(),Time::default(),
            ],
            reads:[Reply::default();15]};
        assert_eq!(o,expected);
    }
}
