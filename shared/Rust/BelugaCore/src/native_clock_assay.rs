//! PRIVATE restricted-constructor cross-language assay, NOT a complete owner ABI.
//! Each invocation owns a fresh full typed draft. Only the declared seed fields
//! are supported. Existing arbitrary product state is not accepted or serialized.
use crate::network_adaptation_candidate::*;
use core::{ffi::c_void, mem::{align_of, size_of}, ptr};

const ABI: u32 = 1;
const BUDGET: usize = 15;
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Time { pub present: u32, pub reserved: u32, pub high: i64, pub low: u64 }
impl Time {
    pub(crate) fn decode(self) -> Result<Option<i128>, u32> {
        if self.reserved != 0 || self.present > 1 { return Err(2); }
        let value = ((self.high as i128) << 64) | self.low as i128;
        if self.present == 0 { return if value == 0 { Ok(None) } else { Err(2) }; }
        // All supported inputs have a public native Duration component pair.
        let unit = 1_000_000_000_000_000_000i128;
        let seconds = value / unit;
        if seconds < i64::MIN as i128 || seconds > i64::MAX as i128 { return Err(2); }
        Ok(Some(value))
    }
    pub(crate) fn encode(value: Option<i128>) -> Self {
        value.map(|v| Self { present: 1, reserved: 0, high: (v >> 64) as i64, low: v as u64 }).unwrap_or_default()
    }
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Request {
    pub abi: u32, pub operation: u32, pub flags: u32, pub sample: u32,
    pub invocation: u64, pub cap: i64, pub fps: i64, pub generation: u64,
    pub peer_present: u32, pub enabled: u32, pub peer: u64, pub revision: u64,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Reply {
    pub abi: u32, pub status: u32, pub site: u32, pub ordinal: u32,
    pub invocation: u64, pub high: i64, pub low: u64, pub reserved: u64,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Edit {
    pub action: u32, pub source: u32, pub index: u32, pub ordinal: u32,
    pub high: i64, pub low: u64,
}
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Metadata {
    pub abi: u32, pub operation: u32, pub scope: u32, pub read_count: u32,
    pub invocation: u64, pub revision: u64, pub peer: u64,
    pub peer_present: u32, pub bound: u32, pub route: u32, pub sample: u32,
    pub enabled: u32, pub lease: u32, pub queue_fault: u32, pub rtt_fault: u32,
}
pub type Callback = unsafe extern "C" fn(*mut c_void, u64, u32, u32, *mut Reply) -> u32;
pub(crate) struct NativeClock {
    callback: Callback, context: *mut c_void, invocation: u64,
    pub(crate) reads: [Reply; BUDGET], pub(crate) len: usize, last: TimeSource,
}
impl NativeClock {
    pub(crate) fn new(callback: Callback, context: *mut c_void, invocation: u64) -> Self {
        Self { callback, context, invocation, reads: [Reply::default(); BUDGET], len: 0, last: TimeSource::Untracked }
    }
}
impl TryClockFacts for NativeClock {
    type Error = u32;
    fn try_cut(&mut self, site: ClockSite) -> Result<i128, u32> {
        if self.len == BUDGET { return Err(3); }
        let tag = match site { ClockSite::RttEvent => 0, ClockSite::RttApply => 1,
            ClockSite::QueueReset => 2, ClockSite::PublishedLease => 3, ClockSite::CopyFence => 4 };
        let ordinal = self.len as u32;
        let mut reply = Reply::default();
        // Borrowed synchronous context. The trusted caller supplies a valid thunk
        // and lifetime, catches native errors inside it, and denies same-frame reentry.
        let returned = unsafe { (self.callback)(self.context, self.invocation, tag, ordinal, &mut reply) };
        if returned != 1 { return Err(3); }
        if reply.abi != ABI || reply.status != 1 || reply.site != tag || reply.ordinal != ordinal ||
            reply.invocation != self.invocation || reply.reserved != 0 { return Err(4); }
        let value = Time { present: 1, reserved: 0, high: reply.high, low: reply.low }.decode()?.ok_or(4u32)?;
        self.reads[self.len] = reply;
        self.last = TimeSource::ActualRead { site, ordinal: self.len };
        self.len += 1;
        Ok(value)
    }
    fn last_try_time_source(&self) -> TimeSource { self.last }
    fn try_arithmetic<T>(&mut self, value: Option<T>) -> Result<T, Self::Error> {
        value.ok_or(2)
    }
}

pub(crate) fn encode_edit(edit: TimeEdit) -> Result<Edit, u32> {
    Ok(match edit {
        TimeEdit::Retain => Edit { action: 1, ..Edit::default() },
        TimeEdit::Clear => Edit { action: 2, ..Edit::default() },
        TimeEdit::Invalid => return Err(5),
        TimeEdit::Set(origin) => {
            let (source, index, ordinal) = match origin.source {
                TimeSource::CurrentInput(slot) => (1, slot as u32, 0),
                TimeSource::CorrespondingPreparedInput(slot) => (2, slot as u32, 0),
                TimeSource::Explicit(site) => (3, site as u32, 0),
                TimeSource::ActualRead { site, ordinal } => (4, match site { ClockSite::RttEvent => 0,
                    ClockSite::RttApply => 1, ClockSite::QueueReset => 2, ClockSite::PublishedLease => 3,
                    ClockSite::CopyFence => 4 }, ordinal as u32),
                TimeSource::Untracked => return Err(5),
            };
            Edit { action: 3, source, index, ordinal, high: (origin.delta >> 64) as i64, low: origin.delta as u64 }
        }
    })
}

fn evaluate(request: Request, current: [Time; 13], explicit: [Time; 4], clock: &mut NativeClock)
    -> Result<(Metadata, [Edit; 13], [Time; 13]), u32>
{
    if request.abi != ABI || request.invocation == 0 || !(1..=10).contains(&request.operation) ||
        request.flags & !15 != 0 || request.peer_present > 1 || request.enabled > 1 || request.sample > 2 ||
        (request.peer_present == 0 && request.peer != 0) || request.cap < 1 || request.cap > u32::MAX as i64 ||
        request.fps < 1 || request.fps > 240 { return Err(2); }
    let mut times = [None; 13];
    let mut supplied = [None; 4];
    for (i, time) in current.into_iter().enumerate() { times[i] = time.decode()?; }
    for (i, time) in explicit.into_iter().enumerate() { supplied[i] = time.decode()?; }
    let cadence_op = request.operation >= 7;
    // Constructor-backed assay owns only the declared domain. Unowned input is
    // absent; no hidden overwrite of preexisting product state is permitted.
    for i in 0..13 {
        let allowed = if cadence_op { (9..=11).contains(&i) } else { i < 9 || (request.operation == 2 && i == 12) };
        if !allowed && times[i].is_some() { return Err(2); }
    }
    let explicit_index = match request.operation { 7 => Some(1), 8..=10 => Some(2), _ => None };
    for i in 0..4 { if supplied[i].is_some() != (explicit_index == Some(i)) { return Err(2); } }
    if cadence_op && (request.flags != 0 || request.peer_present != 0 || request.revision != 0) { return Err(2); }
    if request.operation == 7 && times.iter().any(Option::is_some) { return Err(2); }
    if request.operation == 8 && request.generation > 1 { return Err(2); }
    if request.flags & 8 != 0 && times[8].is_none() { return Err(2); }
    if (8..=10).contains(&request.operation) && (times[9].is_none() || times[11].is_none()) { return Err(2); }
    // Bound additions before entering original Cadence arithmetic. No panic escape.
    if cadence_op {
        for value in [times[11], supplied[explicit_index.ok_or(2u32)?]].into_iter().flatten() {
            value.checked_add(500_000_000_000_000_000).ok_or(2u32)?;
        }
    }
    let dependencies = Dependencies::default();
    let mut owner = Owner::new(request.cap, request.fps, dependencies);
    owner.revision = request.revision;
    owner.policy.peer = (request.peer_present == 1).then_some(request.peer);
    owner.policy.probe_deadline = times[0]; owner.policy.probe_qualification_at = times[1];
    owner.policy.promotion = times[2].map(|deadline| Promotion { tier: Tier::Full, maximum_total: request.cap, deadline });
    owner.policy.floor_first_witness = times[3].map(|observed_at| FloorWitness { observed_at, bandwidth: Scalar::new(1.0) });
    owner.policy.floor_cooldown_at = times[4]; owner.policy.startup_sparse_deadline = times[5];
    owner.policy.queue.low_observation = times[6]; owner.policy.queue.soft_observation = times[7];
    owner.policy.queue.faulted = request.flags & 1 != 0;
    owner.policy.rtt.last_advancement = times[8]; owner.policy.rtt.raw.advancement_present = times[8].is_some() as u32;
    owner.policy.rtt.faulted = request.flags & 2 != 0;
    if request.flags & 8 != 0 { owner.policy.rtt.raw.age_present = 1; owner.policy.rtt.raw.age_seconds = 2; }
    owner.last_evidence = times[12];
    owner.begin_time_assignment_frame();
    let mut meta = Metadata { abi: ABI, operation: request.operation, invocation: request.invocation,
        scope: if cadence_op { 3 } else if request.operation == 2 { 2 } else { 1 }, ..Metadata::default() };
    let mut cadence = None;
    match request.operation {
        1 => { meta.bound = owner.policy.try_bind(request.generation, clock, dependencies)? as u32;
            meta.route = meta.bound; }
        2 => { meta.route = (owner.try_bind_native_peer(request.generation, clock, dependencies)? == RouteAction::Clear) as u32; }
        3 => owner.policy.queue.try_reset(true, clock, dependencies)?,
        4 => owner.policy.rtt.try_implicit(4, Observation::LegacyAbsent, clock, dependencies)?,
        5 => { let mut other = RoundTripTime::default(); other.faulted = request.flags & 4 != 0;
            owner.policy.rtt.try_copy_fence(other, clock, dependencies)?; }
        6 => meta.lease = owner.policy.rtt.try_published_lease(clock, dependencies)? as u32,
        7 => cadence = Some(Cadence::new(supplied[1].ok_or(2u32)?)),
        8..=10 => {
            let mut value = Cadence { times: Default::default(), next_regular: times[9].ok_or(2u32)?,
                next_capacity: times[10], latest: times[11].ok_or(2u32)?, capacity_enabled: request.enabled == 1,
                in_flight: match request.sample { 0 => None, 1 => Some(Sample::Regular), _ => Some(Sample::CapacityOnly) } };
            value.begin_time_assignment_frame();
            let now = supplied[2].ok_or(2u32)?;
            match request.operation {
                8 => value.set_capacity_enabled(request.generation == 1, now),
                9 => { meta.sample = match value.take_due(now) { None => 0, Some(Sample::Regular) => 1, Some(Sample::CapacityOnly) => 2 }; }
                _ => value.finish(now),
            }
            cadence = Some(value);
        }
        _ => return Err(2),
    }
    meta.revision = owner.revision; meta.peer_present = owner.policy.peer.is_some() as u32;
    meta.peer = owner.policy.peer.unwrap_or(0); meta.read_count = clock.len as u32;
    meta.queue_fault = owner.policy.queue.faulted as u32; meta.rtt_fault = owner.policy.rtt.faulted as u32;
    if let Some(value) = cadence { meta.enabled = value.capacity_enabled as u32; }
    let projection = ClockProjection::observe(&owner, cadence);
    let values = [projection.policy[0], projection.policy[1], projection.policy[2],
        projection.policy[3], projection.policy[4], projection.policy[5], projection.policy[6],
        projection.policy[7], projection.policy[8], projection.schedule[0], projection.schedule[1],
        projection.schedule[2], projection.last_evidence];
    let mut edits = [Edit::default(); 13]; let mut coordinates = [Time::default(); 13];
    for (i, slot) in SLOTS.into_iter().enumerate() {
        let owned = if cadence_op { (9..=11).contains(&i) } else { i < 9 || (request.operation == 2 && i == 12) };
        if owned {
            let edit = if let Some(value) = cadence { value.times.edit(slot) } else { owner.time_edit(slot) };
            edits[i] = encode_edit(edit)?; coordinates[i] = Time::encode(values[i]);
            // A mathematically finite deadline may cross the native component range.
            // Validate before publishing any result buffer, not only in Swift later.
            coordinates[i].decode()?;
        }
    }
    Ok((meta, edits, coordinates))
}

pub(crate) fn range<T>(pointer: *const T, count: usize) -> Option<(usize, usize)> {
    let start = pointer as usize;
    if pointer.is_null() || start % align_of::<T>() != 0 { return None; }
    Some((start, start.checked_add(size_of::<T>().checked_mul(count)?)?))
}
/// Caller must supply live initialized/aligned C POD objects with the exact lengths
/// in the header. All seven buffers must be disjoint and remain live for this call.
/// No arbitrary pointer safety is claimed. All output bytes remain untouched on denial.
pub unsafe extern "C" fn beluga_private_clock_assay(request: *const Request, current: *const Time,
    explicit: *const Time, callback: Option<Callback>, context: *mut c_void,
    metadata: *mut Metadata, edits: *mut Edit, coordinates: *mut Time, reads: *mut Reply) -> u32
{
    let ranges = [range(request, 1), range(current, 13), range(explicit, 4), range(metadata, 1),
        range(edits, 13), range(coordinates, 13), range(reads, BUDGET)];
    if ranges.iter().any(Option::is_none) { return 2; }
    for i in 0..ranges.len() { for j in i + 1..ranges.len() {
        let a = ranges[i].unwrap(); let b = ranges[j].unwrap();
        if a.0 < b.1 && b.0 < a.1 { return 2; }
    } }
    let Some(callback) = callback else { return 2; };
    let input = unsafe { ptr::read(request) };
    let mut input_times = [Time::default(); 13]; let mut input_explicit = [Time::default(); 4];
    unsafe { ptr::copy_nonoverlapping(current, input_times.as_mut_ptr(), 13);
        ptr::copy_nonoverlapping(explicit, input_explicit.as_mut_ptr(), 4); }
    let mut clock = NativeClock { callback, context, invocation: input.invocation,
        reads: [Reply::default(); BUDGET], len: 0, last: TimeSource::Untracked };
    match evaluate(input, input_times, input_explicit, &mut clock) {
        Err(status) => status,
        Ok((meta, output_edits, output_times)) => {
            unsafe { ptr::write(metadata, meta); ptr::copy_nonoverlapping(output_edits.as_ptr(), edits, 13);
                ptr::copy_nonoverlapping(output_times.as_ptr(), coordinates, 13);
                ptr::copy_nonoverlapping(clock.reads.as_ptr(), reads, BUDGET); }
            1
        }
    }
}

const _: () = {
    assert!(core::mem::offset_of!(Time, present) == 0);
    assert!(core::mem::offset_of!(Time, reserved) == 4);
    assert!(core::mem::offset_of!(Time, high) == 8);
    assert!(core::mem::offset_of!(Time, low) == 16);
    assert!(core::mem::offset_of!(Request, abi) == 0);
    assert!(core::mem::offset_of!(Request, operation) == 4);
    assert!(core::mem::offset_of!(Request, flags) == 8);
    assert!(core::mem::offset_of!(Request, sample) == 12);
    assert!(core::mem::offset_of!(Request, invocation) == 16);
    assert!(core::mem::offset_of!(Request, cap) == 24);
    assert!(core::mem::offset_of!(Request, fps) == 32);
    assert!(core::mem::offset_of!(Request, generation) == 40);
    assert!(core::mem::offset_of!(Request, peer_present) == 48);
    assert!(core::mem::offset_of!(Request, enabled) == 52);
    assert!(core::mem::offset_of!(Request, peer) == 56);
    assert!(core::mem::offset_of!(Request, revision) == 64);
    assert!(core::mem::offset_of!(Reply, abi) == 0);
    assert!(core::mem::offset_of!(Reply, status) == 4);
    assert!(core::mem::offset_of!(Reply, site) == 8);
    assert!(core::mem::offset_of!(Reply, ordinal) == 12);
    assert!(core::mem::offset_of!(Reply, invocation) == 16);
    assert!(core::mem::offset_of!(Reply, high) == 24);
    assert!(core::mem::offset_of!(Reply, low) == 32);
    assert!(core::mem::offset_of!(Reply, reserved) == 40);
    assert!(core::mem::offset_of!(Edit, action) == 0);
    assert!(core::mem::offset_of!(Edit, source) == 4);
    assert!(core::mem::offset_of!(Edit, index) == 8);
    assert!(core::mem::offset_of!(Edit, ordinal) == 12);
    assert!(core::mem::offset_of!(Edit, high) == 16);
    assert!(core::mem::offset_of!(Edit, low) == 24);
    assert!(core::mem::offset_of!(Metadata, abi) == 0);
    assert!(core::mem::offset_of!(Metadata, operation) == 4);
    assert!(core::mem::offset_of!(Metadata, scope) == 8);
    assert!(core::mem::offset_of!(Metadata, read_count) == 12);
    assert!(core::mem::offset_of!(Metadata, invocation) == 16);
    assert!(core::mem::offset_of!(Metadata, revision) == 24);
    assert!(core::mem::offset_of!(Metadata, peer) == 32);
    assert!(core::mem::offset_of!(Metadata, peer_present) == 40);
    assert!(core::mem::offset_of!(Metadata, bound) == 44);
    assert!(core::mem::offset_of!(Metadata, route) == 48);
    assert!(core::mem::offset_of!(Metadata, sample) == 52);
    assert!(core::mem::offset_of!(Metadata, enabled) == 56);
    assert!(core::mem::offset_of!(Metadata, lease) == 60);
    assert!(core::mem::offset_of!(Metadata, queue_fault) == 64);
    assert!(core::mem::offset_of!(Metadata, rtt_fault) == 68);
    assert!(size_of::<Time>() == 24 && align_of::<Time>() == 8);
    assert!(size_of::<Request>() == 72 && align_of::<Request>() == 8);
    assert!(size_of::<Reply>() == 48 && align_of::<Reply>() == 8);
    assert!(size_of::<Edit>() == 32 && align_of::<Edit>() == 8);
    assert!(size_of::<Metadata>() == 72 && align_of::<Metadata>() == 8);
    assert!(core::mem::offset_of!(Time, high) == 8 && core::mem::offset_of!(Time, low) == 16);
    assert!(core::mem::offset_of!(Edit, high) == 16 && core::mem::offset_of!(Edit, low) == 24);
    assert!(core::mem::offset_of!(Request, invocation) == 16 && core::mem::offset_of!(Request, revision) == 64);
    assert!(core::mem::offset_of!(Reply, invocation) == 16 && core::mem::offset_of!(Reply, reserved) == 40);
    assert!(core::mem::offset_of!(Metadata, invocation) == 16 && core::mem::offset_of!(Metadata, rtt_fault) == 68);
};
