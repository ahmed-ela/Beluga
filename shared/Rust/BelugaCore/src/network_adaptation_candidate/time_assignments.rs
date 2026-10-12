//! PRIVATE assignment provenance, not an exported/native ABI or permission to apply effects.
//! Coordinates alone never distinguish an untouched Instant from a newly assigned equal value.
//! Native callers must retain immutable current/prepared/explicit/read sidecars per invocation.
use super::dependencies::{ClockFacts, ClockSite, RelativeTime};
use core::fmt;

#[repr(usize)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TimeSlot {
    ProbeDeadline, ProbeQualification, PromotionDeadline, FloorWitness, FloorCooldown,
    SparseDeadline, QueueLow, QueueSoft, RttAdvancement, CadenceRegular,
    CadenceCapacity, CadenceLatest, EvidenceTime,
}
pub const SLOTS: [TimeSlot; 13] = [TimeSlot::ProbeDeadline, TimeSlot::ProbeQualification,
    TimeSlot::PromotionDeadline, TimeSlot::FloorWitness, TimeSlot::FloorCooldown,
    TimeSlot::SparseDeadline, TimeSlot::QueueLow, TimeSlot::QueueSoft,
    TimeSlot::RttAdvancement, TimeSlot::CadenceRegular, TimeSlot::CadenceCapacity,
    TimeSlot::CadenceLatest, TimeSlot::EvidenceTime];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExplicitTime { PolicyObservedAt, CadenceStart, CadenceObservation, EvidencePreparation }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TimeSource {
    CurrentInput(TimeSlot), CorrespondingPreparedInput(TimeSlot), Explicit(ExplicitTime),
    ActualRead { site: ClockSite, ordinal: usize }, Untracked,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Origin { pub source: TimeSource, pub delta: i128 }
impl Origin {
    pub const fn explicit(site: ExplicitTime) -> Self { Self { source: TimeSource::Explicit(site), delta: 0 } }
    pub fn advanced(self, delta: i128) -> Option<Self> {
        Some(Self { source: self.source, delta: self.delta.checked_add(delta)? })
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TimeEdit { Retain, Clear, Set(Origin), Invalid }

/// Nonsemantic invocation bookkeeping: never changes native numeric/NaN owner equality.
/// It is intentionally omitted from semantic Debug snapshots; tests inspect edits explicitly.
#[derive(Clone, Copy)]
pub struct AssignmentJournal { edits: [TimeEdit; 13], origins: [Origin; 13], invalid: bool }
impl Default for AssignmentJournal {
    fn default() -> Self {
        Self { edits: [TimeEdit::Retain; 13], invalid: false,
            origins: SLOTS.map(|slot| Origin { source: TimeSource::CurrentInput(slot), delta: 0 }) }
    }
}
impl fmt::Debug for AssignmentJournal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.write_str("<invocation-only>") }
}
impl PartialEq for AssignmentJournal { fn eq(&self, _other: &Self) -> bool { true } }
impl Eq for AssignmentJournal {}
impl AssignmentJournal {
    /// Only a fresh outer-entry numeric snapshot may omit this journal.
    pub fn is_current_snapshot(self) -> bool {
        self.valid() && SLOTS.into_iter().all(|slot| self.edit(slot) == TimeEdit::Retain &&
            self.origin(slot) == (Origin { source: TimeSource::CurrentInput(slot), delta: 0 }))
    }
    pub fn begin_current_frame(&mut self) { *self = Self::default(); }
    pub fn valid(self) -> bool { !self.invalid }
    pub fn edit(self, slot: TimeSlot) -> TimeEdit { self.edits[slot as usize] }
    pub fn origin(self, slot: TimeSlot) -> Origin { self.origins[slot as usize] }
    pub fn clear<T>(&mut self, slot: TimeSlot) -> Option<T> {
        self.edits[slot as usize] = TimeEdit::Clear;
        self.origins[slot as usize] = Origin { source: TimeSource::Untracked, delta: 0 };
        None
    }
    pub fn set<T>(&mut self, slot: TimeSlot, value: T, origin: Option<Origin>) -> Option<T> {
        let index = slot as usize;
        match origin.filter(|origin| origin.source != TimeSource::Untracked) {
            Some(origin) => { self.edits[index] = TimeEdit::Set(origin); self.origins[index] = origin; }
            None => { self.invalid = true; self.edits[index] = TimeEdit::Invalid;
                self.origins[index] = Origin { source: TimeSource::Untracked, delta: 0 }; }
        }
        Some(value) // No fake coordinate or extra policy mutation on provenance failure.
    }
    pub fn copy<T>(&mut self, destination: TimeSlot, source: TimeSlot, value: T, delta: i128) -> Option<T> {
        self.set(destination, value, self.origin(source).advanced(delta))
    }
    pub fn import_prepared<T>(&mut self, slot: TimeSlot, value: Option<T>) {
        if let Some(value) = value {
            self.set(slot, value, Some(Origin { source: TimeSource::CorrespondingPreparedInput(slot), delta: 0 }));
        } else { self.clear::<T>(slot); }
    }
}

/// One bounded, synchronous transcript of actual conditional cuts, never eager/replayed.
/// Budget exhaustion is invalid provenance; the mathematical owner isn't falsely stamped 0.
pub struct TrackedClock<'a, C, const N: usize> {
    inner: &'a mut C, reads: [Option<(ClockSite, RelativeTime)>; N], len: usize,
    last: TimeSource, overflow: bool,
}
impl<'a, C: ClockFacts, const N: usize> TrackedClock<'a, C, N> {
    pub fn new(inner: &'a mut C) -> Self {
        Self { inner, reads: [None; N], len: 0, last: TimeSource::Untracked, overflow: false }
    }
    pub fn read(&self, site: ClockSite, ordinal: usize) -> Option<RelativeTime> {
        self.reads.get(ordinal).copied().flatten().filter(|(actual, _)| *actual == site).map(|(_, time)| time)
    }
    pub fn len(&self) -> usize { self.len }
    pub fn valid(&self) -> bool { !self.overflow }
}
impl<C: ClockFacts, const N: usize> ClockFacts for TrackedClock<'_, C, N> {
    fn cut(&mut self, site: ClockSite) -> RelativeTime {
        let time = self.inner.cut(site);
        if let Some(entry) = self.reads.get_mut(self.len) {
            *entry = Some((site, time));
            self.last = TimeSource::ActualRead { site, ordinal: self.len }; self.len += 1;
        } else { self.overflow = true; self.last = TimeSource::Untracked; }
        time
    }
    fn last_time_source(&self) -> TimeSource { self.last }
}

/// Immutable copied coordinates are validation facts, not native Instant custody/capabilities.
pub trait TimeInputs { fn coordinate(&self, source: TimeSource) -> Option<RelativeTime>; }
pub fn resolve(slot: TimeSlot, edit: TimeEdit, input: &impl TimeInputs)
    -> Result<Option<RelativeTime>, ()>
{
    match edit {
        TimeEdit::Retain => Ok(input.coordinate(TimeSource::CurrentInput(slot))),
        TimeEdit::Clear => Ok(None),
        TimeEdit::Set(origin) => Ok(Some(input.coordinate(origin.source).ok_or(())?
            .checked_add(origin.delta).ok_or(())?)),
        TimeEdit::Invalid => Err(()),
    }
}
