//! Stateless supported browser/Music arbitration over copied observations.
//! Native owns fetch generations, observations, snapshots, tokens, and all effects.
#![forbid(unsafe_code)]

use core::mem::size_of;

const ABI_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Source {
    Browser,
    Music,
}

impl Source {
    fn decode_optional(raw: u32) -> Option<Option<Self>> {
        match raw {
            0 => Some(None),
            1 => Some(Some(Self::Browser)),
            2 => Some(Some(Self::Music)),
            _ => None,
        }
    }

    fn encode_optional(value: Option<Self>) -> u32 {
        match value {
            None => 0,
            Some(Self::Browser) => 1,
            Some(Self::Music) => 2,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ChildObservation {
    NoActiveMedia,
    SnapshotNotPlaying,
    SnapshotPlaying,
    Retry,
}

impl ChildObservation {
    fn decode(raw: u32) -> Option<Self> {
        match raw {
            0 => Some(Self::NoActiveMedia),
            1 => Some(Self::SnapshotNotPlaying),
            2 => Some(Self::SnapshotPlaying),
            3 => Some(Self::Retry),
            _ => None,
        }
    }

    fn is_available(self) -> bool {
        matches!(self, Self::SnapshotNotPlaying | Self::SnapshotPlaying)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Facts {
    selected: Option<Source>,
    browser: ChildObservation,
    music: ChildObservation,
}

impl Facts {
    fn observation(self, source: Source) -> ChildObservation {
        match source {
            Source::Browser => self.browser,
            Source::Music => self.music,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Decision {
    RetryClearingAuthority { selection_hold: Option<Source> },
    PublishCatalog { primary: Option<Source> },
}

fn evaluate(facts: Facts) -> Decision {
    if facts.browser == ChildObservation::Retry || facts.music == ChildObservation::Retry {
        return Decision::RetryClearingAuthority { selection_hold: facts.selected };
    }
    let primary = if let Some(selected) = facts.selected.filter(|source| {
        facts.observation(*source) == ChildObservation::SnapshotPlaying
    }) {
        Some(selected)
    } else if facts.browser == ChildObservation::SnapshotPlaying {
        Some(Source::Browser)
    } else if facts.music == ChildObservation::SnapshotPlaying {
        Some(Source::Music)
    } else if let Some(selected) = facts.selected.filter(|source| {
        facts.observation(*source).is_available()
    }) {
        Some(selected)
    } else if facts.browser.is_available() {
        Some(Source::Browser)
    } else if facts.music.is_available() {
        Some(Source::Music)
    } else {
        None
    };
    Decision::PublishCatalog { primary }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ArbitrationInput {
    pub abi_version: u32,
    pub selected_source: u32,
    pub browser_observation: u32,
    pub music_observation: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ArbitrationOutput {
    pub abi_version: u32,
    // 0 = invalid bridge input; 1 = retry/clear; 2 = publish catalog.
    pub action: u32,
    // 0 = none; 1 = browser; 2 = music. A retry carries the unchanged hold.
    pub primary_or_hold: u32,
    pub reserved: u32,
}

const _: [(); 20] = [(); size_of::<ArbitrationInput>()];
const _: [(); 16] = [(); size_of::<ArbitrationOutput>()];

fn invalid_output() -> ArbitrationOutput {
    ArbitrationOutput { abi_version: ABI_VERSION, action: 0, primary_or_hold: 0, reserved: 0 }
}

// The foreign symbol belongs in lib.rs, outside this forbid(unsafe_code) module.
pub fn arbitrate(input: ArbitrationInput) -> ArbitrationOutput {
    if input.abi_version != ABI_VERSION || input.reserved != 0 {
        return invalid_output();
    }
    let Some(selected) = Source::decode_optional(input.selected_source) else { return invalid_output(); };
    let Some(browser) = ChildObservation::decode(input.browser_observation) else { return invalid_output(); };
    let Some(music) = ChildObservation::decode(input.music_observation) else { return invalid_output(); };
    let (action, primary_or_hold) = match evaluate(Facts { selected, browser, music }) {
        Decision::RetryClearingAuthority { selection_hold } => (1, Source::encode_optional(selection_hold)),
        Decision::PublishCatalog { primary } => (2, Source::encode_optional(primary)),
    };
    ArbitrationOutput { abi_version: ABI_VERSION, action, primary_or_hold, reserved: 0 }
}
