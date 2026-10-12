//! Independent synthetic full-state event-boundary regressions. These literals are
//! transport fixtures, not captured native actors, coherent RTT telemetry, or effect
//! authority. No expected successor is computed by a reducer or production encoder.
use beluga_core::native_clock_assay::{Edit, Metadata, Reply, Time};
use beluga_core::native_owner_events::{beluga_private_owner_event, EventRequest};
use beluga_core::network_adaptation_candidate::state_codec::{Atom, Header};
use core::{mem::{align_of, offset_of, size_of}, ptr};

const fn a(kind:u32,present:u32,high:i64,low:u64)->Atom{Atom{kind,present,high,low}}
const CURRENT:[Atom;179]=[
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
    a(2,1,0,1065),a(2,1,0,1066),
    a(1,1,0,10067),a(1,1,0,10068),a(1,1,0,10069),a(1,1,0,10070),
    a(1,1,0,10071),a(1,1,0,10072),a(1,1,0,10073),a(1,1,0,10074),
    a(3,1,0,0x7ff8_0000_0000_004b),a(1,1,0,10076),
    a(1,1,0,10077),a(1,1,0,10078),a(1,1,0,10079),a(1,1,0,10080),
    a(1,1,0,10081),a(1,1,0,10082),a(1,1,0,10083),a(1,1,0,10084),
    a(3,1,0,0x7ff8_0000_0000_0055),a(1,1,0,10086),a(3,1,0,0x7ff8_0000_0000_0057),
    a(10,1,0,1000088),a(4,1,0,0),a(6,1,0,20090),
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
    a(1,1,0,10168),a(4,1,0,1),a(8,1,0,1),a(10,1,0,1000171),a(1,1,0,10172),
    a(4,1,0,1),a(7,1,0,2),a(2,1,0,1175),a(2,1,0,1176),a(2,1,0,1177),a(3,1,0,0x7ff8_0000_0000_00b2),
];
const OWNER_HEADER:Header=Header{abi:1,domain:2,phase:1,count:179};
const POLICY_HEADER:Header=Header{abi:1,domain:1,phase:1,count:168};
const RESULT_HEADER:Header=Header{abi:1,domain:2,phase:2,count:179};
const TIME_ATOMS:[Option<usize>;13]=[Some(12),Some(23),Some(28),Some(159),Some(163),Some(167),
    Some(39),Some(40),Some(88),None,None,None,Some(171)];

fn request(operation:u32)->EventRequest{EventRequest{abi:1,operation,generation:0,invocation:0xfedc_ba98_7654_3210,
    show:0,capture_source_present:0,resume_context_absent:0}}
fn none(atoms:&mut [Atom],index:usize){atoms[index]=a(atoms[index].kind,0,0,0);}
fn put(atoms:&mut [Atom],index:usize,value:u64){atoms[index]=a(atoms[index].kind,1,0,value);}
fn opt(atoms:&mut [Atom],index:usize,value:Option<u64>){match value{Some(v)=>put(atoms,index,v),None=>none(atoms,index)}}
fn no_witness(atoms:&mut [Atom]){put(atoms,158,0);none(atoms,159);none(atoms,160);}
fn no_resume(atoms:&mut [Atom]){put(atoms,16,0);for index in [17,18,19]{none(atoms,index);}
    put(atoms,25,0);for index in [26,27,28]{none(atoms,index);}}
fn attempt_expected(current:[Atom;179])->[Atom;179]{let mut expected=current;put(&mut expected,155,1);no_witness(&mut expected);expected}
fn stop_expected(current:[Atom;179],revision:u64)->[Atom;179]{let mut expected=current;put(&mut expected,168,revision);
    put(&mut expected,169,0);for index in [170,171,172]{none(&mut expected,index);}expected}

