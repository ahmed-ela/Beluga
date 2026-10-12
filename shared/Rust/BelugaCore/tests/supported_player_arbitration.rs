//! Independent literal native-reference cases against the actual production crate.
//! Expected choices are literal native-reference cases, not production helpers.
use beluga_core::supported_player_arbitration::{arbitrate, ArbitrationInput, ArbitrationOutput};
use std::collections::BTreeSet;
use std::mem::{align_of, offset_of, size_of};

// (selected, browser, music, expected action, expected source/hold).
// selected: none/browser/Music 0/1/2; child: none/paused/playing/retry 0/1/2/3.
const CASES: [(u32, u32, u32, u32, u32); 48] = [
    (0, 0, 0, 2, 0), (0, 0, 1, 2, 2), (0, 0, 2, 2, 2), (0, 0, 3, 1, 0),
    (0, 1, 0, 2, 1), (0, 1, 1, 2, 1), (0, 1, 2, 2, 2), (0, 1, 3, 1, 0),
    (0, 2, 0, 2, 1), (0, 2, 1, 2, 1), (0, 2, 2, 2, 1), (0, 2, 3, 1, 0),
    (0, 3, 0, 1, 0), (0, 3, 1, 1, 0), (0, 3, 2, 1, 0), (0, 3, 3, 1, 0),
    (1, 0, 0, 2, 0), (1, 0, 1, 2, 2), (1, 0, 2, 2, 2), (1, 0, 3, 1, 1),
    (1, 1, 0, 2, 1), (1, 1, 1, 2, 1), (1, 1, 2, 2, 2), (1, 1, 3, 1, 1),
    (1, 2, 0, 2, 1), (1, 2, 1, 2, 1), (1, 2, 2, 2, 1), (1, 2, 3, 1, 1),
    (1, 3, 0, 1, 1), (1, 3, 1, 1, 1), (1, 3, 2, 1, 1), (1, 3, 3, 1, 1),
    (2, 0, 0, 2, 0), (2, 0, 1, 2, 2), (2, 0, 2, 2, 2), (2, 0, 3, 1, 2),
    (2, 1, 0, 2, 1), (2, 1, 1, 2, 2), (2, 1, 2, 2, 2), (2, 1, 3, 1, 2),
    (2, 2, 0, 2, 1), (2, 2, 1, 2, 1), (2, 2, 2, 2, 2), (2, 2, 3, 1, 2),
    (2, 3, 0, 1, 2), (2, 3, 1, 1, 2), (2, 3, 2, 1, 2), (2, 3, 3, 1, 2),
];

fn input(selected: u32, browser: u32, music: u32) -> ArbitrationInput {
    ArbitrationInput { abi_version: 1, selected_source: selected,
        browser_observation: browser, music_observation: music, reserved: 0 }
}

fn fields(output: ArbitrationOutput) -> (u32, u32, u32, u32) {
    (output.abi_version, output.action, output.primary_or_hold, output.reserved)
}

fn expect(selected: u32, browser: u32, music: u32, action: u32, source: u32) {
    assert_eq!(fields(arbitrate(input(selected, browser, music))), (1, action, source, 0),
        "input selected={selected}, browser={browser}, music={music}");
}

#[derive(Clone, Copy, Debug)]
enum RawField { Abi, Selected, Browser, Music, Reserved }

const RAW_FIELDS: [RawField; 5] = [RawField::Abi, RawField::Selected,
    RawField::Browser, RawField::Music, RawField::Reserved];

fn invalid_values(field: RawField) -> [u32; 3] {
    match field {
        RawField::Abi => [0, 2, u32::MAX],
        RawField::Selected => [3, 4, u32::MAX],
        RawField::Browser | RawField::Music => [4, 5, u32::MAX],
        RawField::Reserved => [1, 2, u32::MAX],
    }
}

fn replace(input: &mut ArbitrationInput, field: RawField, value: u32) {
    match field {
        RawField::Abi => input.abi_version = value,
        RawField::Selected => input.selected_source = value,
        RawField::Browser => input.browser_observation = value,
        RawField::Music => input.music_observation = value,
        RawField::Reserved => input.reserved = value,
    }
}

#[test]
fn literal_reference_covers_every_typed_input_exactly_once() {
    let mut inputs = BTreeSet::new();
    for &(selected, browser, music, _, _) in &CASES {
        assert!(inputs.insert((selected, browser, music)), "duplicate reference input");
    }
    assert_eq!(inputs.len(), 48);
    for selected in 0..3 {
        for browser in 0..4 {
            for music in 0..4 {
                assert!(inputs.contains(&(selected, browser, music)), "missing typed input");
            }
        }
    }
}

#[test]
fn literal_48_cases_match_original_native_priority() {
    for &(selected, browser, music, action, source) in &CASES {
        expect(selected, browser, music, action, source);
    }
}

