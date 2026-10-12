//! PRIVATE complete-state zero-clock event ABI. This is not native command,
//! ACK, stop, resume, authentication, capture, or resource admission authority.
//! Inputs are fresh numeric snapshots; native current/observed custody is held
//! separately by the caller. These observed retentions copy no native Instants.
//! All borrowed POD objects must remain initialized, live, and unmodified until
//! return. Alignment/disjointness checks do not prove pointer provenance.
//! Denial writes no output; success is sequential, not multi-buffer atomic.
use core::ptr;
use crate::network_adaptation_candidate::*;
use crate::network_adaptation_candidate::state_codec as codec;
use crate::native_clock_assay::{Time, Edit, Reply, Metadata, encode_edit, range};
use crate::native_owner_codec::disjoint;

pub const POLICY_ACTIVATE_SHOW:u32=101;
pub const POLICY_RETAIN_ATTEMPT:u32=102;
pub const POLICY_RETAIN_STARTUP_TERMINAL:u32=103;
pub const POLICY_RESUME_SUCCEEDED:u32=104;
pub const OWNER_STOP_SAMPLING:u32=105;
pub const OWNER_ACTIVATE_SHOW:u32=106;
pub const OWNER_RESUME_WITHOUT_REVISION:u32=107;
pub const OWNER_RESUME_AND_ADVANCE:u32=108;
pub const OWNER_COLLECTOR_GATE:u32=109;

#[repr(C)]
#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub struct EventRequest {
    pub abi:u32,
    pub operation:u32,
    pub generation:u64,
    pub invocation:u64,
    pub show:u64,
    pub capture_source_present:u32,
    pub resume_context_absent:u32,
}
#[derive(Clone,Copy)]
enum Operation {
    PolicyActivate, RetainAttempt, RetainStartup, PolicyResume,
    StopSampling, OwnerActivate, ResumeWithoutRevision, ResumeAndAdvance, CollectorGate,
}
impl Operation {
    fn decode(request:EventRequest)->Result<Self,u32> {
        if request.abi!=1 || request.invocation==0 {return Err(2);}
        let operation=match request.operation {
            POLICY_ACTIVATE_SHOW=>Self::PolicyActivate,
            POLICY_RETAIN_ATTEMPT=>Self::RetainAttempt,
            POLICY_RETAIN_STARTUP_TERMINAL=>Self::RetainStartup,
            POLICY_RESUME_SUCCEEDED=>Self::PolicyResume,
            OWNER_STOP_SAMPLING=>Self::StopSampling,
            OWNER_ACTIVATE_SHOW=>Self::OwnerActivate,
            OWNER_RESUME_WITHOUT_REVISION=>Self::ResumeWithoutRevision,
            OWNER_RESUME_AND_ADVANCE=>Self::ResumeAndAdvance,
            OWNER_COLLECTOR_GATE=>Self::CollectorGate,
            _=>return Err(2),
        };
        let identity=matches!(operation,Self::PolicyActivate|Self::OwnerActivate);
        if !identity && (request.generation!=0 || request.show!=0) {return Err(2);}
        let capture=matches!(operation,Self::CollectorGate);
        if (capture && (request.capture_source_present>1 || request.resume_context_absent>1)) ||
            (!capture && (request.capture_source_present!=0 || request.resume_context_absent!=0)) {return Err(2);}
        Ok(operation)
    }
    fn needs_observed(self)->bool {matches!(self,Self::RetainAttempt|Self::RetainStartup)}
    fn scope(self)->u32 {if matches!(self,Self::PolicyActivate|Self::RetainAttempt|Self::RetainStartup|Self::PolicyResume){1}else{2}}
    fn time_mask(self)->u16 {
        match self {
            Self::RetainAttempt=>1<<3,
            Self::RetainStartup=>1<<5,
            Self::PolicyResume|Self::ResumeWithoutRevision|Self::ResumeAndAdvance=>1<<2,
            Self::StopSampling=>1<<12,
            Self::PolicyActivate|Self::OwnerActivate|Self::CollectorGate=>0,
        }
    }
}
struct ResultBundle {state:codec::Wire,metadata:Metadata,edits:[Edit;13],coordinates:[Time;13]}
fn values(owner:&Owner)->[Option<RelativeTime>;13] {
    let p=ClockProjection::observe(owner,None);
    [p.policy[0],p.policy[1],p.policy[2],p.policy[3],p.policy[4],
     p.policy[5],p.policy[6],p.policy[7],p.policy[8],None,None,None,p.last_evidence]
}
fn evaluate(request:EventRequest,header:codec::Header,atoms:&[codec::Atom],
    observed:Option<(codec::Header,&[codec::Atom])>)->Result<ResultBundle,u32> {
    let operation=Operation::decode(request)?;
    if operation.needs_observed()!=observed.is_some(){return Err(2);}
    // Decode both complete snapshots before an early-returning semantic guard.
    // Never alias/reconstruct observed from current, or reset imported defaults.
    let mut draft=codec::decode_owner_snapshot(header,atoms).map_err(|_|2u32)?;
    let observed=match observed {
        Some((header,atoms))=>Some(codec::decode_policy_snapshot(header,atoms).map_err(|_|2u32)?),
        None=>None,
    };
    let current_values=values(&draft);
    draft.begin_time_assignment_frame(); // exactly one outer invocation
    let mut enabled=0;
    match operation {
        Operation::PolicyActivate=>draft.policy.activate_show(request.generation,request.show),
        Operation::RetainAttempt=>draft.policy.retain_attempt(observed.ok_or(2u32)?),
        Operation::RetainStartup=>draft.policy.retain_startup_terminal(observed.ok_or(2u32)?),
        Operation::PolicyResume=>draft.policy.resume_succeeded(),
        Operation::StopSampling=>draft.stop_sampling_bookkeeping(),
        Operation::OwnerActivate=>draft.activate_owned_show(request.generation,request.show),
        Operation::ResumeWithoutRevision=>draft.resume_succeeded_without_revision(),
        Operation::ResumeAndAdvance=>draft.resume_succeeded_and_advance(),
        Operation::CollectorGate=>enabled=draft.collector_capture_gate(
            request.capture_source_present==1,request.resume_context_absent==1) as u32,
    }
    let mask=operation.time_mask();
    let output_values=values(&draft);
    let mut edits=[Edit::default();13];
    let mut coordinates=[Time::default();13];
    for (index,slot) in SLOTS.into_iter().enumerate() {
        let edit=draft.time_edit(slot);
        if mask&(1<<index)==0 {
            if edit!=TimeEdit::Retain || output_values[index]!=current_values[index]{return Err(2);}
        } else {
            // This batch has no clock read, explicit time, prepared copy, or Set.
            if !matches!(edit,TimeEdit::Retain|TimeEdit::Clear){return Err(2);}
            edits[index]=encode_edit(edit)?;
            coordinates[index]=Time::encode(output_values[index]);
            coordinates[index].decode()?;
        }
    }
    let metadata=Metadata {
        abi:1,operation:request.operation,scope:operation.scope(),invocation:request.invocation,
        revision:draft.revision,peer_present:draft.policy.peer.is_some() as u32,
        peer:draft.policy.peer.unwrap_or(0),queue_fault:draft.policy.queue.faulted as u32,
        rtt_fault:draft.policy.rtt.faulted as u32,enabled,
        ..Metadata::default()
    };
    let state=codec::encode_owner(draft,codec::RESULT).map_err(|_|2u32)?;
    Ok(ResultBundle{state,metadata,edits,coordinates})
}