// Closed independent field-index ledger. This creates adversarial observed input,
// not an expected result, and never calls a constructor, codec or event implementation.
// Identity fields alone are reset by individual tests to their intended guard values.
fn different_observed()->[Atom;168]{
    let mut observed:[Atom;168]=CURRENT[..168].try_into().unwrap();
    for index in [0,1,2,5,6,7,8,9,10,11,13,14,18,19,24,27,29,30,31,38,65,66,
        91,92,93,94,96,97,98,99,100,102,103,104,105,106,108,109,110,111,112,114,
        115,116,117,118,120,121,122,123,124,126,127,128,129,130,132,133,134,135,136,138,142]{
        observed[index]=a(2,1,0,50_000+index as u64);
    }
    for index in [3,36,67,68,69,70,71,72,73,74,76,77,78,79,80,81,82,83,84,86,143,146,150,152,161,164,165]{
        observed[index]=a(1,1,0,80_000+index as u64);
    }
    for index in [35,37,60,61,62,63,64,75,85,87,95,101,107,113,119,125,131,137,147,148,149,157,160,162]{
        observed[index]=a(3,1,0,0xfff8_1234_0000_0000+index as u64);
    }
    for index in [12,23,28,39,40,88,159,163,167]{observed[index]=a(10,1,0,9_000_000+index as u64);}
    for index in 42..=59{observed[index]=a(6,1,0,0x8000_0000+index as u64);}
    observed[90]=a(6,1,0,0x8000_005a);observed[139]=a(5,1,0,252);observed[141]=a(5,1,0,253);
    for (index,value) in [(4,0),(20,7),(21,2),(22,3),(26,6)]{observed[index]=a(7,1,0,value);}
    for (index,value) in [(15,0),(17,1),(32,1),(33,0),(34,1),(41,0),(89,1),(140,0),(144,1),
        (151,0),(153,1),(154,0),(155,1),(156,0),(166,1)]{observed[index]=a(4,1,0,value);}
    observed
}
fn admitted_attempt(current:&[Atom;179])->[Atom;168]{let mut observed=different_observed();
    observed[3]=current[3];observed[152]=current[152];put(&mut observed,155,1);observed}
fn startup_current()->[Atom;179]{let mut current=CURRENT;current[164]=current[3];current[165]=current[152];
    put(&mut current,166,0);current}
fn admitted_startup(current:&[Atom;179])->[Atom;168]{let mut observed=different_observed();
    for index in [3,152,164,165]{observed[index]=current[index];}put(&mut observed,166,1);observed}

#[derive(Clone,Debug)]
struct Output{header:Header,atoms:[Atom;179],metadata:Metadata,edits:[Edit;13],times:[Time;13],reads:[Reply;15]}
impl Output{
    fn sentinel()->Self{Self{
        header:Header{abi:0xa1,domain:0xa2,phase:0xa3,count:0xa4},
        atoms:[a(777,778,-779,780);179],
        metadata:Metadata{abi:801,operation:802,scope:803,read_count:804,invocation:805,revision:806,peer:807,
            peer_present:808,bound:809,route:810,sample:811,enabled:812,lease:813,queue_fault:814,rtt_fault:815},
        edits:[Edit{action:901,source:902,index:903,ordinal:904,high:-905,low:906};13],
        times:[Time{present:1001,reserved:1002,high:-1003,low:1004};13],
        reads:[Reply{abi:1101,status:1102,site:1103,ordinal:1104,invocation:1105,high:-1106,low:1107,reserved:1108};15],
    }}
    fn buffers(&self)->[Vec<u8>;6]{[bytes(core::slice::from_ref(&self.header)),bytes(&self.atoms),
        bytes(core::slice::from_ref(&self.metadata)),bytes(&self.edits),bytes(&self.times),bytes(&self.reads)]}
}
// Each used repr(C) POD has no padding: the literal layout assertions below cover
// every member and total extent. No bytes of the non-repr(C) Output are inspected.
fn bytes<T:Copy>(values:&[T])->Vec<u8>{unsafe{core::slice::from_raw_parts(values.as_ptr().cast::<u8>(),
    core::mem::size_of_val(values)).to_vec()}}
