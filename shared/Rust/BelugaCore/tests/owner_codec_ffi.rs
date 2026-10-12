use beluga_core::network_adaptation_candidate::*;
use beluga_core::network_adaptation_candidate::state_codec::*;
use beluga_core::native_owner_codec::*;
use beluga_core::native_clock_assay::{Time,Edit,Reply,Metadata};
use core::ffi::c_void;
use std::ptr;
#[derive(Default)]
struct Cuts{calls:Vec<(u32,u32)>,fail:Option<u32>,fault:u32}
unsafe extern "C" fn callback(ctx:*mut c_void,invocation:u64,site:u32,ordinal:u32,out:*mut Reply)->u32{
    let c=unsafe{&mut*(ctx as *mut Cuts)};c.calls.push((site,ordinal));
    if c.fail==Some(ordinal){return 0;}
    let mut reply=Reply{abi:1,status:1,site,ordinal,invocation,high:0,low:ordinal as u64+10,reserved:0};
    match c.fault{1=>reply.site=(site+1)%5,2=>reply.ordinal+=1,3=>reply.invocation^=1,
        4=>reply.reserved=1,5=>reply.status=2,6=>{reply.high=i64::MAX;reply.low=u64::MAX;},_=>{}}
    unsafe{*out=reply};1
}
fn seed()->Wire{
    let mut v=Owner::new(1_000_000,1000,Dependencies::default());
    v.policy.peer=Some(1);v.revision=u64::MAX;v.fast_statistics_available=true;
    v.evidence_lane=Some(EvidenceLane::FastSender);v.last_evidence=Some(0);v.freshness.minimum=Some(u64::MAX);
    v.applied=Some(Recommendation{tier:Tier::Full,maximum_video:i64::MAX,maximum_total:i64::MIN,
        fps:i64::MAX,scale:Scalar(0x8000_0000_0000_0000)});
    v.policy.queue.low_observation=Some(1);v.policy.queue.soft_observation=Some(2);
    v.policy.rtt.last_advancement=Some(3);v.policy.rtt.raw.advancement_present=0;
    encode_owner_snapshot(v).unwrap()
}
fn bytes<T>(value:&T)->Vec<u8>{
    // All callers below use initialized C PODs without padding.
    unsafe{std::slice::from_raw_parts(value as *const T as *const u8,std::mem::size_of::<T>()).to_vec()}
}
struct Output{h:Header,a:[Atom;OWNER_COUNT],m:Metadata,e:[Edit;13],t:[Time;13],r:[Reply;15]}
impl Output{
    fn new()->Self{Self{h:Header{abi:777,domain:777,phase:777,count:777},
        a:[Atom{kind:777,present:777,high:777,low:777};OWNER_COUNT],
        m:Metadata{abi:777,revision:888,..Metadata::default()},
        e:[Edit{action:777,source:3,index:4,ordinal:5,high:6,low:7};13],
        t:[Time{present:777,reserved:9,high:10,low:11};13],
        r:[Reply{abi:777,status:2,site:3,ordinal:4,invocation:5,high:6,low:7,reserved:8};15]}}
    fn bytes(&self)->Vec<Vec<u8>>{vec![bytes(&self.h),bytes(&self.a),bytes(&self.m),bytes(&self.e),bytes(&self.t),bytes(&self.r)]}
}
fn req()->BindRequest{BindRequest{abi:1,operation:2,generation:2,invocation:9}}
fn run(w:&Wire,q:&BindRequest,c:&mut Cuts,o:&mut Output)->u32{
    unsafe{beluga_private_owner_bind(q,&w.header,w.atoms.as_ptr(),w.atoms.len() as u32,Some(callback),c as *mut _ as *mut c_void,
        &mut o.h,o.a.as_mut_ptr(),&mut o.m,o.e.as_mut_ptr(),o.t.as_mut_ptr(),o.r.as_mut_ptr())}
}
#[test]
fn full_raw_denials_before_any_callback_preserve_all_six_buffers(){
    let base=seed();
    for i in 0..OWNER_COUNT{
        for what in 0..3{
            let mut w=base.clone();
            match what{0=>w.atoms[i].kind=99,1=>w.atoms[i].present=2,_=>{if w.atoms[i].kind==10{continue;}w.atoms[i].high=1;}}
            let mut o=Output::new();let before=o.bytes();let mut c=Cuts::default();
            assert_eq!(run(&w,&req(),&mut c,&mut o),2,"raw field {i}/{what}");
            assert!(c.calls.is_empty());assert_eq!(o.bytes(),before);assert_eq!(base,seed());
        }
    }
}
#[test]
fn full_raw_each_callback_fault_or_denial_stops_immediately_without_publication(){
    let w=seed();let sites=[2,0,1,0,1];
    for at in 0..5{
        let mut c=Cuts{fail:Some(at),..Cuts::default()};let mut o=Output::new();let before=o.bytes();
        assert_eq!(run(&w,&req(),&mut c,&mut o),3);assert_eq!(o.bytes(),before);
        assert_eq!(c.calls,sites[..=at as usize].iter().enumerate().map(|(i,s)|(*s,i as u32)).collect::<Vec<_>>());
    }
    for fault in 1..=6{
        let mut c=Cuts{fault,..Cuts::default()};let mut o=Output::new();let before=o.bytes();
        assert_eq!(run(&w,&req(),&mut c,&mut o),if fault==6{2}else{4});
        assert_eq!(o.bytes(),before);assert_eq!(c.calls,vec![(2,0)]);
    }
}
#[test]
fn full_raw_success_matches_existing_complete_typed_method_and_journals(){
    let w=seed();let mut typed=decode_owner_snapshot(w.header,&w.atoms).unwrap();
    struct Clock{n:usize}impl ClockFacts for Clock{
        fn cut(&mut self,_:ClockSite)->i128{self.n+=1;self.n as i128+9}
        fn last_time_source(&self)->TimeSource{TimeSource::Untracked}
    }
    // Numeric comparison only; original API clock has deliberately untracked journal.
    let mut clock=Clock{n:0};assert_eq!(typed.bind_native_peer(2,&mut clock,Dependencies::default()),RouteAction::Clear);
    typed.begin_time_assignment_frame();let expected=encode_owner_snapshot(typed).unwrap();
    let mut o=Output::new();let mut c=Cuts::default();assert_eq!(run(&w,&req(),&mut c,&mut o),1);
    let mut result_header=o.h;assert_eq!(result_header.phase,RESULT);result_header.phase=SNAPSHOT;
    assert_eq!(result_header,expected.header);assert_eq!(o.a.as_slice(),expected.atoms.as_slice());
    assert_eq!(o.m.read_count,5);assert_eq!(o.m.revision,0);assert_eq!(o.m.scope,2);
    assert_eq!(o.e[12].action,2);for e in &o.e[9..12]{assert_eq!(*e,Edit::default());}
    assert_eq!(unsafe{beluga_private_state_validate(&o.h,o.a.as_ptr(),OWNER_COUNT as u32)},1);
    assert!(decode_owner_snapshot(o.h,&o.a).is_err(),"phase cannot lose result journal");
}
#[test]
fn full_raw_null_misaligned_overlap_and_wrong_counts_are_denied_in_real_allocations(){
    let w=seed();let q=req();
    for mode in 0..9{
        let mut o=Output::new();let before=o.bytes();let mut c=Cuts::default();
        let mut slab=[0u64;600];let slab_before=bytes(&slab);
        let hp=&w.header as *const Header;
        let status=unsafe{
            let ap=if mode==0{ptr::null()}else if mode==1{slab.as_mut_ptr().cast::<u8>().add(1).cast::<Atom>()}else{w.atoms.as_ptr()};
            let ohp=if mode==2{hp as *mut Header}else{&mut o.h};
            let outap=if mode==3{w.atoms.as_ptr() as *mut Atom}else{o.a.as_mut_ptr()};
            let mp=if mode==4{ptr::null_mut()}else if mode==5{o.a.as_mut_ptr().cast::<Metadata>()}else{&mut o.m};
            let ep=if mode==6{o.t.as_mut_ptr().cast::<Edit>()}else{o.e.as_mut_ptr()};
            beluga_private_owner_bind(if mode==7{ptr::null()}else{&q},hp,ap,
                if mode==8{178}else{179},Some(callback),&mut c as *mut _ as *mut c_void,ohp,outap,mp,ep,o.t.as_mut_ptr(),o.r.as_mut_ptr())
        };
        assert_eq!(status,2,"pointer mode {mode}");assert!(c.calls.is_empty());assert_eq!(o.bytes(),before);
        assert_eq!(bytes(&slab),slab_before);assert_eq!(w,seed());
    }
}
#[test]
fn full_raw_header_and_request_and_final_field_validate_before_callback(){
    let base=seed();
    for mode in 0..10{
        let mut w=base.clone();let mut q=req();
        match mode{0=>w.header.abi=2,1=>w.header.domain=1,2=>w.header.phase=RESULT,3=>w.header.count=178,
            4=>q.abi=2,5=>q.operation=3,6=>q.invocation=0,7=>{w.atoms[178].present=0;w.atoms[178].low=1;},
            8=>w.atoms[174].low=8,_=>w.atoms[174].present=0}
        let mut o=Output::new();let before=o.bytes();let mut c=Cuts::default();
        assert_eq!(run(&w,&q,&mut c,&mut o),2,"mode {mode}");assert_eq!(o.bytes(),before);assert!(c.calls.is_empty());
    }
}
#[test]
fn full_raw_roundtrip_is_lossless_and_validators_do_not_publish_mutations(){
    let w=seed();let mut o=Output::new();
    assert_eq!(unsafe{beluga_private_state_roundtrip(&w.header,w.atoms.as_ptr(),179,&mut o.h,o.a.as_mut_ptr())},1);
    assert_eq!(o.h,w.header);assert_eq!(o.a.as_slice(),w.atoms.as_slice());
    for n in [0,5,178,180,u32::MAX]{
        let mut o=Output::new();let before=o.bytes();
        assert_eq!(unsafe{beluga_private_state_roundtrip(&w.header,w.atoms.as_ptr(),n,&mut o.h,o.a.as_mut_ptr())},2);
        assert_eq!(o.bytes(),before);
    }
}

