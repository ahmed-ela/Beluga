//! PRIVATE complete stored-owner actual-clock lifecycle boundary.
//! Native resources, routes, actor/await fences and effect authority stay with
//! the caller. A locally derived operation/read plan must gate its callback
//! before sampling native time. Callback failure discards the unpublished draft.
//! Live exact-sized borrowed POD objects and callback context remain unchanged
//! through return; pointer checks cannot prove their provenance/lifetime.
//! Success writes six buffers sequentially, not concurrent atomic publication.
use core::{ffi::c_void, ptr};
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Reply, Metadata, Callback, NativeClock, encode_edit, range};
use crate::native_owner_codec::disjoint;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ClockEventRequest {
    pub abi:u32, pub operation:u32, pub generation:u64, pub invocation:u64,
    pub show:u64, pub minimum:u64, pub flag:u32, pub minimum_present:u32,
}
#[derive(Clone, Copy)]
struct Operation(u32);
impl Operation {
    fn decode(r:ClockEventRequest)->Result<Self,u32> {
        if r.abi!=1 || r.invocation==0 || !(201..=218).contains(&r.operation) ||
            r.flag>1 || r.minimum_present>1 {return Err(2);}
        let identity=r.operation==201 || (r.operation==214 && r.flag==1);
        if !identity && (r.generation!=0 || r.show!=0) {return Err(2);}
        if r.operation!=214 && r.flag!=0 {return Err(2);}
        if r.operation!=216 {
            if r.minimum_present!=0 || r.minimum!=0 {return Err(2);}
        } else if r.minimum_present==0 && r.minimum!=0 {return Err(2);}
        Ok(Self(r.operation))
    }
    fn needs_observed(self)->bool {matches!(self.0,203|204|208)}
    fn scope(self)->u32 {if self.0<=211 {1}else{2}}
    fn mask(self,r:ClockEventRequest)->u16 {
        match self.0 {
            201=>0x01ff,
            202|203|204|205|206|208|209|211|213|215|217=>0x00ef,
            207=>0x00cc,
            210|218=>0x00cf,
            212=>0x10ef,
            214=>if r.flag==1 {0x01ff}else{0x00ef},
            216=>0x10cc,
            _=>unreachable!(),
        }
    }
}
fn values(owner:&Owner)->[Option<RelativeTime>;13] {
    let p=ClockProjection::observe(owner,None);
    [p.policy[0],p.policy[1],p.policy[2],p.policy[3],p.policy[4],p.policy[5],
     p.policy[6],p.policy[7],p.policy[8],None,None,None,p.last_evidence]
}
struct ResultBundle {state:codec::Wire,meta:Metadata,edits:[Edit;13],coordinates:[Time;13]}
fn evaluate(r:ClockEventRequest,h:codec::Header,a:&[codec::Atom],
    observed:Option<(codec::Header,&[codec::Atom])>,clock:&mut NativeClock)->Result<ResultBundle,u32> {
    let op=Operation::decode(r)?;
    if op.needs_observed()!=observed.is_some(){return Err(2);}
    // Decode all current/observed fields before any semantic early return.
    let mut draft=codec::decode_owner_snapshot(h,a).map_err(|_|2u32)?;
    let observed=match observed {
        Some((h,a))=>Some(codec::decode_policy_snapshot(h,a).map_err(|_|2u32)?),None=>None,
    };
    let before=values(&draft);
    draft.begin_time_assignment_frame(); // once at outer entry, never inside helpers
    let d=Dependencies::default();
    let mut bound=0;
    let route=match op.0 {
        201=>{bound=draft.policy.try_reserve_show(r.generation,r.show,clock,d)? as u32;bound},
        202=>{draft.policy.try_end_show(clock,d)?;0},
        203=>{draft.policy.try_retain_rtt_fault(observed.ok_or(2u32)?,clock,d)?;0},
        204=>{draft.policy.try_retain_fault(observed.ok_or(2u32)?,clock,d)?;0},
        205=>{draft.policy.try_invalidate_route(clock,d)?;1},
        206=>{draft.policy.try_revoke_for_hide(clock,d)?;0},
        207=>{draft.policy.try_reset_incomplete(clock,d)?;0},
        208=>{draft.policy.try_retain_fast_identity(observed.ok_or(2u32)?,clock,d)?;0},
        209=>{draft.policy.try_resume_began(clock,d)?;0},
        210=>{draft.policy.try_resume_failed(clock,d)?;0},
        211=>{draft.policy.try_reset_inactive(clock,d)?;0},
        212=>(draft.try_route_invalidated(clock,d)?==RouteAction::Clear) as u32,
        213=>{draft.try_end_show_and_advance(clock,d)?;0},
        214=>(draft.try_visibility_command(r.flag==1,r.generation,r.show,clock,d)?==RouteAction::Clear) as u32,
        215=>{draft.try_hide_health_revocation(clock,d)?;0},
        216=>{draft.try_begin_post_resume_epoch((r.minimum_present==1).then_some(r.minimum),clock,d)?;0},
        217=>{draft.try_resume_accepted(clock,d)?;0},
        218=>{draft.try_resume_failed_and_advance(clock,d)?;0},
        _=>unreachable!(),
    };
    let after=values(&draft);
    let mask=op.mask(r);
    let mut edits=[Edit::default();13];
    let mut coordinates=[Time::default();13];
    for (index,slot) in SLOTS.into_iter().enumerate() {
        let edit=draft.time_edit(slot);
        if mask&(1<<index)==0 {
            if edit!=TimeEdit::Retain || before[index]!=after[index] {return Err(5);}
        } else {
            // No operation in this batch copies or sets a native Instant.
            if !matches!(edit,TimeEdit::Retain|TimeEdit::Clear){return Err(5);}
            edits[index]=encode_edit(edit)?;
            coordinates[index]=Time::encode(after[index]);
            coordinates[index].decode()?;
        }
    }
    let meta=Metadata {abi:1,operation:r.operation,scope:op.scope(),read_count:clock.len as u32,
        invocation:r.invocation,revision:draft.revision,peer:draft.policy.peer.unwrap_or(0),
        peer_present:draft.policy.peer.is_some() as u32,bound,route,
        queue_fault:draft.policy.queue.faulted as u32,rtt_fault:draft.policy.rtt.faulted as u32,
        ..Metadata::default()};
    let state=codec::encode_owner(draft,codec::RESULT).map_err(|_|2u32)?;
    Ok(ResultBundle{state,meta,edits,coordinates})
}
pub unsafe extern "C" fn beluga_private_owner_clock_event(
    request:*const ClockEventRequest,header:*const codec::Header,atoms:*const codec::Atom,count:u32,
    observed_header:*const codec::Header,observed_atoms:*const codec::Atom,observed_count:u32,
    callback:Option<Callback>,context:*mut c_void,
    output_header:*mut codec::Header,output_atoms:*mut codec::Atom,metadata:*mut Metadata,
    edits:*mut Edit,coordinates:*mut Time,reads:*mut Reply)->u32 {
    if count!=codec::OWNER_COUNT as u32 || (observed_count!=0 && observed_count!=codec::POLICY_COUNT as u32){return 2;}
    let mut ranges=[range(request,1),range(header,1),range(atoms,count as usize),
        range(output_header,1),range(output_atoms,count as usize),range(metadata,1),range(edits,13),
        range(coordinates,13),range(reads,15),None,None];
    if observed_count==0 {
        if !observed_header.is_null() || !observed_atoms.is_null(){return 2;}
    } else {
        ranges[9]=range(observed_header,1);ranges[10]=range(observed_atoms,observed_count as usize);
    }
    if !disjoint(&ranges[..if observed_count==0{9}else{11}]){return 2;}
    let Some(callback)=callback else{return 2;};
    let r=unsafe{ptr::read(request)};
    let h=unsafe{ptr::read(header)};
    let a=unsafe{core::slice::from_raw_parts(atoms,count as usize)};
    let observed=if observed_count==0 {None}else{
        Some((unsafe{ptr::read(observed_header)},unsafe{core::slice::from_raw_parts(observed_atoms,observed_count as usize)}))
    };
    let mut clock=NativeClock::new(callback,context,r.invocation);
    match evaluate(r,h,a,observed,&mut clock) {
        Err(status)=>status,
        Ok(result)=>{
            unsafe {
                ptr::write(output_header,result.state.header);
                ptr::copy_nonoverlapping(result.state.atoms.as_ptr(),output_atoms,count as usize);
                ptr::write(metadata,result.meta);
                ptr::copy_nonoverlapping(result.edits.as_ptr(),edits,13);
                ptr::copy_nonoverlapping(result.coordinates.as_ptr(),coordinates,13);
                ptr::copy_nonoverlapping(clock.reads.as_ptr(),reads,15);
            }
            1
        }
    }
}
const _:()={
    assert!(core::mem::size_of::<ClockEventRequest>()==48);assert!(core::mem::align_of::<ClockEventRequest>()==8);
    assert!(core::mem::offset_of!(ClockEventRequest,abi)==0);assert!(core::mem::offset_of!(ClockEventRequest,operation)==4);
    assert!(core::mem::offset_of!(ClockEventRequest,generation)==8);assert!(core::mem::offset_of!(ClockEventRequest,invocation)==16);
    assert!(core::mem::offset_of!(ClockEventRequest,show)==24);assert!(core::mem::offset_of!(ClockEventRequest,minimum)==32);
    assert!(core::mem::offset_of!(ClockEventRequest,flag)==40);assert!(core::mem::offset_of!(ClockEventRequest,minimum_present)==44);
};