unsafe fn raw_call(req:*const EventRequest,header:*const Header,current:*const Atom,count:u32,
    observed_header:*const Header,observed:*const Atom,observed_count:u32)->(u32,Output,[Vec<u8>;6]){
    let mut output=Output::sentinel();let before=output.buffers();
    let status=unsafe{beluga_private_owner_event(req,header,current,count,observed_header,observed,observed_count,
        &mut output.header,output.atoms.as_mut_ptr(),&mut output.metadata,output.edits.as_mut_ptr(),
        output.times.as_mut_ptr(),output.reads.as_mut_ptr())};
    (status,output,before)
}
fn call(current:&[Atom;179],req:&EventRequest,observed:Option<&[Atom;168]>)->(u32,Output){
    let h=OWNER_HEADER;let oh=POLICY_HEADER;
    let current_before=bytes(current);let request_before=bytes(core::slice::from_ref(req));
    let header_before=bytes(core::slice::from_ref(&h));let observed_before=observed.map(|a|bytes(a));
    let (status,output,_)=unsafe{raw_call(req,&h,current.as_ptr(),179,
        if observed.is_some(){&oh}else{ptr::null()},observed.map_or(ptr::null(),|a|a.as_ptr()),
        if observed.is_some(){168}else{0})};
    assert_eq!(bytes(current),current_before,"borrowed current snapshot modified");
    assert_eq!(bytes(core::slice::from_ref(req)),request_before,"request modified");
    assert_eq!(bytes(core::slice::from_ref(&h)),header_before,"current header modified");
    assert_eq!(observed.map(|a|bytes(a)),observed_before,"borrowed observed snapshot modified");
    assert_eq!(oh,POLICY_HEADER,"observed header modified");
    (status,output)
}
fn success(current:&[Atom;179],req:&EventRequest,observed:Option<&[Atom;168]>,expected:&[Atom;179],
    clear_slot:Option<usize>,enabled:u32,label:&str)->Output{
    let (status,output)=call(current,req,observed);assert_eq!(status,1,"{label}: accepted");
    assert_eq!(output.header,RESULT_HEADER,"{label}: exact result header");
    assert_eq!(output.atoms,*expected,"{label}: ALL179 literal semantic atoms");
    let scope=if req.operation<=104{1}else{2};
    let metadata=Metadata{abi:1,operation:req.operation,scope,read_count:0,invocation:req.invocation,
        revision:expected[168].low,peer:if expected[3].present==1{expected[3].low}else{0},
        peer_present:expected[3].present,bound:0,route:0,sample:0,enabled,lease:0,
        queue_fault:expected[41].low as u32,rtt_fault:expected[89].low as u32};
    assert_eq!(output.metadata,metadata,"{label}: every metadata member");
    assert_eq!(output.reads,[Reply::default();15],"{label}: zero actual reads, every reply byte zero");
    // Event ownership is a literal operation contract, not broad Policy/Owner
    // ownership and never inferred from a returned edit. Early-return branches
    // still own their one declared slot, exposing Retain rather than raw zero.
    let declared_slot=match req.operation{102=>Some(3),103=>Some(5),104|107|108=>Some(2),105=>Some(12),
        101|106|109=>None,_=>panic!("unexpected success operation")};
    assert!(clear_slot.is_none() || clear_slot==declared_slot,"{label}: independent event mask");
    for slot in 0..13{
        let owned=declared_slot==Some(slot);
        let expected_edit=if owned{Edit{action:if clear_slot==Some(slot){2}else{1},..Edit::default()}}else{Edit::default()};
        assert_eq!(output.edits[slot],expected_edit,"{label}: exact edit slot {slot}");
        let expected_time=if owned{
            let atom=expected[TIME_ATOMS[slot].unwrap()];
            Time{present:atom.present,reserved:0,high:atom.high,low:atom.low}
        }else{Time::default()};
        assert_eq!(output.times[slot],expected_time,"{label}: exact coordinate slot {slot}");
    }
    output
}
unsafe fn denied(req:*const EventRequest,header:*const Header,current:*const Atom,count:u32,
    oh:*const Header,observed:*const Atom,observed_count:u32,label:&str){
    let(status,output,before)=unsafe{raw_call(req,header,current,count,oh,observed,observed_count)};
    assert_eq!(status,2,"{label}: ordinary closed denial");
    assert_eq!(output.buffers(),before,"{label}: all SIX output buffers byte-unchanged");
}

