//! SOURCE-ONLY public wrapper fixtures. The full179 seed and literal field edits
//! are retained from the independently authored clock fixture; expected values
//! never call a reducer, the private raw entrypoint, or a result encoder.
//! This is not native actor, actual Instant, authentication, or installed proof.
use crate::network_adaptation_owner_clocked_events::{
    beluga_core_network_adaptation_owner_clocked_event as event, RawOwnerClockedEventRequest,
};
use crate::native_clock_assay::{Callback, Edit, Metadata, Reply, Time};
use crate::network_adaptation_candidate::{Owner, Dependencies};
use crate::network_adaptation_candidate::state_codec::{self as codec, Atom, Header};
use core::{ffi::c_void, mem::{align_of, offset_of, size_of}, ptr};

const fn a(kind:u32,present:u32,high:i64,low:u64)->Atom { Atom{kind,present,high,low} }
const OWNER:Header=Header{abi:1,domain:2,phase:1,count:179};
const RESULT:Header=Header{abi:1,domain:2,phase:2,count:179};
const TIME_ATOMS:[Option<usize>;13]=[Some(12),Some(23),Some(28),Some(159),Some(163),Some(167),
    Some(39),Some(40),Some(88),None,None,None,Some(171)];
const INVOCATION:u64=0xfeed_abcd_7654_3210;

