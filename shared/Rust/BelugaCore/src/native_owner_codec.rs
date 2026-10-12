//! PRIVATE full stored-state ABI assay. No native actor/application integration.
//! Caller owns valid live buffers, corresponding native route/time sidecars and effects.
//! Fresh snapshots only; results cannot be reused as entry snapshots. Output publication
//! on denial is prevented at this C boundary; partially mutated local drafts are discarded.
//! Successful writes are not concurrent atomic memory publication across buffers.
//! Callbacks/concurrent threads must not mutate/free any borrowed input/output objects.
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Reply, Metadata, Callback, NativeClock, encode_edit, range};
use core::{ffi::c_void, ptr};
#[repr(C)]
#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub struct BindRequest {pub abi:u32,pub operation:u32,pub generation:u64,pub invocation:u64}
pub(crate) fn disjoint(ranges:&[Option<(usize,usize)>])->bool {
    if ranges.iter().any(Option::is_none){return false;}
    for i in 0..ranges.len(){for j in i+1..ranges.len(){
        let (a,b)=ranges[i].unwrap();let(c,d)=ranges[j].unwrap();
        if a<d && c<b{return false;}
    }}true
}
fn input(h:codec::Header,a:&[codec::Atom])->Result<codec::Wire,u32>{
    let w=match h.domain{
        codec::POLICY=>codec::encode_policy_snapshot(codec::decode_policy_snapshot(h,a).map_err(|_|2u32)?),
        codec::OWNER=>codec::encode_owner_snapshot(codec::decode_owner_snapshot(h,a).map_err(|_|2u32)?),
        codec::CADENCE=>codec::encode_cadence_snapshot(codec::decode_cadence_snapshot(h,a).map_err(|_|2u32)?),
        _=>return Err(2),
    };w.map_err(|_|2)
}
/// Trusted callers provide live exact-sized aligned POD objects; null, overlap and
/// count errors are rejected, but pointer provenance/lifetime cannot be validated here.
pub unsafe extern "C" fn beluga_private_state_roundtrip(header:*const codec::Header,atoms:*const codec::Atom,count:u32,
    output_header:*mut codec::Header,output_atoms:*mut codec::Atom)->u32{
    if !disjoint(&[range(header,1),range(atoms,count as usize),range(output_header,1),range(output_atoms,count as usize)])
        || count==0 || count>codec::OWNER_COUNT as u32{return 2;}
    let h=unsafe{ptr::read(header)};
    if codec::count(h.domain)!=Some(count as usize){return 2;}
    let a=unsafe{core::slice::from_raw_parts(atoms,count as usize)};
    let Ok(result)=input(h,a)else{return 2;};
    unsafe{ptr::write(output_header,result.header);ptr::copy_nonoverlapping(result.atoms.as_ptr(),output_atoms,count as usize);}1
}
/// Structural result validation is not computation correlation or effect authority.
pub unsafe extern "C" fn beluga_private_state_validate(header:*const codec::Header,atoms:*const codec::Atom,count:u32)->u32{
    if !disjoint(&[range(header,1),range(atoms,count as usize)]) || count==0 || count>codec::OWNER_COUNT as u32{return 2;}
    let h=unsafe{ptr::read(header)};
    if codec::count(h.domain)!=Some(count as usize){return 2;}
    let a=unsafe{core::slice::from_raw_parts(atoms,count as usize)};
    if h.phase==codec::RESULT{if codec::validate_result(h,a).is_ok(){1}else{2}}
    else if input(h,a).is_ok(){1}else{2}
}
fn evaluate(request:BindRequest,h:codec::Header,a:&[codec::Atom],clock:&mut NativeClock)
    ->Result<(codec::Wire,Metadata,[Edit;13],[Time;13]),u32>{
    if request.abi!=1 || request.invocation==0 || !(1..=2).contains(&request.operation){return Err(2);}
    let mut draft=codec::decode_owner_snapshot(h,a).map_err(|_|2u32)?;
    // The numeric snapshot is already fresh. Begin exactly once at the outer entry.
    // No nested helper resets this journal; separate result phase/journal survive.
    draft.begin_time_assignment_frame();
    let mut meta=Metadata{abi:1,operation:request.operation,scope:request.operation,
        invocation:request.invocation,..Metadata::default()};
    if request.operation==1{
        meta.bound=draft.policy.try_bind(request.generation,clock,Dependencies::default())? as u32;
        meta.route=meta.bound;
    }else{
        meta.route=(draft.try_bind_native_peer(request.generation,clock,Dependencies::default())?==RouteAction::Clear)as u32;
    }
    meta.revision=draft.revision;meta.peer_present=draft.policy.peer.is_some()as u32;
    meta.peer=draft.policy.peer.unwrap_or(0);meta.queue_fault=draft.policy.queue.faulted as u32;
    meta.rtt_fault=draft.policy.rtt.faulted as u32;meta.read_count=clock.len as u32;
    let result=codec::encode_owner(draft,codec::RESULT).map_err(|_|2u32)?;
    let p=ClockProjection::observe(&draft,None);
    let values=[p.policy[0],p.policy[1],p.policy[2],p.policy[3],p.policy[4],p.policy[5],
        p.policy[6],p.policy[7],p.policy[8],None,None,None,p.last_evidence];
    let mut edits=[Edit::default();13];let mut coords=[Time::default();13];
    for (i,slot)in SLOTS.into_iter().enumerate(){
        if i<9 || (request.operation==2 && i==12){
            edits[i]=encode_edit(draft.time_edit(slot))?;coords[i]=Time::encode(values[i]);coords[i].decode()?;
        }
    }
    Ok((result,meta,edits,coords))
}
pub unsafe extern "C" fn beluga_private_owner_bind(request:*const BindRequest,header:*const codec::Header,
    atoms:*const codec::Atom,count:u32,callback:Option<Callback>,context:*mut c_void,
    output_header:*mut codec::Header,output_atoms:*mut codec::Atom,metadata:*mut Metadata,
    edits:*mut Edit,coordinates:*mut Time,reads:*mut Reply)->u32{
    if count!=codec::OWNER_COUNT as u32 || !disjoint(&[range(request,1),range(header,1),range(atoms,count as usize),
        range(output_header,1),range(output_atoms,count as usize),range(metadata,1),range(edits,13),
        range(coordinates,13),range(reads,15)]){return 2;}
    let Some(callback)=callback else{return 2;};
    let request=unsafe{ptr::read(request)};let h=unsafe{ptr::read(header)};
    let a=unsafe{core::slice::from_raw_parts(atoms,count as usize)};
    let mut clock=NativeClock::new(callback,context,request.invocation);
    match evaluate(request,h,a,&mut clock){
        Err(status)=>status,
        Ok((result,meta,e,c))=>{
            unsafe{ptr::write(output_header,result.header);ptr::copy_nonoverlapping(result.atoms.as_ptr(),output_atoms,count as usize);
                ptr::write(metadata,meta);ptr::copy_nonoverlapping(e.as_ptr(),edits,13);
                ptr::copy_nonoverlapping(c.as_ptr(),coordinates,13);ptr::copy_nonoverlapping(clock.reads.as_ptr(),reads,15);}
            1
        }
    }
}
const _:()={
    assert!(core::mem::size_of::<BindRequest>()==24);assert!(core::mem::align_of::<BindRequest>()==8);
    assert!(core::mem::offset_of!(BindRequest,abi)==0);assert!(core::mem::offset_of!(BindRequest,operation)==4);
    assert!(core::mem::offset_of!(BindRequest,generation)==8);assert!(core::mem::offset_of!(BindRequest,invocation)==16);
};