#[test]
fn owner_event_exact_request_and_six_output_pod_layouts(){
    assert_eq!((size_of::<EventRequest>(),align_of::<EventRequest>()),(40,8));
    assert_eq!([offset_of!(EventRequest,abi),offset_of!(EventRequest,operation),offset_of!(EventRequest,generation),
        offset_of!(EventRequest,invocation),offset_of!(EventRequest,show),offset_of!(EventRequest,capture_source_present),
        offset_of!(EventRequest,resume_context_absent)],[0,4,8,16,24,32,36]);
    assert_eq!((size_of::<Header>(),align_of::<Header>()),(16,4));
    assert_eq!([offset_of!(Header,abi),offset_of!(Header,domain),offset_of!(Header,phase),offset_of!(Header,count)],[0,4,8,12]);
    assert_eq!((size_of::<Atom>(),align_of::<Atom>()),(24,8));
    assert_eq!([offset_of!(Atom,kind),offset_of!(Atom,present),offset_of!(Atom,high),offset_of!(Atom,low)],[0,4,8,16]);
    assert_eq!((size_of::<Edit>(),align_of::<Edit>()),(32,8));
    assert_eq!([offset_of!(Edit,action),offset_of!(Edit,source),offset_of!(Edit,index),offset_of!(Edit,ordinal),
        offset_of!(Edit,high),offset_of!(Edit,low)],[0,4,8,12,16,24]);
    assert_eq!((size_of::<Time>(),align_of::<Time>()),(24,8));
    assert_eq!([offset_of!(Time,present),offset_of!(Time,reserved),offset_of!(Time,high),offset_of!(Time,low)],[0,4,8,16]);
    assert_eq!((size_of::<Reply>(),align_of::<Reply>()),(48,8));
    assert_eq!([offset_of!(Reply,abi),offset_of!(Reply,status),offset_of!(Reply,site),offset_of!(Reply,ordinal),
        offset_of!(Reply,invocation),offset_of!(Reply,high),offset_of!(Reply,low),offset_of!(Reply,reserved)],[0,4,8,12,16,24,32,40]);
    assert_eq!((size_of::<Metadata>(),align_of::<Metadata>()),(72,8));
    assert_eq!([offset_of!(Metadata,abi),offset_of!(Metadata,operation),offset_of!(Metadata,scope),offset_of!(Metadata,read_count),
        offset_of!(Metadata,invocation),offset_of!(Metadata,revision),offset_of!(Metadata,peer),offset_of!(Metadata,peer_present),
        offset_of!(Metadata,bound),offset_of!(Metadata,route),offset_of!(Metadata,sample),offset_of!(Metadata,enabled),
        offset_of!(Metadata,lease),offset_of!(Metadata,queue_fault),offset_of!(Metadata,rtt_fault)],
        [0,4,8,12,16,24,32,40,44,48,52,56,60,64,68]);
}

#[test]
fn owner_event_all_nine_operations_exact_full179_selective_successors(){
    for operation in 101..=109{
        let mut current=if operation==103{startup_current()}else{CURRENT};
        put(&mut current,168,u64::MAX);let mut req=request(operation);let mut expected=current;
        let observed;let observed_ref;let clear_slot;let enabled;
        match operation{
            101|106=>{put(&mut current,153,1);put(&mut current,154,0);expected=current;
                req.generation=10003;req.show=10152;put(&mut expected,154,1);
                if operation==106{put(&mut expected,168,0);}observed_ref=None;clear_slot=None;enabled=0;}
            102=>{observed=admitted_attempt(&current);expected=attempt_expected(current);
                put(&mut expected,161,80161); // independent larger observed sequence
                // Both input timestamp payloads are NaN: Swift keeps CURRENT's payload.
                observed_ref=Some(&observed);clear_slot=Some(3);enabled=0;}
            103=>{observed=admitted_startup(&current);put(&mut expected,166,1);none(&mut expected,167);
                observed_ref=Some(&observed);clear_slot=Some(5);enabled=0;}
            104|107|108=>{no_resume(&mut expected);if operation==108{put(&mut expected,168,0);}
                observed_ref=None;clear_slot=Some(2);enabled=0;}
            105=>{expected=stop_expected(current,0);observed_ref=None;clear_slot=Some(12);enabled=0;}
            109=>{req.capture_source_present=1;req.resume_context_absent=1;
                observed_ref=None;clear_slot=None;enabled=1;}
            _=>unreachable!(),
        }
        success(&current,&req,observed_ref,&expected,clear_slot,enabled,&format!("operation {operation}"));
    }
}

#[test]
fn owner_event_policy_activate_guards_zero_and_max_identity(){
    for (peer,show) in [(0,0),(u64::MAX,u64::MAX),(0,u64::MAX),(u64::MAX,0)]{
        let mut base=CURRENT;put(&mut base,3,peer);put(&mut base,152,show);put(&mut base,153,1);put(&mut base,154,0);
        let mut req=request(101);req.generation=peer;req.show=show;
        let mut expected=base;put(&mut expected,154,1);
        success(&base,&req,None,&expected,None,0,"exact extreme identity activates");
        for guard in 0..5{
            let mut current=base;match guard{0=>none(&mut current,3),1=>put(&mut current,3,peer.wrapping_add(1)),
                2=>none(&mut current,152),3=>put(&mut current,152,show.wrapping_add(1)),4=>put(&mut current,153,0),_=>unreachable!()}
            success(&current,&req,None,&current,None,0,&format!("activate guard {guard}"));
        }
        let mut already=base;put(&mut already,154,1);success(&already,&req,None,&already,None,0,"already active still untouched");
    }
}