// Frozen, independently indexed transport atoms. Inner RTT DTO words are opaque.
const RICH:[Atom;179]=[
    a(2,1,0,1000),a(2,1,0,1001),a(2,1,0,1002),a(1,1,0,10003),a(7,1,0,5),
    a(2,1,0,1005),a(2,1,0,1006),a(2,1,0,1007),a(2,1,0,1008),a(2,1,0,1009),
    a(2,1,0,1010),a(2,1,0,1011),a(10,1,0,1000012),a(2,1,0,1013),a(2,1,0,1014),
    a(4,1,0,1),a(4,1,0,1),a(4,1,0,0),a(2,1,0,1018),a(2,1,0,1019),
    a(7,1,0,3),a(7,1,0,4),a(7,1,0,6),a(10,1,0,1000023),a(2,1,0,1024),
    a(4,1,0,1),a(7,1,0,1),a(2,1,0,1027),a(10,1,0,1000028),a(2,1,0,1029),
    a(2,1,0,1030),a(2,1,0,1031),a(4,1,0,0),a(4,1,0,1),a(4,1,0,0),
    a(3,1,0,0x7ff8_0000_0000_0023),a(1,1,0,10036),a(3,1,0,0x7ff8_0000_0000_0025),
    a(2,1,0,1038),a(10,1,0,1000039),a(10,1,0,1000040),a(4,1,0,1),
    a(6,1,0,20042),a(6,1,0,20043),a(6,1,0,20044),a(6,1,0,20045),a(6,1,0,20046),
    a(6,1,0,20047),a(6,1,0,20048),a(6,1,0,20049),a(6,1,0,20050),a(6,1,0,20051),
    a(6,1,0,20052),a(6,1,0,20053),a(6,1,0,20054),a(6,1,0,20055),a(6,1,0,20056),
    a(6,1,0,20057),a(6,1,0,20058),a(6,1,0,20059),
    a(3,1,0,0x7ff8_0000_0000_003c),a(3,1,0,0x7ff8_0000_0000_003d),
    a(3,1,0,0x7ff8_0000_0000_003e),a(3,1,0,0x7ff8_0000_0000_003f),a(3,1,0,0x7ff8_0000_0000_0040),
    a(2,1,0,1065),a(2,1,0,1066),a(1,1,0,10067),a(1,1,0,10068),a(1,1,0,10069),
    a(1,1,0,10070),a(1,1,0,10071),a(1,1,0,10072),a(1,1,0,10073),a(1,1,0,10074),
    a(3,1,0,0x7ff8_0000_0000_004b),a(1,1,0,10076),a(1,1,0,10077),a(1,1,0,10078),
    a(1,1,0,10079),a(1,1,0,10080),a(1,1,0,10081),a(1,1,0,10082),a(1,1,0,10083),a(1,1,0,10084),
    a(3,1,0,0x7ff8_0000_0000_0055),a(1,1,0,10086),a(3,1,0,0x7ff8_0000_0000_0057),
    a(10,1,0,1000088),a(4,1,0,1),a(6,1,0,20090),
    a(2,1,0,1091),a(2,1,0,1092),a(2,1,0,1093),a(2,1,0,1094),a(3,1,0,0x7ff8_0000_0000_005f),a(2,1,0,1096),
    a(2,1,0,1097),a(2,1,0,1098),a(2,1,0,1099),a(2,1,0,1100),a(3,1,0,0x7ff8_0000_0000_0065),a(2,1,0,1102),
    a(2,1,0,1103),a(2,1,0,1104),a(2,1,0,1105),a(2,1,0,1106),a(3,1,0,0x7ff8_0000_0000_006b),a(2,1,0,1108),
    a(2,1,0,1109),a(2,1,0,1110),a(2,1,0,1111),a(2,1,0,1112),a(3,1,0,0x7ff8_0000_0000_0071),a(2,1,0,1114),
    a(2,1,0,1115),a(2,1,0,1116),a(2,1,0,1117),a(2,1,0,1118),a(3,1,0,0x7ff8_0000_0000_0077),a(2,1,0,1120),
    a(2,1,0,1121),a(2,1,0,1122),a(2,1,0,1123),a(2,1,0,1124),a(3,1,0,0x7ff8_0000_0000_007d),a(2,1,0,1126),
    a(2,1,0,1127),a(2,1,0,1128),a(2,1,0,1129),a(2,1,0,1130),a(3,1,0,0x7ff8_0000_0000_0083),a(2,1,0,1132),
    a(2,1,0,1133),a(2,1,0,1134),a(2,1,0,1135),a(2,1,0,1136),a(3,1,0,0x7ff8_0000_0000_0089),a(2,1,0,1138),
    a(5,1,0,250),a(4,1,0,1),a(5,1,0,251),a(2,1,0,1142),a(1,1,0,10143),a(4,1,0,0),
    a(4,1,0,1),a(1,1,0,10146),a(3,1,0,0x7ff8_0000_0000_0093),a(3,1,0,0x7ff8_0000_0000_0094),
    a(3,1,0,0x7ff8_0000_0000_0095),a(1,1,0,10150),a(4,1,0,1),a(1,1,0,10152),
    a(4,1,0,0),a(4,1,0,1),a(4,1,0,0),a(4,1,0,1),a(3,1,0,0x7ff8_0000_0000_009d),
    a(4,1,0,1),a(10,1,0,1000159),a(3,1,0,0x7ff8_0000_0000_00a0),
    a(1,1,0,10161),a(3,1,0,0x7ff8_0000_0000_00a2),a(10,1,0,1000163),
    a(1,1,0,10164),a(1,1,0,10165),a(4,1,0,0),a(10,1,0,1000167),
    a(1,1,0,u64::MAX),a(4,1,0,1),a(8,1,0,1),a(10,1,0,1000171),a(1,1,0,10172),
    a(4,1,0,1),a(7,1,0,2),a(2,1,0,1175),a(2,1,0,1176),a(2,1,0,1177),a(3,1,0,0x7ff8_0000_0000_00b2),
];

