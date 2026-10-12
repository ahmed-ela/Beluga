//! Private lossless stored-state codec. Not actor integration or an effect capability.
//! Decode only at a declared fresh outer entry. Results retain separate time journals;
//! their phase is deliberately refused as another entry snapshot. No constructor,
//! reducer, float normalization or telemetry-coherence repair occurs here.
use super::*;
use super::dependencies::{Profile, TierDemand};
use crate::rtt_evidence::{RawState, RawMeasurement};

pub const ABI: u32 = 1;
pub const POLICY: u32 = 1;
pub const OWNER: u32 = 2;
pub const CADENCE: u32 = 3;
pub const SNAPSHOT: u32 = 1;
pub const RESULT: u32 = 2;
pub const POLICY_COUNT: usize = 168;
pub const OWNER_COUNT: usize = 179;
pub const CADENCE_COUNT: usize = 5;
// A continuation is not a stored-owner snapshot or an effect capability. Its
// invocation journals travel separately and must be checked/resolved by native
// code before any later event imports these scalar times as corresponding inputs.
pub const PREPARED: u32 = 4;
pub const CONTINUATION: u32 = 3;
pub const PREPARED_COUNT: usize = 222;
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Header { pub abi: u32, pub domain: u32, pub phase: u32, pub count: u32 }
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Atom { pub kind: u32, pub present: u32, pub high: i64, pub low: u64 }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Wire { pub header: Header, pub atoms: Vec<Atom> }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error { Header, Length, Kind, Presence, Payload, Width, Time, Journal }
fn time_fits(v:i128)->bool {
    let seconds=v/1_000_000_000_000_000_000;
    (i64::MIN as i128..=i64::MAX as i128).contains(&seconds)
}
struct Writer { atoms:Vec<Atom>, invalid:bool }
impl Writer {
    fn new()->Self { Self { atoms:Vec::new(),invalid:false } }
    fn atom(&mut self,kind:u32,v:Option<(i64,u64)>) {
        self.atoms.push(v.map(|(high,low)|Atom{kind,present:1,high,low})
            .unwrap_or(Atom{kind,..Atom::default()}));
    }
    fn none(&mut self,kind:u32) { self.atom(kind,None); }
    fn u(&mut self,v:u64) { self.ou(Some(v)); }
    fn ou(&mut self,v:Option<u64>) { self.atom(1,v.map(|v|(0,v))); }
    fn i(&mut self,v:i64) { self.oi(Some(v)); }
    fn oi(&mut self,v:Option<i64>) { self.atom(2,v.map(|v|(0,v as u64))); }
    fn s(&mut self,v:Scalar) { self.os(Some(v)); }
    fn os(&mut self,v:Option<Scalar>) { self.atom(3,v.map(|v|(0,v.0))); }
    fn b(&mut self,v:bool) { self.atom(4,Some((0,v as u64))); }
    fn ob(&mut self,v:Option<bool>) { self.atom(4,v.map(|v|(0,v as u64))); }
    fn u8(&mut self,v:u8) { self.atom(5,Some((0,v as u64))); }
    fn u32(&mut self,v:u32) { self.atom(6,Some((0,v as u64))); }
    fn tier(&mut self,v:Tier) { self.otier(Some(v)); }
    fn otier(&mut self,v:Option<Tier>) { self.atom(7,v.map(|v|(0,v as u64))); }
    fn lane(&mut self,v:Option<EvidenceLane>) {
        self.atom(8,v.map(|v|(0,match v{EvidenceLane::FastSender=>0,EvidenceLane::OrdinaryFallback=>1})));
    }
    fn sample(&mut self,v:Option<Sample>) {
        self.atom(9,v.map(|v|(0,match v{Sample::Regular=>0,Sample::CapacityOnly=>1})));
    }
    fn t(&mut self,v:i128) { self.ot(Some(v)); }
    fn ot(&mut self,v:Option<i128>) {
        if v.is_some_and(|v|!time_fits(v)) { self.invalid=true; }
        self.atom(10,v.map(|v|((v>>64)as i64,v as u64)));
    }
    fn finish(self,domain:u32,phase:u32,count:usize)->Result<Wire,Error>{
        if self.invalid {return Err(Error::Time);}
        if self.atoms.len()!=count {return Err(Error::Length);}
        Ok(Wire{header:Header{abi:ABI,domain,phase,count:count as u32},atoms:self.atoms})
    }
}
struct Reader<'a>{atoms:&'a [Atom],at:usize}
impl<'a> Reader<'a>{
    fn new(header:Header,atoms:&'a[Atom],domain:u32,phase:u32,count:usize)->Result<Self,Error>{
        if header!= (Header{abi:ABI,domain,phase,count:count as u32}) {return Err(Error::Header);}
        if atoms.len()!=count {return Err(Error::Length);}
        Ok(Self{atoms,at:0})
    }
    fn atom(&mut self,kind:u32,required:bool)->Result<Option<Atom>,Error>{
        let a=*self.atoms.get(self.at).ok_or(Error::Length)?;self.at+=1;
        if a.kind!=kind {return Err(Error::Kind);}
        if a.present>1 || (required && a.present!=1) {return Err(Error::Presence);}
        if a.present==0 {return if a.high==0 && a.low==0 {Ok(None)}else{Err(Error::Payload)};}
        if kind!=10 && a.high!=0 {return Err(Error::Payload);}
        let limit=match kind{4=>Some(1),5=>Some(u8::MAX as u64),6=>Some(u32::MAX as u64),
            7=>Some(7),8|9=>Some(1),_=>None};
        if limit.is_some_and(|limit|a.low>limit){return Err(Error::Width);}
        if kind==10 && !time_fits(((a.high as i128)<<64)|a.low as i128){return Err(Error::Time);}
        Ok(Some(a))
    }
    fn absent(&mut self,kind:u32)->Result<(),Error>{
        if self.atom(kind,false)?.is_some(){Err(Error::Presence)}else{Ok(())}
    }
    fn required(&mut self,kind:u32)->Result<Atom,Error>{self.atom(kind,true)?.ok_or(Error::Presence)}
    fn u(&mut self)->Result<u64,Error>{Ok(self.required(1)?.low)}
    fn ou(&mut self)->Result<Option<u64>,Error>{Ok(self.atom(1,false)?.map(|v|v.low))}
    fn i(&mut self)->Result<i64,Error>{Ok(self.required(2)?.low as i64)}
    fn oi(&mut self)->Result<Option<i64>,Error>{Ok(self.atom(2,false)?.map(|v|v.low as i64))}
    fn s(&mut self)->Result<Scalar,Error>{Ok(Scalar(self.required(3)?.low))}
    fn os(&mut self)->Result<Option<Scalar>,Error>{Ok(self.atom(3,false)?.map(|v|Scalar(v.low)))}
    fn b(&mut self)->Result<bool,Error>{Ok(self.required(4)?.low==1)}
    fn ob(&mut self)->Result<Option<bool>,Error>{Ok(self.atom(4,false)?.map(|v|v.low==1))}
    fn u8(&mut self)->Result<u8,Error>{Ok(self.required(5)?.low as u8)}
    fn u32(&mut self)->Result<u32,Error>{Ok(self.required(6)?.low as u32)}
    fn tier(&mut self)->Result<Tier,Error>{Tier::from_ordinal(self.required(7)?.low as u8).ok_or(Error::Width)}
    fn otier(&mut self)->Result<Option<Tier>,Error>{
        self.atom(7,false)?.map(|v|Tier::from_ordinal(v.low as u8).ok_or(Error::Width)).transpose()
    }
    fn lane(&mut self)->Result<Option<EvidenceLane>,Error>{
        Ok(self.atom(8,false)?.map(|v|if v.low==0{EvidenceLane::FastSender}else{EvidenceLane::OrdinaryFallback}))
    }
    fn sample(&mut self)->Result<Option<Sample>,Error>{
        Ok(self.atom(9,false)?.map(|v|if v.low==0{Sample::Regular}else{Sample::CapacityOnly}))
    }
    fn t(&mut self)->Result<i128,Error>{let v=self.required(10)?;Ok(((v.high as i128)<<64)|v.low as i128)}
    fn ot(&mut self)->Result<Option<i128>,Error>{Ok(self.atom(10,false)?.map(|v|((v.high as i128)<<64)|v.low as i128))}
    fn finish(self)->Result<(),Error>{if self.at==self.atoms.len(){Ok(())}else{Err(Error::Length)}}
}
fn write_measurement(w:&mut Writer,v:RawMeasurement){
    for word in v.fingerprint_words{w.u(word);}w.s(Scalar(v.total_bits));w.u(v.responses);
}
fn read_measurement(r:&mut Reader)->Result<RawMeasurement,Error>{
    let mut fingerprint_words=[0;8];for word in &mut fingerprint_words{*word=r.u()?;}
    Ok(RawMeasurement{fingerprint_words,total_bits:r.s()?.0,responses:r.u()?})
}
fn write_policy(w:&mut Writer,p:Policy){
    w.i(p.configured_cap);
    w.i(p.maximum_tier_video);
    w.i(p.base_fps);
    w.ou(p.peer);
    w.tier(p.tier);
    w.i(p.healthy_upgrades);
    w.i(p.bandwidth_downgrades);
    w.i(p.unavailable_samples);
    w.i(p.positive_bootstrap);
    w.i(p.limited_upgrades);
    w.i(p.probe_healthy);
    w.i(p.probe_grace);
    w.ot(p.probe_deadline);
    w.i(p.probe_cooldown);
    w.i(p.probe_failures);
    w.b(p.below_reserve_disproved);
    w.b(p.resume_restoration.is_some());
    if let Some(v)=p.resume_restoration{w.b(v.disproved);w.i(v.cooldown);w.i(v.failures);}
    else{w.none(4);w.none(2);w.none(2);}
    w.otier(p.probe_origin);
    w.otier(p.probe_best);
    w.otier(p.probe_confirmed);
    w.ot(p.probe_qualification_at);
    w.oi(p.probe_maximum);
    w.b(p.promotion.is_some());
    if let Some(v)=p.promotion{w.tier(v.tier);w.i(v.maximum_total);w.t(v.deadline);}
    else{w.none(7);w.none(2);w.none(10);}
    w.i(p.suspension_pressure);
    w.i(p.stable_resume);
    w.i(p.maximum_resume);
    w.b(p.bandwidth_unavailable);
    w.b(p.last_latency_pressure);
    w.b(p.last_positive_suspension_pressure);
    w.os(p.last_average_delay);
    w.ou(p.queue.packets);w.os(p.queue.delay_bits.map(Scalar));w.i(p.queue.pressure_count);
    w.ot(p.queue.low_observation);w.ot(p.queue.soft_observation);w.b(p.queue.faulted);
    // Inner RTT DTO is opaque: even reserved/presence words and unclaimed bodies survive.
    w.u32(p.rtt.raw.abi_version);
    w.u32(p.rtt.raw.reserved);
    w.u32(p.rtt.raw.baseline_present);
    w.u32(p.rtt.raw.bootstrap_count);
    w.u32(p.rtt.raw.disposition);
    w.u32(p.rtt.raw.health);
    w.u32(p.rtt.raw.uses_native);
    w.u32(p.rtt.raw.provisional);
    w.u32(p.rtt.raw.permits_initial);
    w.u32(p.rtt.raw.distinct_count);
    w.u32(p.rtt.raw.last_measured_present);
    w.u32(p.rtt.raw.advancement_present);
    w.u32(p.rtt.raw.age_present);
    w.u32(p.rtt.raw.watermark_present);
    w.u32(p.rtt.raw.fence_present);
    w.u32(p.rtt.raw.fence_current_present);
    w.u32(p.rtt.raw.reserved2);
    w.u32(p.rtt.raw.reserved3);
    w.s(Scalar(p.rtt.raw.baseline_bits));w.s(Scalar(p.rtt.raw.last_measured_bits));
    for bits in p.rtt.raw.bootstrap_bits{w.s(Scalar(bits));}
    w.i(p.rtt.raw.age_seconds);w.i(p.rtt.raw.age_attoseconds);
    write_measurement(w,p.rtt.raw.watermark);write_measurement(w,p.rtt.raw.fence);
    w.s(Scalar(p.rtt.raw.fence_current_bits));w.ot(p.rtt.last_advancement);w.b(p.rtt.faulted);
    w.u32(p.demand.configured_cap);
    for v in p.demand.profiles{w.i(v.baseline_video);w.i(v.maximum_video);w.i(v.maximum_total);
        w.i(v.minimum_sustainable);w.s(v.required);w.oi(v.next_direct);}
    w.u8(p.demand.profiles_count);w.b(p.demand.faulted);w.u8(p.demand.initial);w.i(p.demand.maximum_video);
    w.ou(p.consumed_sequence);
    w.b(p.route_present);
    w.b(p.capacity_sample.is_some());
    if let Some(v)=p.capacity_sample{w.ou(v.packets);w.os(v.delay);}else{w.none(1);w.none(3);}
    w.os(p.capacity_bandwidth_high);
    w.os(p.capacity_timestamp);
    w.ou(p.capacity_sequence);
    w.b(p.capacity_growth_veto);
    w.ou(p.floor_show);
    w.b(p.floor_reserved);
    w.b(p.floor_active);
    w.b(p.floor_attempt_consumed);
    w.b(p.floor_probe_cancelled);
    w.os(p.floor_seed);
    w.b(p.floor_first_witness.is_some());
    if let Some(v)=p.floor_first_witness{w.t(v.observed_at);w.s(v.bandwidth);}else{w.none(10);w.none(3);}
    w.ou(p.floor_regular_sequence);
    w.os(p.floor_regular_timestamp);
    w.ot(p.floor_cooldown_at);
    w.ou(p.startup_peer);
    w.ou(p.startup_show);
    w.b(p.startup_disproved);
    w.ot(p.startup_sparse_deadline);
}
fn read_policy(r:&mut Reader)->Result<Policy,Error>{
    // Each named field is constructed exhaustively; no seed/reset/recompute path.
    let configured_cap=r.i()?;let maximum_tier_video=r.i()?;let base_fps=r.i()?;
    let peer=r.ou()?;let tier=r.tier()?;let healthy_upgrades=r.i()?;
    let bandwidth_downgrades=r.i()?;let unavailable_samples=r.i()?;let positive_bootstrap=r.i()?;
    let limited_upgrades=r.i()?;let probe_healthy=r.i()?;let probe_grace=r.i()?;
    let probe_deadline=r.ot()?;let probe_cooldown=r.i()?;let probe_failures=r.i()?;
    let below_reserve_disproved=r.b()?;
    let resume_restoration=if r.b()?{Some(Restoration{disproved:r.b()?,cooldown:r.i()?,failures:r.i()?})}
        else{r.absent(4)?;r.absent(2)?;r.absent(2)?;None};
    let probe_origin=r.otier()?;let probe_best=r.otier()?;let probe_confirmed=r.otier()?;
    let probe_qualification_at=r.ot()?;let probe_maximum=r.oi()?;
    let promotion=if r.b()?{Some(Promotion{tier:r.tier()?,maximum_total:r.i()?,deadline:r.t()?})}
        else{r.absent(7)?;r.absent(2)?;r.absent(10)?;None};
    let suspension_pressure=r.i()?;let stable_resume=r.i()?;let maximum_resume=r.i()?;
    let bandwidth_unavailable=r.b()?;let last_latency_pressure=r.b()?;
    let last_positive_suspension_pressure=r.b()?;let last_average_delay=r.os()?;
    let queue=PacketQueue{times:Default::default(),packets:r.ou()?,delay_bits:r.os()?.map(|v|v.0),
        pressure_count:r.i()?,low_observation:r.ot()?,soft_observation:r.ot()?,faulted:r.b()?};
    let raw=RawState{
        abi_version: r.u32()?,
        reserved: r.u32()?,
        baseline_present: r.u32()?,
        bootstrap_count: r.u32()?,
        disposition: r.u32()?,
        health: r.u32()?,
        uses_native: r.u32()?,
        provisional: r.u32()?,
        permits_initial: r.u32()?,
        distinct_count: r.u32()?,
        last_measured_present: r.u32()?,
        advancement_present: r.u32()?,
        age_present: r.u32()?,
        watermark_present: r.u32()?,
        fence_present: r.u32()?,
        fence_current_present: r.u32()?,
        reserved2: r.u32()?,
        reserved3: r.u32()?,
        baseline_bits:r.s()?.0,last_measured_bits:r.s()?.0,
        bootstrap_bits:[r.s()?.0,r.s()?.0,r.s()?.0],
        age_seconds:r.i()?,age_attoseconds:r.i()?,
        watermark:read_measurement(r)?,fence:read_measurement(r)?,fence_current_bits:r.s()?.0,
    };
    let rtt=RoundTripTime{times:Default::default(),raw,last_advancement:r.ot()?,faulted:r.b()?};
    let demand_cap=r.u32()?;
    let mut profiles=[Profile::default();8];
    for v in &mut profiles{*v=Profile{baseline_video:r.i()?,maximum_video:r.i()?,maximum_total:r.i()?,
        minimum_sustainable:r.i()?,required:r.s()?,next_direct:r.oi()?};}
    let demand=TierDemand{configured_cap:demand_cap,profiles,profiles_count:r.u8()?,faulted:r.b()?,
        initial:r.u8()?,maximum_video:r.i()?};
    let consumed_sequence=r.ou()?;let route_present=r.b()?;
    let capacity_sample=if r.b()?{Some(CapacitySample{packets:r.ou()?,delay:r.os()?})}
        else{r.absent(1)?;r.absent(3)?;None};
    let capacity_bandwidth_high=r.os()?;let capacity_timestamp=r.os()?;let capacity_sequence=r.ou()?;
    let capacity_growth_veto=r.b()?;let floor_show=r.ou()?;let floor_reserved=r.b()?;
    let floor_active=r.b()?;let floor_attempt_consumed=r.b()?;let floor_probe_cancelled=r.b()?;let floor_seed=r.os()?;
    let floor_first_witness=if r.b()?{Some(FloorWitness{observed_at:r.t()?,bandwidth:r.s()?})}
        else{r.absent(10)?;r.absent(3)?;None};
    let floor_regular_sequence=r.ou()?;let floor_regular_timestamp=r.os()?;let floor_cooldown_at=r.ot()?;
    let startup_peer=r.ou()?;let startup_show=r.ou()?;let startup_disproved=r.b()?;let startup_sparse_deadline=r.ot()?;
    Ok(Policy{times:Default::default(),configured_cap,maximum_tier_video,base_fps,peer,tier,
        healthy_upgrades,bandwidth_downgrades,unavailable_samples,positive_bootstrap,limited_upgrades,
        probe_healthy,probe_grace,probe_deadline,probe_cooldown,probe_failures,below_reserve_disproved,
        resume_restoration,probe_origin,probe_best,probe_confirmed,probe_qualification_at,probe_maximum,
        promotion,suspension_pressure,stable_resume,maximum_resume,bandwidth_unavailable,last_latency_pressure,
        last_positive_suspension_pressure,last_average_delay,queue,rtt,demand,consumed_sequence,route_present,
        capacity_sample,capacity_bandwidth_high,capacity_timestamp,capacity_sequence,capacity_growth_veto,
        floor_show,floor_reserved,floor_active,floor_attempt_consumed,floor_probe_cancelled,floor_seed,
        floor_first_witness,floor_regular_sequence,floor_regular_timestamp,floor_cooldown_at,
        startup_peer,startup_show,startup_disproved,startup_sparse_deadline})
}
fn policy_pristine(p:Policy)->bool{p.times.is_current_snapshot() && p.queue.times.is_current_snapshot() && p.rtt.times.is_current_snapshot()}
pub fn encode_policy_snapshot(p:Policy)->Result<Wire,Error>{
    if !policy_pristine(p){return Err(Error::Journal);}encode_policy(p,SNAPSHOT)
}
pub(crate) fn encode_policy(p:Policy,phase:u32)->Result<Wire,Error>{
    let mut w=Writer::new();write_policy(&mut w,p);w.finish(POLICY,phase,POLICY_COUNT)
}
pub fn decode_policy_snapshot(h:Header,a:&[Atom])->Result<Policy,Error>{decode_policy(h,a,SNAPSHOT)}
fn decode_policy(h:Header,a:&[Atom],phase:u32)->Result<Policy,Error>{
    let mut r=Reader::new(h,a,POLICY,phase,POLICY_COUNT)?;let value=read_policy(&mut r)?;r.finish()?;Ok(value)
}
pub fn encode_owner_snapshot(v:Owner)->Result<Wire,Error>{
    if !v.times.is_current_snapshot() || !policy_pristine(v.policy){return Err(Error::Journal);}encode_owner(v,SNAPSHOT)
}
pub(crate) fn encode_owner(v:Owner,phase:u32)->Result<Wire,Error>{
    let mut w=Writer::new();write_policy(&mut w,v.policy);w.u(v.revision);w.b(v.fast_statistics_available);
    w.lane(v.evidence_lane);w.ot(v.last_evidence);w.ou(v.freshness.minimum);w.b(v.applied.is_some());
    if let Some(v)=v.applied{w.tier(v.tier);w.i(v.maximum_video);w.i(v.maximum_total);w.i(v.fps);w.s(v.scale);}
    else{w.none(7);w.none(2);w.none(2);w.none(2);w.none(3);}
    w.finish(OWNER,phase,OWNER_COUNT)
}
pub fn decode_owner_snapshot(h:Header,a:&[Atom])->Result<Owner,Error>{decode_owner(h,a,SNAPSHOT)}
fn decode_owner(h:Header,a:&[Atom],phase:u32)->Result<Owner,Error>{
    let mut r=Reader::new(h,a,OWNER,phase,OWNER_COUNT)?;let policy=read_policy(&mut r)?;
    let revision=r.u()?;let fast_statistics_available=r.b()?;let evidence_lane=r.lane()?;
    let last_evidence=r.ot()?;let freshness=Freshness{minimum:r.ou()?};
    let applied=if r.b()?{Some(Recommendation{tier:r.tier()?,maximum_video:r.i()?,maximum_total:r.i()?,fps:r.i()?,scale:r.s()?})}
        else{r.absent(7)?;r.absent(2)?;r.absent(2)?;r.absent(2)?;r.absent(3)?;None};
    r.finish()?;Ok(Owner{times:Default::default(),policy,revision,fast_statistics_available,evidence_lane,last_evidence,freshness,applied})
}
pub fn encode_cadence_snapshot(v:Cadence)->Result<Wire,Error>{
    if !v.times.is_current_snapshot(){return Err(Error::Journal);}encode_cadence(v,SNAPSHOT)
}
pub(crate) fn encode_cadence(v:Cadence,phase:u32)->Result<Wire,Error>{
    let mut w=Writer::new();w.t(v.next_regular);w.ot(v.next_capacity);w.b(v.capacity_enabled);w.sample(v.in_flight);w.t(v.latest);
    w.finish(CADENCE,phase,CADENCE_COUNT)
}
pub fn decode_cadence_snapshot(h:Header,a:&[Atom])->Result<Cadence,Error>{decode_cadence(h,a,SNAPSHOT)}
fn decode_cadence(h:Header,a:&[Atom],phase:u32)->Result<Cadence,Error>{
    let mut r=Reader::new(h,a,CADENCE,phase,CADENCE_COUNT)?;
    let v=Cadence{times:Default::default(),next_regular:r.t()?,next_capacity:r.ot()?,capacity_enabled:r.b()?,in_flight:r.sample()?,latest:r.t()?};
    r.finish()?;Ok(v)
}
pub fn validate_result(h:Header,a:&[Atom])->Result<(),Error>{
    match h.domain{POLICY=>{decode_policy(h,a,RESULT)?;},OWNER=>{decode_owner(h,a,RESULT)?;},
        CADENCE=>{decode_cadence(h,a,RESULT)?;},_=>return Err(Error::Header)}Ok(())
}
pub fn count(domain:u32)->Option<usize>{
    match domain{POLICY=>Some(POLICY_COUNT),OWNER=>Some(OWNER_COUNT),CADENCE=>Some(CADENCE_COUNT),_=>None}
}