#[test]
fn owner_event_owned_activate_wraps_revision_even_when_guard_rejects(){
    let mut req=request(106);req.generation=0;req.show=u64::MAX;
    for (revision,next) in [(0,1),(u64::MAX-1,u64::MAX),(u64::MAX,0)]{
        for admitted in [false,true]{
            let mut current=CURRENT;put(&mut current,168,revision);put(&mut current,3,0);put(&mut current,152,u64::MAX);
            put(&mut current,153,admitted as u64);put(&mut current,154,0);
            let mut expected=current;put(&mut expected,168,next);if admitted{put(&mut expected,154,1);}
            success(&current,&req,None,&expected,None,0,"owner activation unconditional single wrapping advance");
        }
    }
}

#[test]
fn owner_event_retain_attempt_imports_only_negative_bookkeeping(){
    for peer in [None,Some(0),Some(u64::MAX)]{
        for show in [0,u64::MAX]{for witness_present in [false,true]{
            let mut current=CURRENT;opt(&mut current,3,peer);put(&mut current,152,show);
            if !witness_present{no_witness(&mut current);}
            let mut observed=admitted_attempt(&current);none(&mut observed,161);none(&mut observed,162);
            let expected=attempt_expected(current);
            success(&current,&request(102),Some(&observed),&expected,Some(3),0,"same optional peer exact Show and no broad observed copy");
        }}
    }
}

#[test]
fn owner_event_retain_attempt_each_guard_rejects_without_clear(){
    let base=CURRENT;
    for guard in 0..6{
        let mut current=base;let mut observed=admitted_attempt(&base);
        match guard{0=>put(&mut observed,3,10004),1=>none(&mut observed,3),2=>none(&mut current,152),
            3=>put(&mut observed,152,10153),4=>none(&mut observed,152),5=>put(&mut observed,155,0),_=>unreachable!()}
        success(&current,&request(102),Some(&observed),&current,None,0,&format!("retain attempt guard {guard}"));
    }
    let mut current=base;no_witness(&mut current);let mut observed=admitted_attempt(&current);put(&mut observed,155,0);
    success(&current,&request(102),Some(&observed),&current,None,0,"rejected absent witness is owned Retain, not Clear or unowned");
}

#[test]
fn owner_event_retain_attempt_sequence_is_exact_u64_max_and_optional_zero(){
    let rows=[
        (None,None,None),(None,Some(0),Some(0)),(None,Some(u64::MAX),Some(u64::MAX)),
        (Some(0),None,Some(0)),(Some(u64::MAX),None,Some(u64::MAX)),
        (Some(0),Some(0),Some(0)),(Some(0),Some(u64::MAX),Some(u64::MAX)),
        (Some(u64::MAX),Some(0),Some(u64::MAX)),(Some(u64::MAX),Some(u64::MAX),Some(u64::MAX)),
        (Some(1),Some(2),Some(2)),(Some(2),Some(1),Some(2)),
        (Some(9_007_199_254_740_992),Some(9_007_199_254_740_993),Some(9_007_199_254_740_993)),
        (Some(9_007_199_254_740_993),Some(9_007_199_254_740_992),Some(9_007_199_254_740_993)),
    ];
    for (at,(old,new,want)) in rows.into_iter().enumerate(){
        let mut current=CURRENT;opt(&mut current,161,old);let mut observed=admitted_attempt(&current);
        opt(&mut observed,161,new);none(&mut observed,162);let mut expected=attempt_expected(current);opt(&mut expected,161,want);
        success(&current,&request(102),Some(&observed),&expected,Some(3),0,&format!("literal integer max row {at}"));
    }
}