fn request(operation:u32)->RawOwnerClockedEventRequest {
    RawOwnerClockedEventRequest {abi:1,operation,generation:0,invocation:INVOCATION,
        show:0,minimum:0,flag:0,minimum_present:0}
}
fn none(atoms:&mut [Atom],index:usize) { atoms[index]=a(atoms[index].kind,0,0,0); }
fn put(atoms:&mut [Atom],index:usize,value:u64) { atoms[index]=a(atoms[index].kind,1,0,value); }
fn zero(atoms:&mut [Atom],indices:&[usize]) { for &index in indices { put(atoms,index,0); } }
fn absent(atoms:&mut [Atom],indices:&[usize]) { for &index in indices { none(atoms,index); } }
fn no_witness(atoms:&mut [Atom]) { put(atoms,158,0); absent(atoms,&[159,160]); }
fn no_promotion(atoms:&mut [Atom]) { put(atoms,25,0); absent(atoms,&[26,27,28]); }
fn no_restoration(atoms:&mut [Atom]) { put(atoms,16,0); absent(atoms,&[17,18,19]); }
fn no_capacity(atoms:&mut [Atom]) { put(atoms,145,0); absent(atoms,&[146,147,148]); }
fn no_startup(atoms:&mut [Atom]) { absent(atoms,&[164,165,167]); put(atoms,166,0); }
fn queue_for_tier(atoms:&mut [Atom],clears:&mut Vec<usize>) {
    no_witness(atoms); no_capacity(atoms); no_promotion(atoms); clears.extend([3,2]);
    if atoms[41].low==0 { zero(atoms,&[38]); absent(atoms,&[39,40]); clears.extend([6,7]); }
}
fn revert(atoms:&mut [Atom],clears:&mut Vec<usize>) {
    if atoms[20].present==0 { return; }
    if atoms[157].present==1 && atoms[20].low==7 { put(atoms,156,1); none(atoms,157); }
    atoms[4]=atoms[20]; queue_for_tier(atoms,clears);
    absent(atoms,&[20,21,22,23,24,12]); zero(atoms,&[10,11]); clears.extend([1,0]);
}
fn end_show(atoms:&mut [Atom],clears:&mut Vec<usize>) {
    no_startup(atoms); zero(atoms,&[153,154]); no_witness(atoms); clears.extend([5,3]);
    if (atoms[157].present==1 && atoms[20].present==1 && atoms[20].low==7) || atoms[22].present==1 {
        revert(atoms,clears);
    }
}
fn restrict(atoms:&mut [Atom],clears:&mut Vec<usize>) {
    revert(atoms,clears); no_promotion(atoms); clears.push(2);
    if atoms[166].low==0 && atoms[164].present==1 && atoms[165].present==1 &&
        atoms[3]==atoms[164] && atoms[152]==atoms[165] && (atoms[153].low==1 || atoms[154].low==1) {
        put(atoms,166,1); none(atoms,167); clears.push(5);
    }
    zero(atoms,&[5,9]);
}
fn reset_path(atoms:&mut [Atom],clears:&mut Vec<usize>) {
    no_witness(atoms); absent(atoms,&[22,23]); clears.extend([3,1]);
    if atoms[157].present==1 && atoms[20].present==1 && atoms[20].low==7 { put(atoms,156,1); }
    none(atoms,157); no_capacity(atoms); no_promotion(atoms); clears.push(2);
    zero(atoms,&[5,6]);
    if atoms[41].low==0 { absent(atoms,&[36,37,39,40]); put(atoms,38,0); clears.extend([6,7]); }
    zero(atoms,&[7,8,9,10,11,15,13,14,32,33,34]); absent(atoms,&[12,20,21,24,35]);
    no_restoration(atoms); clears.push(0);
    // Sticky RTT-fault fixture: both reads execute, but its raw DTO and stamp are retained.
}
fn reset_incomplete(atoms:&mut [Atom],clears:&mut Vec<usize>) {
    no_witness(atoms); no_capacity(atoms); no_promotion(atoms); clears.extend([3,2]);
    zero(atoms,&[5,6,7,8,9,10]); none(atoms,21);
    if atoms[41].low==0 { put(atoms,38,0); absent(atoms,&[39,40]); clears.extend([6,7]); }
}
fn resume_began(atoms:&mut [Atom],clears:&mut Vec<usize>) {
    end_show(atoms,clears); no_promotion(atoms); clears.push(2);
    if atoms[16].low==1 { return; }
    put(atoms,16,1); atoms[17]=atoms[15]; atoms[18]=atoms[13]; atoms[19]=atoms[14];
    zero(atoms,&[15,9,13,14]);
}
fn resume_failed(atoms:&mut [Atom],clears:&mut Vec<usize>) {
    no_witness(atoms); clears.push(3);
    if atoms[157].present==1 && atoms[20].present==1 && atoms[20].low==7 { put(atoms,156,1); }
    none(atoms,157);
    if atoms[16].low==1 { atoms[15]=atoms[17]; atoms[13]=atoms[18]; atoms[14]=atoms[19]; }
    no_restoration(atoms); put(atoms,4,7); absent(atoms,&[22,23]); clears.push(1);
    queue_for_tier(atoms,clears); zero(atoms,&[5,6,9,10,11,29,30,31]);
    absent(atoms,&[12,20,21,24]); clears.push(0);
}