fn write_recommendation(w:&mut Writer,v:Recommendation){
    w.tier(v.tier);w.i(v.maximum_video);w.i(v.maximum_total);w.i(v.fps);w.s(v.scale);
}
fn read_recommendation(r:&mut Reader)->Result<Recommendation,Error>{
    Ok(Recommendation{tier:r.tier()?,maximum_video:r.i()?,maximum_total:r.i()?,fps:r.i()?,scale:r.s()?})
}
fn absent_fields(r:&mut Reader,kinds:&[u32])->Result<(),Error>{
    for &kind in kinds{r.absent(kind)?;}Ok(())
}
const FLOOR_KINDS:[u32;23]=[1,4,4,4,4,2,1,1,1,1,1,3,3,1,2,2,6,6,6,6,1,6,4];
const CAPACITY_KINDS:[u32;11]=[6,7,1,1,1,2,2,1,1,1,1];
fn write_floor(w:&mut Writer,v:Option<FloorDiagnostics>){
    w.b(v.is_some());
    let Some(v)=v else{for kind in FLOOR_KINDS{w.none(kind);}return;};
    w.ou(v.show_epoch);w.b(v.reserved);w.b(v.active);w.b(v.consumed);w.b(v.disproved);
    w.i(v.cooldown_remaining);w.ou(v.collection_sequence);w.ou(v.previous_regular_sequence);
    w.ou(v.previous_regular_report_microseconds);w.ou(v.capacity_report_microseconds);
    w.ou(v.native_report_microseconds);w.os(v.current_bandwidth);w.os(v.first_bandwidth);
    w.ou(v.witness_age_microseconds);w.i(v.before_total);w.i(v.proposed_total);
    w.u32(match v.trend{Trend::Unknown=>0,Trend::Falling=>1,Trend::Flat=>2,Trend::Rising=>3});
    w.u32(match v.identity{FloorIdentity::NotChecked=>0,FloorIdentity::Fresh=>1,
        FloorIdentity::RejectedOrder=>2,FloorIdentity::RejectedTimestamp=>3});
    w.u32(match v.reason{
        FloorReason::NotEvaluated=>0,FloorReason::RejectedOrder=>1,FloorReason::RejectedTimestamp=>2,
        FloorReason::InactiveVisibility=>3,FloorReason::Consumed=>4,FloorReason::Disproved=>5,
        FloorReason::NotFloor=>6,FloorReason::ExistingProbe=>7,FloorReason::RttBlocked=>8,
        FloorReason::InvalidBandwidth=>9,FloorReason::OrdinaryProbeEligible=>10,FloorReason::NoHeadroom=>11,
        FloorReason::NoNewPackets=>12,FloorReason::QueueBlocked=>13,FloorReason::Cooldown=>14,
        FloorReason::FirstWitness=>15,FloorReason::TooEarly=>16,FloorReason::BandwidthFalling=>17,
        FloorReason::Qualified=>18,FloorReason::Admitted=>19});
    w.u32(match v.queue_kind{QueueKind::NotChecked=>0,QueueKind::Measured=>1,
        QueueKind::NoNewPackets=>2,QueueKind::UnavailableOrReset=>3});
    w.ou(v.queue_microseconds);
    w.atom(6,v.rtt_disposition.map(|v|(0,v as u64)));w.ob(v.rtt_allows_upgrade);
}
fn read_floor(r:&mut Reader)->Result<Option<FloorDiagnostics>,Error>{
    if !r.b()?{absent_fields(r,&FLOOR_KINDS)?;return Ok(None);}
    let show_epoch=r.ou()?;let reserved=r.b()?;let active=r.b()?;let consumed=r.b()?;let disproved=r.b()?;
    let cooldown_remaining=r.i()?;let collection_sequence=r.ou()?;let previous_regular_sequence=r.ou()?;
    let previous_regular_report_microseconds=r.ou()?;let capacity_report_microseconds=r.ou()?;
    let native_report_microseconds=r.ou()?;let current_bandwidth=r.os()?;let first_bandwidth=r.os()?;
    let witness_age_microseconds=r.ou()?;let before_total=r.i()?;let proposed_total=r.i()?;
    let trend=match r.u32()?{0=>Trend::Unknown,1=>Trend::Falling,2=>Trend::Flat,3=>Trend::Rising,_=>return Err(Error::Width)};
    let identity=match r.u32()?{0=>FloorIdentity::NotChecked,1=>FloorIdentity::Fresh,
        2=>FloorIdentity::RejectedOrder,3=>FloorIdentity::RejectedTimestamp,_=>return Err(Error::Width)};
    let reason=match r.u32()?{
        0=>FloorReason::NotEvaluated,1=>FloorReason::RejectedOrder,2=>FloorReason::RejectedTimestamp,
        3=>FloorReason::InactiveVisibility,4=>FloorReason::Consumed,5=>FloorReason::Disproved,
        6=>FloorReason::NotFloor,7=>FloorReason::ExistingProbe,8=>FloorReason::RttBlocked,
        9=>FloorReason::InvalidBandwidth,10=>FloorReason::OrdinaryProbeEligible,11=>FloorReason::NoHeadroom,
        12=>FloorReason::NoNewPackets,13=>FloorReason::QueueBlocked,14=>FloorReason::Cooldown,
        15=>FloorReason::FirstWitness,16=>FloorReason::TooEarly,17=>FloorReason::BandwidthFalling,
        18=>FloorReason::Qualified,19=>FloorReason::Admitted,_=>return Err(Error::Width)};
    let queue_kind=match r.u32()?{0=>QueueKind::NotChecked,1=>QueueKind::Measured,
        2=>QueueKind::NoNewPackets,3=>QueueKind::UnavailableOrReset,_=>return Err(Error::Width)};
    let queue_microseconds=r.ou()?;
    // This is a copied diagnostic word, not a policy enum or authority grant.
    let rtt_disposition=r.atom(6,false)?.map(|v|v.low as u32);let rtt_allows_upgrade=r.ob()?;
    Ok(Some(FloorDiagnostics{show_epoch,reserved,active,consumed,disproved,cooldown_remaining,
        collection_sequence,previous_regular_sequence,previous_regular_report_microseconds,
        capacity_report_microseconds,native_report_microseconds,current_bandwidth,first_bandwidth,
        witness_age_microseconds,before_total,proposed_total,trend,identity,reason,queue_kind,
        queue_microseconds,rtt_disposition,rtt_allows_upgrade}))
}
fn write_capacity(w:&mut Writer,v:Option<CapacityDiagnostics>){
    w.b(v.is_some());
    let Some(v)=v else{for kind in CAPACITY_KINDS{w.none(kind);}return;};
    w.u32(match v.reason{CapacityReason::Inactive=>0,CapacityReason::Expired=>1,CapacityReason::RejectedReport=>2,
        CapacityReason::RoundTripTime=>3,CapacityReason::RouteChanged=>4,CapacityReason::MissingPrimaryEvidence=>5,
        CapacityReason::ImmediateQueue=>6,CapacityReason::MissingBandwidth=>7,CapacityReason::BandwidthCollapse=>8,
        CapacityReason::QueueWithheld=>9,CapacityReason::GrowthVetoed=>10,CapacityReason::BandwidthNotAdvanced=>11,
        CapacityReason::AtCeiling=>12,CapacityReason::Increased=>13});
    w.otier(v.origin);w.ou(v.collection_sequence);w.ou(v.previous_native_microseconds);w.ou(v.native_microseconds);
    w.i(v.before_total);w.i(v.proposed_total);w.ou(v.collapse_threshold);w.ou(v.delta_packets);
    w.ou(v.delta_delay_microseconds);w.ou(v.average_queue_microseconds);
}
fn read_capacity(r:&mut Reader)->Result<Option<CapacityDiagnostics>,Error>{
    if !r.b()?{absent_fields(r,&CAPACITY_KINDS)?;return Ok(None);}
    let reason=match r.u32()?{0=>CapacityReason::Inactive,1=>CapacityReason::Expired,2=>CapacityReason::RejectedReport,
        3=>CapacityReason::RoundTripTime,4=>CapacityReason::RouteChanged,5=>CapacityReason::MissingPrimaryEvidence,
        6=>CapacityReason::ImmediateQueue,7=>CapacityReason::MissingBandwidth,8=>CapacityReason::BandwidthCollapse,
        9=>CapacityReason::QueueWithheld,10=>CapacityReason::GrowthVetoed,11=>CapacityReason::BandwidthNotAdvanced,
        12=>CapacityReason::AtCeiling,13=>CapacityReason::Increased,_=>return Err(Error::Width)};
    Ok(Some(CapacityDiagnostics{reason,origin:r.otier()?,collection_sequence:r.ou()?,
        previous_native_microseconds:r.ou()?,native_microseconds:r.ou()?,before_total:r.i()?,proposed_total:r.i()?,
        collapse_threshold:r.ou()?,delta_packets:r.ou()?,delta_delay_microseconds:r.ou()?,average_queue_microseconds:r.ou()?}))
}
/// Serialize every scalar field of an unpublished prepared continuation, without
/// normalizing IEEE payloads or optional/opaque state. The original invocation
/// journal is intentionally NOT this codec: raw event publication must separately
/// validate it and native resolution must retain the corresponding actual Instants.
pub fn encode_prepared_continuation(v:Prepared)->Result<Wire,Error>{
    if !v.policy.times.valid() || !v.policy.queue.times.valid() || !v.policy.rtt.times.valid(){return Err(Error::Journal);}
    let mut w=Writer::new();write_policy(&mut w,v.policy);
    // 168..170 generation/expected/applying;171 lane;172 active;173 capacity;
    // 174..179 changed;180..184 recommendation;185 route;186..209 floor;
    // 210..221 capacity diagnostics. Never substitute live owner atoms168..178.
    w.u(v.source_generation);w.u(v.expected_revision);w.u(v.applying_revision);
    w.u32(match v.lane{ProposalLane::Regular=>0,ProposalLane::Capacity=>1,ProposalLane::Expiry=>2});
    w.b(v.capture_active);w.b(v.capacity_only);w.b(v.changed.is_some());
    if let Some(v)=v.changed{write_recommendation(&mut w,v);}else{for kind in [7,2,2,2,3]{w.none(kind);}}
    write_recommendation(&mut w,v.recommendation);
    w.u32(match v.route_action{RouteAction::Retain=>0,RouteAction::Clear=>1,RouteAction::CopyIncoming=>2});
    write_floor(&mut w,v.floor_diagnostics);write_capacity(&mut w,v.capacity_diagnostics);
    w.finish(PREPARED,CONTINUATION,PREPARED_COUNT)
}
/// Decode only as a separately correlated, native-resolved prepared input to a
/// fresh synchronous event. No frame, raw pointer, clock permission, native route,
/// resource or sender receipt is carried. Journals are fresh current snapshots;
/// later policy adoption explicitly imports corresponding-prepared origins.
pub fn decode_prepared_continuation(h:Header,a:&[Atom])->Result<Prepared,Error>{
    let mut r=Reader::new(h,a,PREPARED,CONTINUATION,PREPARED_COUNT)?;
    let policy=read_policy(&mut r)?;let source_generation=r.u()?;let expected_revision=r.u()?;let applying_revision=r.u()?;
    let lane=match r.u32()?{0=>ProposalLane::Regular,1=>ProposalLane::Capacity,2=>ProposalLane::Expiry,_=>return Err(Error::Width)};
    let capture_active=r.b()?;let capacity_only=r.b()?;
    let changed=if r.b()?{Some(read_recommendation(&mut r)?)}else{absent_fields(&mut r,&[7,2,2,2,3])?;None};
    let recommendation=read_recommendation(&mut r)?;
    let route_action=match r.u32()?{0=>RouteAction::Retain,1=>RouteAction::Clear,
        2=>RouteAction::CopyIncoming,_=>return Err(Error::Width)};
    let floor_diagnostics=read_floor(&mut r)?;let capacity_diagnostics=read_capacity(&mut r)?;
    r.finish()?;Ok(Prepared{policy,source_generation,expected_revision,applying_revision,lane,
        capture_active,capacity_only,changed,recommendation,route_action,floor_diagnostics,capacity_diagnostics})
}
const _:()={assert!(core::mem::size_of::<Header>()==16);assert!(core::mem::align_of::<Header>()==4);
    assert!(core::mem::offset_of!(Header,abi)==0);assert!(core::mem::offset_of!(Header,domain)==4);
    assert!(core::mem::offset_of!(Header,phase)==8);assert!(core::mem::offset_of!(Header,count)==12);
    assert!(core::mem::size_of::<Atom>()==24);assert!(core::mem::align_of::<Atom>()==8);
    assert!(core::mem::offset_of!(Atom,kind)==0);assert!(core::mem::offset_of!(Atom,present)==4);
    assert!(core::mem::offset_of!(Atom,high)==8);assert!(core::mem::offset_of!(Atom,low)==16);};