#[test]
fn owner_event_retain_attempt_swift_max_preserves_literal_ieee_operand_bits(){
    const P0:u64=0;const N0:u64=0x8000_0000_0000_0000;
    const P1:u64=0x3ff0_0000_0000_0000;const P2:u64=0x4000_0000_0000_0000;
    const N1:u64=0xbff0_0000_0000_0000;const N2:u64=0xc000_0000_0000_0000;
    const PI:u64=0x7ff0_0000_0000_0000;const NI:u64=0xfff0_0000_0000_0000;
    const QA:u64=0x7ff8_0000_0000_0123;const QB:u64=0x7ff8_4567_89ab_cdef;
    const NQ:u64=0xfff8_0123_4567_89ab;const SA:u64=0x7ff0_0000_0000_0042;const NS:u64=0xfff0_0000_0000_0043;
    // Literal native Swift semantics: y >= x ? y : x. No .max or floating
    // operation computes these expected payloads. A None x is specifically +0.
    let rows=[
        (None,None,None),(Some(QA),None,Some(QA)),(None,Some(QA),Some(P0)),
        (None,Some(N0),Some(N0)),(None,Some(P0),Some(P0)),(None,Some(N1),Some(P0)),
        (None,Some(P1),Some(P1)),(None,Some(NI),Some(P0)),(None,Some(PI),Some(PI)),
        (Some(P0),Some(N0),Some(N0)),(Some(N0),Some(P0),Some(P0)),
        (Some(N0),Some(N0),Some(N0)),(Some(P0),Some(P0),Some(P0)),
        (Some(P1),Some(P2),Some(P2)),(Some(P2),Some(P1),Some(P2)),
        (Some(N2),Some(N1),Some(N1)),(Some(P1),Some(P1),Some(P1)),
        (Some(QA),Some(P2),Some(QA)),(Some(P2),Some(QA),Some(P2)),
        (Some(QA),Some(QB),Some(QA)),(Some(QB),Some(QA),Some(QB)),
        (Some(NQ),Some(SA),Some(NQ)),(Some(SA),Some(P1),Some(SA)),
        (Some(P1),Some(NS),Some(P1)),(None,Some(NS),Some(P0)),
        (Some(PI),Some(PI),Some(PI)),(Some(NI),Some(NI),Some(NI)),
        (Some(PI),Some(NI),Some(PI)),(Some(NI),Some(PI),Some(PI)),
        (Some(NI),Some(N1),Some(N1)),(Some(P1),Some(PI),Some(PI)),
    ];
    for (at,(old,new,want)) in rows.into_iter().enumerate(){
        let mut current=CURRENT;opt(&mut current,162,old);let mut observed=admitted_attempt(&current);
        none(&mut observed,161);opt(&mut observed,162,new);let mut expected=attempt_expected(current);opt(&mut expected,162,want);
        success(&current,&request(102),Some(&observed),&expected,Some(3),0,&format!("literal IEEE row {at}"));
    }
}

#[test]
fn owner_event_startup_terminal_copies_no_other_observed_fields(){
    for (peer,show) in [(0,0),(u64::MAX,u64::MAX),(0,u64::MAX),(u64::MAX,0)]{for sparse_present in [false,true]{
        let mut current=startup_current();for index in [3,164]{put(&mut current,index,peer);}
        for index in [152,165]{put(&mut current,index,show);}put(&mut current,153,0);put(&mut current,154,0);
        if !sparse_present{none(&mut current,167);}
        let observed=admitted_startup(&current);let mut expected=current;put(&mut expected,166,1);none(&mut expected,167);
        success(&current,&request(103),Some(&observed),&expected,Some(5),0,"startup terminal exact extreme identity only two atoms");
    }}
}

#[test]
fn owner_event_startup_terminal_all_eight_identity_and_two_terminal_guards(){
    let base=startup_current();let baseline=admitted_startup(&base);
    for observed_side in [false,true]{for index in [3,152,164,165]{for absent in [false,true]{
        let mut current=base;let mut observed=baseline;
        let target:&mut [Atom]=if observed_side{&mut observed}else{&mut current};
        if absent{none(target,index);}else{let wrong=target[index].low.wrapping_add(1);put(target,index,wrong);}
        success(&current,&request(103),Some(&observed),&current,None,0,
            &format!("terminal identity side {observed_side} index {index} absent {absent}"));
    }}}
    let mut current=base;put(&mut current,166,1);
    success(&current,&request(103),Some(&baseline),&current,None,0,"already terminal performs no new clear");
    let mut observed=baseline;put(&mut observed,166,0);
    success(&base,&request(103),Some(&observed),&base,None,0,"observed nonterminal does not clear");
    let mut current=base;none(&mut current,167);
    success(&current,&request(103),Some(&observed),&current,None,0,"rejected absent sparse time is owned Retain, not Clear or unowned");
}

#[test]
fn owner_event_policy_resume_clears_only_two_composites_even_when_absent(){
    for already_absent in [false,true]{
        let mut current=CURRENT;put(&mut current,168,u64::MAX);if already_absent{no_resume(&mut current);}
        let mut expected=current;no_resume(&mut expected);
        success(&current,&request(104),None,&expected,Some(2),0,"policy resume has no owner advance and explicit promotion Clear");
    }
}

#[test]
fn owner_event_stop_sampling_does_not_fuse_end_show_or_drop_applied(){
    for (old,next) in [(0,1),(u64::MAX-1,u64::MAX),(u64::MAX,0)]{
        for already_stopped in [false,true]{
            let mut current=CURRENT;put(&mut current,168,old);
            if already_stopped{put(&mut current,169,0);for index in [170,171,172]{none(&mut current,index);}}
            let expected=stop_expected(current,next);
            success(&current,&request(105),None,&expected,Some(12),0,"stop bookkeeping exact policy/applied retention");
        }
    }
}