const OPERATIONS:[u32;8]=[202,212,213,214,215,216,217,218];
fn mask(operation:u32,show:bool)->u16 {
    match operation {
        202|213|215|217=>0x00ef,212=>0x10ef,
        214=>if show {0x01ff} else {0x00ef},216=>0x10cc,218=>0x00cf,
        _=>panic!("not a wrapper fixture operation"),
    }
}
fn literal_case(operation:u32)->(RawOwnerClockedEventRequest,[Atom;179],Vec<usize>,Vec<u32>,u32) {
    let mut req=request(operation);let mut expected=RICH;let mut clear=vec![];
    let plan=match operation {
        202|213=>{end_show(&mut expected,&mut clear);vec![2]},
        212=>{put(&mut expected,144,0);revert(&mut expected,&mut clear);
            reset_path(&mut expected,&mut clear);vec![2,2,0,1]},
        214=>{req.generation=10003;req.show=10153;req.flag=1;
            end_show(&mut expected,&mut clear);put(&mut expected,152,10153);
            put(&mut expected,153,1);zero(&mut expected,&[155,156]);vec![2]},
        215=>{none(&mut expected,167);no_witness(&mut expected);clear.extend([5,3]);
            revert(&mut expected,&mut clear);put(&mut expected,10,0);
            restrict(&mut expected,&mut clear);vec![2,0,1]},
        216=>{reset_incomplete(&mut expected,&mut clear);req.minimum_present=1;
            req.minimum=10200;put(&mut expected,172,10200);vec![2]},
        217=>{resume_began(&mut expected,&mut clear);vec![2]},
        218=>{resume_failed(&mut expected,&mut clear);vec![2]},
        _=>panic!("not a wrapper fixture operation"),
    };
    if matches!(operation,212|213|214|216|217|218) {put(&mut expected,168,0);}
    if matches!(operation,212|216) {absent(&mut expected,&[170,171]);clear.push(12);}
    (req,expected,clear,plan,if operation==212 {1} else {0})
}