/// No callback parameter is accepted: these nine existing operations have no
/// clock cuts. Reads are an explicitly empty transcript, not a replay/default time.
pub unsafe extern "C" fn beluga_private_owner_event(
    request:*const EventRequest,header:*const codec::Header,atoms:*const codec::Atom,count:u32,
    observed_header:*const codec::Header,observed_atoms:*const codec::Atom,observed_count:u32,
    output_header:*mut codec::Header,output_atoms:*mut codec::Atom,metadata:*mut Metadata,
    edits:*mut Edit,coordinates:*mut Time,reads:*mut Reply)->u32 {
    if count!=codec::OWNER_COUNT as u32 || (observed_count!=0 && observed_count!=codec::POLICY_COUNT as u32){return 2;}
    let mut ranges=[range(request,1),range(header,1),range(atoms,count as usize),
        range(output_header,1),range(output_atoms,count as usize),range(metadata,1),
        range(edits,13),range(coordinates,13),range(reads,15),None,None];
    if observed_count==0 {
        if !observed_header.is_null() || !observed_atoms.is_null(){return 2;}
    } else {
        ranges[9]=range(observed_header,1);
        ranges[10]=range(observed_atoms,observed_count as usize);
    }
    if !disjoint(&ranges[..if observed_count==0{9}else{11}]){return 2;}
    let request=unsafe{ptr::read(request)};
    let header=unsafe{ptr::read(header)};
    let atoms=unsafe{core::slice::from_raw_parts(atoms,count as usize)};
    let observed=if observed_count==0 {None}else {
        Some((unsafe{ptr::read(observed_header)},unsafe{core::slice::from_raw_parts(observed_atoms,observed_count as usize)}))
    };
    match evaluate(request,header,atoms,observed) {
        Err(status)=>status,
        Ok(result)=>{
            // Only after the entire result and operation-scoped journal validate.
            unsafe {
                ptr::write(output_header,result.state.header);
                ptr::copy_nonoverlapping(result.state.atoms.as_ptr(),output_atoms,count as usize);
                ptr::write(metadata,result.metadata);
                ptr::copy_nonoverlapping(result.edits.as_ptr(),edits,13);
                ptr::copy_nonoverlapping(result.coordinates.as_ptr(),coordinates,13);
                ptr::write_bytes(reads,0,15);
            }
            1
        }
    }
}
const _:()={
    assert!(core::mem::size_of::<EventRequest>()==40);assert!(core::mem::align_of::<EventRequest>()==8);
    assert!(core::mem::offset_of!(EventRequest,abi)==0);
    assert!(core::mem::offset_of!(EventRequest,operation)==4);
    assert!(core::mem::offset_of!(EventRequest,generation)==8);
    assert!(core::mem::offset_of!(EventRequest,invocation)==16);
    assert!(core::mem::offset_of!(EventRequest,show)==24);
    assert!(core::mem::offset_of!(EventRequest,capture_source_present)==32);
    assert!(core::mem::offset_of!(EventRequest,resume_context_absent)==36);
};
