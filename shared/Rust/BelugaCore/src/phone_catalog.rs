//! Pure copied-value phone-catalog policy. Native code retains the shared lock,
//! complete opaque records, identity, crypto, decoder, receipt and durable effect.
//! The exact ABI is frozen in the approved phone-catalog ABI.md.

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawPhoneCatalogInput {
    pub abi_version: u32,
    pub stage: u32,
    pub operation: u32,
    pub flags: u32,
    pub count: u32,
    pub selected_slot: u32,
    pub target_slot: u32,
    pub duplicate_axes: u32,
    pub previous_phase: u32,
    pub candidate_phase: u32,
    pub previous_recovery: u32,
    pub candidate_recovery: u32,
    pub reserved0: u32,
    pub reserved1: u32,
    pub revision: u64,
    pub previous_outbound: u64,
    pub candidate_outbound: u64,
    pub previous_accepted: u64,
    pub candidate_accepted: u64,
    pub reserved2: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawPhoneCatalogResult {
    pub abi_version: u32,
    pub status: u32,
    pub error: u32,
    pub action: u32,
    pub count: u32,
    pub selected_slot: u32,
    pub target_slot: u32,
    pub reserved: u32,
    pub slot0: u32,
    pub slot1: u32,
    pub slot2: u32,
    pub slot3: u32,
    pub slot4: u32,
    pub slot5: u32,
    pub slot6: u32,
    pub slot7: u32,
    pub revision: u64,
}

#[derive(Clone, Copy)]
enum Stage {
    Header, RecordUniqueness, SelectionReceipt, Token, Add, UpdateLookup,
    UpdateBindingMonotonic, UpdateRecovery, Select, Forget, Plan, Finish,
}
impl Stage {
    fn parse(tag: u32) -> Option<Self> {
        Some(match tag {
            0 => Self::Header, 1 => Self::RecordUniqueness,
            2 => Self::SelectionReceipt, 3 => Self::Token, 4 => Self::Add,
            5 => Self::UpdateLookup, 6 => Self::UpdateBindingMonotonic,
            7 => Self::UpdateRecovery, 8 => Self::Select, 9 => Self::Forget,
            10 => Self::Plan, 11 => Self::Finish, _ => return None,
        })
    }
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum Operation { Structural, Add, Update, Select, Forget }
impl Operation {
    fn parse(tag: u32) -> Option<Self> {
        Some(match tag {
            0 => Self::Structural, 1 => Self::Add, 2 => Self::Update,
            3 => Self::Select, 4 => Self::Forget, _ => return None,
        })
    }
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum Phase { Pending, AcceptedReceived, Active, AcceptedIssued }
impl Phase {
    fn parse(tag: u32) -> Option<Self> {
        Some(match tag { 0 => Self::Pending, 1 => Self::AcceptedReceived,
            2 => Self::Active, 3 => Self::AcceptedIssued, _ => return None })
    }
    fn rank(self) -> i8 {
        match self { Self::Pending => 0, Self::AcceptedReceived => 1,
            Self::Active => 2, Self::AcceptedIssued => -1 }
    }
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum Recovery { None, Resend, Other, InvalidBridge }
impl Recovery {
    fn parse(tag: u32) -> Option<Self> {
        Some(match tag { 0 => Self::None, 1 => Self::Resend,
            2 => Self::Other, 3 => Self::InvalidBridge, _ => return None })
    }
}

struct Input { raw: RawPhoneCatalogInput, stage: Stage, operation: Operation }

fn occupied_or_nil(slot: u32, count: u32) -> bool { slot < count || slot == 8 }

// Construct the ONLY allowed input shape, then compare every field. This rejects
// all nonzero reserved/unused operands without truncating any admitted value.
fn validate(raw: RawPhoneCatalogInput) -> Option<Input> {
    let stage = Stage::parse(raw.stage)?;
    let operation = Operation::parse(raw.operation)?;
    let mut allowed = RawPhoneCatalogInput {
        abi_version: 1, stage: raw.stage, operation: raw.operation,
        ..RawPhoneCatalogInput::default()
    };
    match stage {
        Stage::Header => {
            if operation != Operation::Structural || raw.count > 9 { return None; }
            allowed.flags = raw.flags & 3; allowed.count = raw.count;
        }
        Stage::RecordUniqueness => {
            if operation != Operation::Structural { return None; }
            allowed.duplicate_axes = raw.duplicate_axes & 15;
        }
        Stage::SelectionReceipt => {
            if operation != Operation::Structural { return None; }
            allowed.flags = raw.flags & 3;
        }
        Stage::Token => {
            if operation == Operation::Structural { return None; }
            allowed.flags = raw.flags & 3;
        }
        Stage::Add => {
            if operation != Operation::Add || raw.count > 8 { return None; }
            allowed.count = raw.count; allowed.duplicate_axes = raw.duplicate_axes & 15;
        }
        Stage::UpdateLookup | Stage::Forget => {
            let required = if matches!(stage, Stage::UpdateLookup) {
                Operation::Update
            } else { Operation::Forget };
            if operation != required || raw.count > 8 || !occupied_or_nil(raw.target_slot, raw.count) {
                return None;
            }
            allowed.count = raw.count; allowed.target_slot = raw.target_slot;
        }
        Stage::UpdateBindingMonotonic => {
            if operation != Operation::Update { return None; }
            Phase::parse(raw.previous_phase)?; Phase::parse(raw.candidate_phase)?;
            allowed.flags = raw.flags & 1;
            allowed.previous_phase = raw.previous_phase; allowed.candidate_phase = raw.candidate_phase;
            allowed.previous_outbound = raw.previous_outbound; allowed.candidate_outbound = raw.candidate_outbound;
            allowed.previous_accepted = raw.previous_accepted; allowed.candidate_accepted = raw.candidate_accepted;
        }
        Stage::UpdateRecovery => {
            if operation != Operation::Update { return None; }
            Phase::parse(raw.previous_phase)?; Phase::parse(raw.candidate_phase)?;
            let previous = Recovery::parse(raw.previous_recovery)?;
            let candidate = Recovery::parse(raw.candidate_recovery)?;
            if raw.flags & 1 != 0 && (previous != Recovery::Resend || candidate != Recovery::Resend) {
                return None;
            }
            allowed.flags = raw.flags & 1;
            allowed.previous_phase = raw.previous_phase; allowed.candidate_phase = raw.candidate_phase;
            allowed.previous_recovery = raw.previous_recovery; allowed.candidate_recovery = raw.candidate_recovery;
        }
        Stage::Select => {
            if operation != Operation::Select || raw.count > 8 || !occupied_or_nil(raw.target_slot, raw.count)
                || (raw.flags & 1 != 0 && raw.target_slot != 8) { return None; }
            allowed.flags = raw.flags & 1; allowed.count = raw.count; allowed.target_slot = raw.target_slot;
        }
        Stage::Plan | Stage::Finish => {
            if operation == Operation::Structural || raw.count > 8
                || !occupied_or_nil(raw.selected_slot, raw.count) { return None; }
            match operation {
                Operation::Add => if raw.count == 8 || raw.target_slot != 8 { return None; },
                Operation::Update | Operation::Forget => if raw.target_slot >= raw.count { return None; },
                Operation::Select => if !occupied_or_nil(raw.target_slot, raw.count) { return None; },
                Operation::Structural => return None,
            }
            allowed.count = raw.count; allowed.selected_slot = raw.selected_slot; allowed.target_slot = raw.target_slot;
            if matches!(stage, Stage::Finish) {
                if raw.revision == 0 { return None; }
                let equal = raw.flags & 1 != 0;
                if (matches!(operation, Operation::Add | Operation::Forget) && equal)
                    || (operation == Operation::Select && equal != (raw.selected_slot == raw.target_slot)) {
                    return None;
                }
                allowed.flags = raw.flags & 1; allowed.revision = raw.revision;
            }
        }
    }
    if raw != allowed { return None; }
    Some(Input { raw, stage, operation })
}

fn empty(status: u32, error: u32) -> RawPhoneCatalogResult {
    RawPhoneCatalogResult { abi_version: 1, status, error, ..RawPhoneCatalogResult::default() }
}

fn planned(input: &Input, original: bool, action: u32, revision: u64) -> RawPhoneCatalogResult {
    let raw = input.raw;
    let mut slots = [9; 8];
    let mut count = raw.count;
    let mut selected = raw.selected_slot;
    let mut source = 0;
    let mut destination = 0;
    while source < raw.count {
        if !original && input.operation == Operation::Forget && source == raw.target_slot {
            source += 1;
            continue;
        }
        slots[destination as usize] = if !original && input.operation == Operation::Update
            && source == raw.target_slot { 8 } else { source };
        destination += 1; source += 1;
    }
    if !original {
        match input.operation {
            Operation::Add => { slots[count as usize] = 8; count += 1; }
            Operation::Select => selected = raw.target_slot,
            Operation::Forget => {
                count -= 1;
                if selected == raw.target_slot { selected = 8; }
                else if selected != 8 && selected > raw.target_slot { selected -= 1; }
            }
            Operation::Structural | Operation::Update => (),
        }
    }
    RawPhoneCatalogResult {
        abi_version: 1, status: 1, error: 0, action, count,
        selected_slot: selected, target_slot: raw.target_slot, reserved: 0,
        slot0: slots[0], slot1: slots[1], slot2: slots[2], slot3: slots[3],
        slot4: slots[4], slot5: slots[5], slot6: slots[6], slot7: slots[7], revision,
    }
}

#[must_use]
pub fn decide(raw: RawPhoneCatalogInput) -> RawPhoneCatalogResult {
    let Some(input) = validate(raw) else { return empty(0, 0); };
    let error = match input.stage {
        Stage::Header => if raw.flags & 1 == 0 { 1 } else if raw.flags & 2 == 0 { 2 }
            else if raw.count == 9 { 5 } else { 0 },
        Stage::RecordUniqueness | Stage::Add => if raw.duplicate_axes != 0 { 3 }
            else if matches!(input.stage, Stage::Add) && raw.count == 8 { 5 } else { 0 },
        Stage::SelectionReceipt => if raw.flags != 3 { 1 } else { 0 },
        Stage::Token => if raw.flags != 3 { 6 } else { 0 },
        Stage::UpdateLookup | Stage::Forget => if raw.target_slot == 8 { 4 } else { 0 },
        Stage::UpdateBindingMonotonic => {
            if raw.flags == 0 { 8 }
            else if raw.candidate_outbound < raw.previous_outbound
                || raw.candidate_accepted < raw.previous_accepted
                || Phase::parse(raw.candidate_phase).map(Phase::rank)
                    < Phase::parse(raw.previous_phase).map(Phase::rank) { 7 }
            else { 0 }
        }
        Stage::UpdateRecovery => {
            let previous = Recovery::parse(raw.previous_recovery);
            let candidate = Recovery::parse(raw.candidate_recovery);
            if previous == Some(Recovery::InvalidBridge) || candidate == Some(Recovery::InvalidBridge) { 10 }
            else if raw.previous_phase == raw.candidate_phase && previous == Some(Recovery::Resend)
                && raw.flags == 0 { 7 } else { 0 }
        }
        Stage::Select => if raw.flags == 0 && raw.target_slot == 8 { 4 } else { 0 },
        Stage::Plan => return planned(&input, false, 1, 0),
        Stage::Finish => {
            // Original whole-Catalog equality precedes the MAX check. In particular,
            // an exact Update no-op must restore old sources, not candidate source8.
            if raw.flags == 1 { return planned(&input, true, 2, raw.revision); }
            if raw.revision == u64::MAX { 9 }
            else { return planned(&input, false, 3, raw.revision + 1); }
        }
    };
    empty(1, error)
}

/// Recompute from copied input; malformed status0 is never a valid decision.
#[must_use]
pub fn result_is_valid(input: RawPhoneCatalogInput, result: RawPhoneCatalogResult) -> u32 {
    let expected = decide(input);
    u32::from(expected.status == 1 && expected == result)
}