#[derive(Clone,Debug,PartialEq,Eq)]
struct Output {
    header:Header,atoms:[Atom;179],metadata:Metadata,edits:[Edit;13],times:[Time;13],reads:[Reply;15],
}
impl Output {
    fn sentinel()->Self {Self {
        header:Header{abi:701,domain:702,phase:703,count:704},atoms:[a(711,712,-713,714);179],
        metadata:Metadata{abi:721,operation:722,scope:723,read_count:724,invocation:725,
            revision:726,peer:727,peer_present:728,bound:729,route:730,sample:731,
            enabled:732,lease:733,queue_fault:734,rtt_fault:735},
        edits:[Edit{action:741,source:742,index:743,ordinal:744,high:-745,low:746};13],
        times:[Time{present:751,reserved:752,high:-753,low:754};13],
        reads:[Reply{abi:761,status:762,site:763,ordinal:764,invocation:765,high:-766,low:767,reserved:768};15],
    }}
    fn bytes(&self)->[Vec<u8>;6] {
        [bytes(core::slice::from_ref(&self.header)),bytes(&self.atoms),
         bytes(core::slice::from_ref(&self.metadata)),bytes(&self.edits),bytes(&self.times),bytes(&self.reads)]
    }
}
fn bytes<T:Copy>(v:&[T])->Vec<u8> {
    unsafe {core::slice::from_raw_parts(v.as_ptr().cast(),core::mem::size_of_val(v)).to_vec()}
}
struct Clock {expected:Vec<u32>,seen:Vec<u32>,fail:usize,failure_return:u32,corrupt:u32,corrupt_at:usize,mismatch:bool}
impl Clock {
    fn new(expected:&[u32])->Self {Self {expected:expected.to_vec(),seen:vec![],
        fail:usize::MAX,failure_return:0,corrupt:0,corrupt_at:0,mismatch:false}}
}
unsafe extern "C" fn callback(context:*mut c_void,invocation:u64,site:u32,ordinal:u32,out:*mut Reply)->u32 {
    let clock=unsafe{&mut *context.cast::<Clock>()};let n=clock.seen.len();clock.seen.push(site);
    clock.mismatch|=clock.expected.get(n)!=Some(&site)||ordinal!=n as u32||invocation!=INVOCATION;
    if n==clock.fail {
        // A nonzero denial carries an otherwise exact valid reply, so a weakened
        // "reject only zero" return-code vote cannot hide behind reply rejection.
        if clock.failure_return!=0 {
            unsafe{ptr::write(out,Reply{abi:1,status:1,site,ordinal,invocation,
                high:0,low:9_000_000+n as u64,reserved:0})};
        }
        return clock.failure_return;
    }
    let mut reply=Reply{abi:1,status:1,site,ordinal,invocation,high:0,low:9_000_000+n as u64,reserved:0};
    match if n==clock.corrupt_at {clock.corrupt} else {0} {
        1=>reply.abi=2,2=>reply.status=0,3=>reply.site=site.wrapping_add(1),
        4=>reply.ordinal=ordinal.wrapping_add(1),5=>reply.invocation=invocation^1,
        6=>reply.reserved=1,7=>{reply.high=i64::MAX;reply.low=u64::MAX;},_=>{},
    }
    unsafe{ptr::write(out,reply)};1
}
#[derive(Clone,Copy)]
struct Args {
    pointers:[usize;9],counts:[u32;5],cb:Option<Callback>,context:*mut c_void,
}
impl Args {
    fn new(req:&RawOwnerClockedEventRequest,h:&Header,v:&[Atom;179],out:&mut Output,clock:&mut Clock)->Self {
        Self {pointers:[req as *const _ as usize,h as *const _ as usize,v.as_ptr() as usize,
            &mut out.header as *mut _ as usize,out.atoms.as_mut_ptr() as usize,
            &mut out.metadata as *mut _ as usize,out.edits.as_mut_ptr() as usize,
            out.times.as_mut_ptr() as usize,out.reads.as_mut_ptr() as usize],
            counts:[179,179,13,13,15],cb:Some(callback),context:(clock as *mut Clock).cast()}
    }
    unsafe fn run(self)->u32 {unsafe {event(
        self.pointers[0] as *const RawOwnerClockedEventRequest,self.pointers[1] as *const Header,
        self.pointers[2] as *const Atom,self.counts[0],self.cb,self.context,
        self.pointers[3] as *mut Header,self.pointers[4] as *mut Atom,self.counts[1],
        self.pointers[5] as *mut Metadata,self.pointers[6] as *mut Edit,self.counts[2],
        self.pointers[7] as *mut Time,self.counts[3],self.pointers[8] as *mut Reply,self.counts[4])}}
}
fn call(v:&[Atom;179],req:&RawOwnerClockedEventRequest,clock:&mut Clock)->(u32,Output,[Vec<u8>;6]) {
    let input_before=bytes(v);let request_before=bytes(core::slice::from_ref(req));let h=OWNER;
    let mut out=Output::sentinel();let before=out.bytes();
    let status=unsafe {Args::new(req,&h,v,&mut out,clock).run()};
    assert_eq!(bytes(v),input_before);assert_eq!(bytes(core::slice::from_ref(req)),request_before);
    assert_eq!(h,OWNER);(status,out,before)
}
fn deny(v:&[Atom;179],req:&RawOwnerClockedEventRequest,mutate:impl FnOnce(&mut Args)) {
    let h=OWNER;let mut out=Output::sentinel();let before=out.bytes();
    let input_before=bytes(v);let req_before=bytes(core::slice::from_ref(req));let mut clock=Clock::new(&[]);
    let mut args=Args::new(req,&h,v,&mut out,&mut clock);mutate(&mut args);
    assert_eq!(unsafe {args.run()},2);assert_eq!(out.bytes(),before,"all six output byte sentinels");
    assert!(clock.seen.is_empty());assert_eq!(bytes(v),input_before);
    assert_eq!(bytes(core::slice::from_ref(req)),req_before);assert_eq!(h,OWNER);
}
fn success(v:&[Atom;179],req:&RawOwnerClockedEventRequest,want:&[Atom;179],clear:&[usize],plan:&[u32],route:u32) {
    let mut clock=Clock::new(plan);let(status,out,_)=call(v,req,&mut clock);
    assert_eq!(status,1);assert!(!clock.mismatch);assert_eq!(clock.seen,plan);
    assert_eq!(out.header,RESULT);assert_eq!(out.atoms,*want,"all179 literal successor atoms");
    assert_eq!(out.metadata,Metadata{abi:1,operation:req.operation,
        scope:if req.operation==202 {1} else {2},read_count:plan.len() as u32,
        invocation:INVOCATION,revision:want[168].low,peer_present:want[3].present,
        peer:if want[3].present==1 {want[3].low} else {0},route,
        queue_fault:want[41].low as u32,rtt_fault:want[89].low as u32,..Metadata::default()});
    let owned=mask(req.operation,req.flag==1);
    for i in 0..13 {
        let has_slot=owned&(1<<i)!=0;assert!(!clear.contains(&i)||has_slot);
        assert_eq!(out.edits[i],if has_slot {Edit{action:if clear.contains(&i){2}else{1},..Edit::default()}} else {Edit::default()},
            "manual owned/clear witness slot {i}");
        let coordinate=if has_slot {let atom=want[TIME_ATOMS[i].unwrap()];
            Time{present:atom.present,reserved:0,high:atom.high,low:atom.low}} else {Time::default()};
        assert_eq!(out.times[i],coordinate,"manual coordinate slot {i}");
    }
    for i in 0..15 {
        assert_eq!(out.reads[i],if i<plan.len() {Reply{abi:1,status:1,site:plan[i],
            ordinal:i as u32,invocation:INVOCATION,high:0,low:9_000_000+i as u64,reserved:0}} else {Reply::default()},
            "exact correlated transcript including zero tail {i}");
    }
}
fn rich_success(operation:u32) {
    let(req,want,clear,plan,route)=literal_case(operation);
    success(&RICH,&req,&want,&clear,&plan,route);
}