#[test]
fn owner_event_two_owner_resume_stages_have_distinct_revision_contracts(){
    for (operation,next) in [(107,u64::MAX),(108,0)]{
        for already_absent in [false,true]{
            let mut current=CURRENT;put(&mut current,168,u64::MAX);if already_absent{no_resume(&mut current);}
            let mut expected=current;no_resume(&mut expected);put(&mut expected,168,next);
            success(&current,&request(operation),None,&expected,Some(2),0,"resume stage literal wrapping/no wrapping and no evidence/applied loss");
        }
    }
}

#[test]
fn owner_event_collector_gate_truth_table_never_invents_fast_availability(){
    for fast in [false,true]{for capture in [false,true]{for resume_absent in [false,true]{
        let mut current=CURRENT;put(&mut current,168,u64::MAX);put(&mut current,169,fast as u64);
        let mut req=request(109);req.capture_source_present=capture as u32;req.resume_context_absent=resume_absent as u32;
        let mut expected=current;if !capture{put(&mut expected,169,0);}
        success(&current,&req,None,&expected,None,(capture && resume_absent)as u32,"collector exact truth table and no revision/time mutation");
    }}}
}

#[test]
fn owner_event_all179_current_fields_malformed_even_on_noop_are_atomic_denials(){
    for operation in 101..=109{
        let req=request(operation);let observed=if operation==103{admitted_startup(&CURRENT)}else{admitted_attempt(&CURRENT)};
        let oh=if operation==102 || operation==103{&POLICY_HEADER}else{ptr::null()};
        let op=if operation==102 || operation==103{observed.as_ptr()}else{ptr::null()};
        let oc=if operation==102 || operation==103{168}else{0};
        for index in 0..179{
            for invalid in 0..3{
                if invalid==2 && CURRENT[index].kind==10{continue;}
                let mut current=CURRENT;
                match invalid{0=>current[index].kind=99,1=>current[index].present=2,2=>current[index].high=1,_=>unreachable!()}
                unsafe{denied(&req,&OWNER_HEADER,current.as_ptr(),179,oh,op,oc,
                    &format!("current op {operation} index {index} mutation {invalid}"));}
            }
        }
    }
}

#[test]
fn owner_event_all168_observed_fields_validated_before_rejected_identity_guard(){
    for operation in [102,103]{
        let req=request(operation);let base=different_observed(); // identities deliberately reject.
        for index in 0..168{
            for invalid in 0..3{
                if invalid==2 && base[index].kind==10{continue;}
                let mut observed=base;
                match invalid{0=>observed[index].kind=99,1=>observed[index].present=2,2=>observed[index].high=1,_=>unreachable!()}
                unsafe{denied(&req,&OWNER_HEADER,CURRENT.as_ptr(),179,&POLICY_HEADER,observed.as_ptr(),168,
                    &format!("unused observed op {operation} index {index} mutation {invalid}"));}
            }
        }
        // Absent composite tags do not grant permission for hidden children.
        for tag in [16,25,145,158]{let mut observed=base;put(&mut observed,tag,0);
            unsafe{denied(&req,&OWNER_HEADER,CURRENT.as_ptr(),179,&POLICY_HEADER,observed.as_ptr(),168,"hidden composite children denied before guard");}}
    }
}