#[test]
fn every_raw_closed_field_rejects_against_all_48_valid_bases() {
    let mut attempts = 0;
    for &(selected, browser, music, _, _) in &CASES {
        for field in RAW_FIELDS {
            for bad in invalid_values(field) {
                let mut raw = input(selected, browser, music);
                replace(&mut raw, field, bad);
                assert_eq!(fields(arbitrate(raw)), (1, 0, 0, 0),
                    "base=({selected},{browser},{music}), field={field:?}, invalid={bad}");
                attempts += 1;
            }
        }
    }
    assert_eq!(attempts, 720);
}

#[test]
fn every_distinct_pair_of_invalid_fields_stays_invalid() {
    let mut attempts = 0;
    for &(selected, browser, music, _, _) in &CASES {
        for (left_index, left) in RAW_FIELDS.iter().copied().enumerate() {
            for right in RAW_FIELDS.iter().copied().skip(left_index + 1) {
                for left_bad in invalid_values(left) {
                    for right_bad in invalid_values(right) {
                        let mut raw = input(selected, browser, music);
                        replace(&mut raw, left, left_bad);
                        replace(&mut raw, right, right_bad);
                        assert_eq!(fields(arbitrate(raw)), (1, 0, 0, 0),
                            "base=({selected},{browser},{music}), invalid {left:?}={left_bad}, {right:?}={right_bad}");
                        attempts += 1;
                    }
                }
            }
        }
    }
    assert_eq!(attempts, 4_320);
}

#[test]
fn every_valid_output_has_closed_action_source_and_zero_reserved() {
    for &(selected, browser, music, _, _) in &CASES {
        let output = arbitrate(input(selected, browser, music));
        assert_eq!(output.abi_version, 1);
        assert!(matches!(output.action, 1 | 2));
        assert!(output.primary_or_hold <= 2);
        assert_eq!(output.reserved, 0);
    }
}

#[test]
fn copied_layout_pins_every_field_offset_size_and_alignment() {
    assert_eq!(size_of::<ArbitrationInput>(), 20);
    assert_eq!(align_of::<ArbitrationInput>(), 4);
    assert_eq!(offset_of!(ArbitrationInput, abi_version), 0);
    assert_eq!(offset_of!(ArbitrationInput, selected_source), 4);
    assert_eq!(offset_of!(ArbitrationInput, browser_observation), 8);
    assert_eq!(offset_of!(ArbitrationInput, music_observation), 12);
    assert_eq!(offset_of!(ArbitrationInput, reserved), 16);
    assert_eq!(size_of::<ArbitrationOutput>(), 16);
    assert_eq!(align_of::<ArbitrationOutput>(), 4);
    assert_eq!(offset_of!(ArbitrationOutput, abi_version), 0);
    assert_eq!(offset_of!(ArbitrationOutput, action), 4);
    assert_eq!(offset_of!(ArbitrationOutput, primary_or_hold), 8);
    assert_eq!(offset_of!(ArbitrationOutput, reserved), 12);
}

#[test]
fn a_retry_from_either_child_beats_a_playing_successor() {
    expect(1, 3, 2, 1, 1);
    expect(2, 2, 3, 1, 2);
}

#[test]
fn retry_retains_selected_provider_even_when_absent() {
    expect(2, 3, 0, 1, 2);
    expect(1, 0, 3, 1, 1);
}

#[test]
fn selected_playing_music_beats_browser_playing_fallback() {
    expect(2, 2, 2, 2, 2);
}

#[test]
fn playing_tie_without_selection_bootstraps_browser() {
    expect(0, 2, 2, 2, 1);
}

#[test]
fn paused_selected_music_is_retained_over_browser_available_fallback() {
    expect(2, 1, 1, 2, 2);
}

#[test]
fn paused_tie_without_selection_bootstraps_browser() {
    expect(0, 1, 1, 2, 1);
}

#[test]
fn absence_publishes_none_and_does_not_retain_stale_selection() {
    expect(0, 0, 0, 2, 0);
    expect(1, 0, 0, 2, 0);
    expect(2, 0, 0, 2, 0);
}

#[test]
fn unsupported_abi_is_canonical_invalid_not_a_selection() {
    let mut raw = input(2, 2, 2);
    raw.abi_version = 2;
    assert_eq!(fields(arbitrate(raw)), (1, 0, 0, 0));
}

#[test]
fn reserved_input_is_canonical_invalid_not_a_selection() {
    let mut raw = input(2, 2, 2);
    raw.reserved = 1;
    assert_eq!(fields(arbitrate(raw)), (1, 0, 0, 0));
}

#[test]
fn unknown_selected_source_is_not_normalized_to_none() {
    let mut raw = input(0, 2, 2);
    raw.selected_source = 3;
    assert_eq!(fields(arbitrate(raw)), (1, 0, 0, 0));
}

#[test]
fn unknown_child_observation_is_not_normalized_to_retry() {
    let mut browser = input(1, 0, 0);
    browser.browser_observation = 4;
    assert_eq!(fields(arbitrate(browser)), (1, 0, 0, 0));
    let mut music = input(2, 0, 0);
    music.music_observation = 4;
    assert_eq!(fields(arbitrate(music)), (1, 0, 0, 0));
}