#[test]
fn product_owner_clocked_public_request_and_reused_pod_layouts_are_exact() {
    assert_eq!((size_of::<RawOwnerClockedEventRequest>(),align_of::<RawOwnerClockedEventRequest>()),(48,8));
    assert_eq!([offset_of!(RawOwnerClockedEventRequest,abi),offset_of!(RawOwnerClockedEventRequest,operation),
        offset_of!(RawOwnerClockedEventRequest,generation),offset_of!(RawOwnerClockedEventRequest,invocation),
        offset_of!(RawOwnerClockedEventRequest,show),offset_of!(RawOwnerClockedEventRequest,minimum),
        offset_of!(RawOwnerClockedEventRequest,flag),offset_of!(RawOwnerClockedEventRequest,minimum_present)],
        [0,4,8,16,24,32,40,44]);
    assert_eq!((size_of::<Header>(),align_of::<Header>()),(16,4));
    assert_eq!((size_of::<Atom>(),align_of::<Atom>()),(24,8));
    assert_eq!((size_of::<Edit>(),align_of::<Edit>()),(32,8));
    assert_eq!((size_of::<Time>(),align_of::<Time>()),(24,8));
    assert_eq!((size_of::<Reply>(),align_of::<Reply>()),(48,8));
    assert_eq!((size_of::<Metadata>(),align_of::<Metadata>()),(72,8));
}
#[test] fn product_owner_clocked_202_initial_stop_retains_revision_and_full_owner_tail() {rich_success(202);}
#[test] fn product_owner_clocked_212_route_invalidation_advances_and_clears_evidence_not_fast_applied() {rich_success(212);}
#[test] fn product_owner_clocked_213_end_show_and_advance_preserves_original_cut() {rich_success(213);}
#[test] fn product_owner_clocked_214_same_peer_reserve_wraps_once_and_retains_route() {rich_success(214);}
#[test] fn product_owner_clocked_215_hide_health_revocation_does_not_advance() {rich_success(215);}
#[test] fn product_owner_clocked_216_post_resume_epoch_retains_fast_applied_and_uses_minimum() {rich_success(216);}
#[test] fn product_owner_clocked_217_resume_accepted_retains_existing_restoration_tuple() {rich_success(217);}
#[test] fn product_owner_clocked_218_failure_restores_exact_backoff_and_advances() {rich_success(218);}