#[test]
fn owner_event_request_and_forbidden_unused_payloads_are_closed(){
    let observed=different_observed();
    for operation in 101..=109{
        let base=request(operation);let uses_observed=operation==102 || operation==103;
        let oh=if uses_observed{&POLICY_HEADER}else{ptr::null()};
        let op=if uses_observed{observed.as_ptr()}else{ptr::null()};let oc=if uses_observed{168}else{0};
        let mut malformed=Vec::new();let mut q=base;q.abi=2;malformed.push(q);
        q=base;q.invocation=0;malformed.push(q);
        if operation!=101 && operation!=106{q=base;q.generation=1;malformed.push(q);q=base;q.show=1;malformed.push(q);}
        q=base;q.capture_source_present=if operation==109{2}else{1};malformed.push(q);
        q=base;q.resume_context_absent=if operation==109{2}else{1};malformed.push(q);
        for (at,req) in malformed.iter().enumerate(){unsafe{denied(req,&OWNER_HEADER,CURRENT.as_ptr(),179,oh,op,oc,
            &format!("unused request op {operation} row {at}"));}}
        if !uses_observed{
            unsafe{denied(&base,&OWNER_HEADER,CURRENT.as_ptr(),179,&POLICY_HEADER,observed.as_ptr(),168,"forbidden observed entire valid DTO");}
            unsafe{denied(&base,&OWNER_HEADER,CURRENT.as_ptr(),179,&POLICY_HEADER,ptr::null(),0,"forbidden observed header alone");}
            unsafe{denied(&base,&OWNER_HEADER,CURRENT.as_ptr(),179,ptr::null(),observed.as_ptr(),0,"forbidden observed atoms alone");}
            unsafe{denied(&base,&OWNER_HEADER,CURRENT.as_ptr(),179,ptr::null(),ptr::null(),168,"forbidden nonzero count alone");}
        }else{
            for (h,p,n) in [(ptr::null(),ptr::null(),0),(&POLICY_HEADER,ptr::null(),168),
                (ptr::null(),observed.as_ptr(),168),(&POLICY_HEADER,observed.as_ptr(),0),(&POLICY_HEADER,observed.as_ptr(),167),
                (&POLICY_HEADER,observed.as_ptr(),169)]{
                unsafe{denied(&base,&OWNER_HEADER,CURRENT.as_ptr(),179,h,p,n,"required exact observed DTO");}
            }
        }
    }
    for operation in [0,1,100,110,u32::MAX]{let q=request(operation);
        unsafe{denied(&q,&OWNER_HEADER,CURRENT.as_ptr(),179,ptr::null(),ptr::null(),0,"unknown operation");}}
}

#[test]
fn owner_event_input_headers_counts_result_replay_and_overlap_are_denied(){
    let req=request(104);
    for field in 0..4{let mut h=OWNER_HEADER;match field{0=>h.abi=2,1=>h.domain=1,2=>h.phase=2,3=>h.count=178,_=>unreachable!()}
        unsafe{denied(&req,&h,CURRENT.as_ptr(),179,ptr::null(),ptr::null(),0,"current header framing");}}
    for n in [0,168,178,180,u32::MAX]{unsafe{denied(&req,&OWNER_HEADER,CURRENT.as_ptr(),n,ptr::null(),ptr::null(),0,"current count framing");}}
    unsafe{denied(ptr::null(),&OWNER_HEADER,CURRENT.as_ptr(),179,ptr::null(),ptr::null(),0,"null request");}
    unsafe{denied(&req,ptr::null(),CURRENT.as_ptr(),179,ptr::null(),ptr::null(),0,"null current header");}
    unsafe{denied(&req,&OWNER_HEADER,ptr::null(),179,ptr::null(),ptr::null(),0,"null current atoms");}
    let mut expected=CURRENT;no_resume(&mut expected);
    let result=success(&CURRENT,&req,None,&expected,Some(2),0,"result replay predecessor");
    unsafe{denied(&req,&result.header,result.atoms.as_ptr(),179,ptr::null(),ptr::null(),0,"result is not a fresh snapshot");}
    for operation in [102,103]{let q=request(operation);let observed=different_observed();
        for field in 0..4{let mut h=POLICY_HEADER;match field{0=>h.abi=2,1=>h.domain=2,2=>h.phase=2,3=>h.count=169,_=>unreachable!()}
            unsafe{denied(&q,&OWNER_HEADER,CURRENT.as_ptr(),179,&h,observed.as_ptr(),168,"observed header framing");}}
        unsafe{denied(&q,&OWNER_HEADER,CURRENT.as_ptr(),179,&POLICY_HEADER,CURRENT.as_ptr(),168,"current observed borrowed ranges overlap");}
    }
    for missing in 0..6{
        let mut output=Output::sentinel();let before=output.buffers();
        let status=unsafe{beluga_private_owner_event(&req,&OWNER_HEADER,CURRENT.as_ptr(),179,ptr::null(),ptr::null(),0,
            if missing==0{ptr::null_mut()}else{&mut output.header},
            if missing==1{ptr::null_mut()}else{output.atoms.as_mut_ptr()},
            if missing==2{ptr::null_mut()}else{&mut output.metadata},
            if missing==3{ptr::null_mut()}else{output.edits.as_mut_ptr()},
            if missing==4{ptr::null_mut()}else{output.times.as_mut_ptr()},
            if missing==5{ptr::null_mut()}else{output.reads.as_mut_ptr()})};
        assert_eq!(status,2,"null output pointer {missing}");
        assert_eq!(output.buffers(),before,"null output {missing}: all SIX buffers untouched");
    }
}