#[test]
fn product_owner_clocked_214_new_peer_binds_before_zero_show_guard_and_hide_is_distinct() {
    for (generation,show) in [(0,0),(u64::MAX,0),(0,u64::MAX)] {
        let mut req=request(214);req.generation=generation;req.show=show;req.flag=1;
        let mut want=RICH;let mut clear=vec![];no_startup(&mut want);clear.push(5);
        put(&mut want,3,generation);put(&mut want,4,7);put(&mut want,144,0);reset_path(&mut want,&mut clear);
        absent(&mut want,&[143,152,157,161,162,163,150,149]);
        zero(&mut want,&[153,154,155,156,29,30,31]);no_witness(&mut want);clear.extend([3,4]);
        if show>0 {end_show(&mut want,&mut clear);put(&mut want,152,show);put(&mut want,153,1);}
        put(&mut want,168,0);
        success(&RICH,&req,&want,&clear,&[2,0,1,0,1],1);
    }
    let mut want=RICH;let mut clear=vec![];end_show(&mut want,&mut clear);put(&mut want,168,0);
    success(&RICH,&request(214),&want,&clear,&[2],0);
}
#[test]
fn product_owner_clocked_lazy_guard_and_healthy_rtt_preserve_original_read_sites() {
    let mut current=RICH;none(&mut current,20);let mut want=current;let mut clear=vec![];
    end_show(&mut want,&mut clear);success(&current,&request(202),&want,&clear,&[],0);
    let mut req=request(214);req.flag=1;req.generation=10003;req.show=0;let mut want=RICH;
    put(&mut want,168,0);success(&RICH,&req,&want,&[],&[],0);
    // Constructor/encoder make INPUT only. Expectations remain literal transport edits.
    let wire=codec::encode_owner_snapshot(Owner::new(50_000_000,60,Dependencies::default())).unwrap();
    let mut current:[Atom;179]=wire.atoms.try_into().unwrap();
    put(&mut current,3,77);put(&mut current,168,u64::MAX);put(&mut current,169,1);
    put(&mut current,170,1);put(&mut current,171,123);put(&mut current,172,300);
    put(&mut current,48,1);put(&mut current,47,1);put(&mut current,50,1);
    let mut want=current;put(&mut want,47,0);put(&mut want,46,6);put(&mut want,50,0);
    success(&current,&request(215),&want,&[5,3],&[0,1],0);
}
#[test]
fn product_owner_clocked_optional_minimum_wrap_and_healthy_queue_are_literal() {
    for minimum in [None,Some(0),Some(10171),Some(10172),Some(u64::MAX)] {
        let mut req=request(216);let mut want=RICH;let mut clear=vec![];
        reset_incomplete(&mut want,&mut clear);absent(&mut want,&[170,171]);clear.push(12);put(&mut want,168,0);
        match minimum {None=>none(&mut want,172),Some(value)=>{
            req.minimum_present=1;req.minimum=value;put(&mut want,172,value.max(10172));}}
        success(&RICH,&req,&want,&clear,&[2],0);
    }
    for operation in [216,218] {
        let mut current=RICH;put(&mut current,41,0);put(&mut current,38,123);
        let mut want=current;let mut clear=vec![];
        let req=if operation==216 {reset_incomplete(&mut want,&mut clear);
            absent(&mut want,&[170,171,172]);clear.push(12);request(216)}
            else {resume_failed(&mut want,&mut clear);request(218)};
        put(&mut want,168,0);success(&current,&req,&want,&clear,&[2],0);
    }
}
#[test]
fn product_owner_clocked_every_lazy_callback_failure_refuses_whole_tuple() {
    for operation in OPERATIONS {
        let(req,_,_,plan,_)=literal_case(operation);
        for failed in 0..plan.len() {for returned in [0,2,u32::MAX] {
            let mut clock=Clock::new(&plan);clock.fail=failed;clock.failure_return=returned;
            let(status,out,before)=call(&RICH,&req,&mut clock);
            assert_eq!(status,3);assert_eq!(out.bytes(),before);
            assert_eq!(clock.seen,&plan[..=failed]);assert!(!clock.mismatch);
        }}
    }
    let mut req=request(214);req.flag=1;req.generation=0;req.show=0;let plan=[2,0,1,0,1];
    for failed in 0..plan.len() {for returned in [0,2,u32::MAX] {
        let mut clock=Clock::new(&plan);clock.fail=failed;clock.failure_return=returned;
        let(status,out,before)=call(&RICH,&req,&mut clock);
        assert_eq!(status,3);assert_eq!(out.bytes(),before);assert_eq!(clock.seen,&plan[..=failed]);assert!(!clock.mismatch);
    }}
}
#[test]
fn product_owner_clocked_reply_correlation_and_native_range_refuse_each_read() {
    let(req,_,_,plan,_)=literal_case(212);
    for corruption in 1..=7 {for failed in 0..plan.len() {
        let mut clock=Clock::new(&plan);clock.corrupt=corruption;clock.corrupt_at=failed;
        let(status,out,before)=call(&RICH,&req,&mut clock);
        assert_eq!(status,if corruption==7 {2} else {4});assert_eq!(out.bytes(),before);
        assert_eq!(clock.seen,&plan[..=failed]);assert!(!clock.mismatch);
    }}
}
#[test]
fn product_owner_clocked_policy_only_vote_is_closed_before_decode_or_provider() {
    // Valid owner and request distinguish the public operation vote from the
    // later raw pointer/shape refusal. Private policy201 needs no observed input.
    deny(&RICH,&request(201),|_|{});
    for operation in [0,1,105,109,200,201,203,204,205,206,207,208,209,210,211,219,u32::MAX] {
        deny(&RICH,&request(operation),|args|{args.pointers[1]=0;args.pointers[2]=0;});
    }
}
#[test]
fn product_owner_clocked_all179_malformed_atoms_and_headers_precede_lazy_guards() {
    let mut req=request(214);req.flag=1;req.generation=10003;req.show=0;
    for index in 0..179 {for field in 0..3 {
        let mut current=RICH;match field {
            0=>current[index].kind=99,1=>current[index].present=2,
            _=>if current[index].kind==10 {current[index].high=i64::MAX;current[index].low=u64::MAX;}
                else {current[index].high=1;},
        }
        deny(&current,&req,|_|{});
    }}
    for h in [RESULT,Header{abi:2,..OWNER},Header{domain:1,..OWNER},Header{count:178,..OWNER}] {
        deny(&RICH,&req,|args|args.pointers[1]=&h as *const Header as usize);
    }
}
#[test]
fn product_owner_clocked_request_payload_null_callback_and_all_counts_are_closed() {
    for operation in OPERATIONS {
        deny(&RICH,&request(operation),|args|args.cb=None);
        let mut req=request(operation);req.abi=2;deny(&RICH,&req,|_|{});
        req=request(operation);req.invocation=0;deny(&RICH,&req,|_|{});
        for position in 0..5 {for count in [0,1,u32::MAX] {
            deny(&RICH,&request(operation),|args|args.counts[position]=count);
        }}
        for position in 0..5 {for delta in [-1i64,1] {
            deny(&RICH,&request(operation),|args|args.counts[position]=(args.counts[position] as i64+delta) as u32);
        }}
    }
    for (op,generation,show,flag,minimum,present) in [
        (202,1,0,0,0,0),(202,0,1,0,0,0),(202,0,0,1,0,0),
        (202,0,0,0,1,0),(202,0,0,0,0,1),(214,0,0,2,0,0),
        (214,1,0,0,0,0),(214,0,1,0,0,0),(216,0,0,0,1,0),(216,0,0,0,0,2),
    ] {
        let mut req=request(op);req.generation=generation;req.show=show;req.flag=flag;
        req.minimum=minimum;req.minimum_present=present;deny(&RICH,&req,|_|{});
    }
}
#[test]
fn product_owner_clocked_null_alignment_and_every_output_alias_preserve_sentinels() {
    for bad in 0..9 {for offset in [0usize,1] {
        deny(&RICH,&request(212),|args|args.pointers[bad]=if offset==0 {0} else {args.pointers[bad]+1});
    }}
    for target in 3..9 {for alias in 0..target {
        deny(&RICH,&request(212),|args|args.pointers[target]=args.pointers[alias]);
    }}
}
