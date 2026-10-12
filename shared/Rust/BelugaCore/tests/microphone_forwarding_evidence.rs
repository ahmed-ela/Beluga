//! Standalone copied-policy controls only. No native audio or ownership authority.
#![forbid(unsafe_code)]

use beluga_core::microphone_forwarding_evidence as evidence;

#[cfg(test)]
mod independent_controls {
    use super::evidence::*;

    fn progress(flags: u32, callbacks: u64, frames: u64) -> Progress {
        Progress {
            queue_running: flags & 1 != 0,
            enqueue_failure_count: if flags & 2 != 0 { 0 } else { 1 },
            successful_pull_count: u64::from(flags & 4 != 0),
            successful_frame_count: if flags & 8 != 0 { frames } else { 0 },
            post_start_callback_count: callbacks,
        }
    }

    #[test]
    fn both_health_readiness_votes_are_independently_required() {
        // Keep both counters growing when queue/failure/pull readiness fails.
        // Those readiness votes cannot be masked by non-advancing counters.
        for before in 0..16 {
            for after in 0..16 {
                let previous = progress(before, 10, 100);
                for (callbacks, frames) in [(9, 99), (10, 100), (11, 101)] {
                    let current = progress(after, callbacks, frames);
                    let expected = before == 15 && after == 15
                        && callbacks == 11 && frames == 101;
                    assert_eq!(proves_continuing_health(previous, current), expected,
                        "previous_flags={before}, current_flags={after}, callbacks={callbacks}, frames={frames}");
                }
            }
        }
    }

    fn watermark(values: [Option<u64>; 4]) -> Watermark {
        Watermark {
            packets_received: values[0], bytes_received: values[1],
            jitter_buffer_emitted_count: values[2], total_samples_received: values[3],
        }
    }

    fn values(mut code: usize) -> [Option<u64>; 4] {
        let choices = [None, Some(0), Some(1), Some(u64::MAX)];
        let mut result = [None; 4];
        for field in &mut result {
            *field = choices[code % 4];
            code /= 4;
        }
        result
    }

    #[test]
    fn full_optional_counter_domain_keeps_independent_and_guarded_votes() {
        for old_code in 0..256 {
            let old = values(old_code);
            let previous = watermark(old);
            for new_code in 0..256 {
                let new = values(new_code);
                let current = watermark(new);
                let continuous = (0..4).all(|i| match (old[i], new[i]) {
                    (Some(a), Some(b)) => b >= a,
                    _ => true,
                });
                let advanced = (0..2).any(|i| match (old[i], new[i]) {
                    (Some(a), Some(b)) => b > a,
                    _ => false,
                });
                let mut maxima = [None; 4];
                for i in 0..4 {
                    maxima[i] = match (old[i], new[i]) {
                        (Some(a), Some(b)) => Some(if a >= b { a } else { b }),
                        (Some(a), None) => Some(a),
                        (None, value) => value,
                    };
                }
                assert_eq!(current.is_continuous(Some(previous)), continuous);
                assert_eq!(current.advances(Some(previous)), advanced);
                assert_eq!(current.preserving_maximums(Some(previous)), watermark(maxima));
                let before = WatermarkState { retained: Some(previous) };
                let result = watermark_transition(before, WatermarkEvent::Observe(Some(current)));
                assert_eq!(result.continuous, continuous);
                assert_eq!(result.did_advance, continuous && advanced);
                assert_eq!(result.state.retained,
                    Some(if continuous { watermark(maxima) } else { previous }));
            }
        }
    }

    #[test]
    fn freshness_clock_request_matches_original_short_circuit_predicate() {
        for deadline in [None, Some(0), Some(10), Some(u64::MAX)] {
            for advancement_count in [0, 1, u64::MAX] {
                for consecutive_stale_samples in [-1, 0, 1, 2, 3, i64::MAX] {
                    let state = FreshnessState {
                        deadline_nanoseconds: deadline, advancement_count,
                        consecutive_stale_samples,
                    };
                    let eligible = deadline.is_some() && advancement_count > 0
                        && consecutive_stale_samples < 3;
                    assert_eq!(freshness(state, FreshnessEvent::Observe {
                        maximum_stale_samples: 3, now_nanoseconds: None,
                    }), if eligible { FreshnessResult::NeedsNow } else { FreshnessResult::NotFresh });
                    for now in [0, 9, 10, 11, u64::MAX] {
                        let expected = eligible && deadline.is_some_and(|end| now < end);
                        assert_eq!(freshness(state, FreshnessEvent::Observe {
                            maximum_stale_samples: 3, now_nanoseconds: Some(now),
                        }), if expected { FreshnessResult::Fresh } else { FreshnessResult::NotFresh });
                    }
                }
            }
        }
    }

    #[test]
    fn raw_positive_decisions_cannot_silently_become_false_or_no_change() {
        let current = RawProgress {
            queue_running: 1, reserved: 0, post_start_callback_count: 2,
            successful_pull_count: 1, successful_frame_count: 480,
            enqueue_failure_count: 0,
        };
        assert_eq!(beluga_core::beluga_core_microphone_forwarding_readiness_decide(RawReadinessFacts {
            abi_version: 1, reserved: 0, current,
            previous_present: 1, previous_reserved: 0,
            previous: RawProgress {
                post_start_callback_count: 1, successful_frame_count: 479, ..current
            },
        }), RawReadinessResult {
            abi_version: 1, status: 1, ready: 1, continuing: 1,
        });

        let present = |value| OptionalU64 { present: 1, reserved: 0, value };
        let old = RawWatermarkState {
            abi_version: 1, reserved: 0,
            retained: RawWatermark {
                present: 1, reserved: 0,
                fields: [present(10), present(100), present(20), present(200)],
            },
        };
        assert_eq!(beluga_core::beluga_core_microphone_forwarding_watermark_step(old, RawWatermarkEvent {
            abi_version: 1, reserved: 0,
            current: RawWatermark {
                present: 1, reserved: 0,
                fields: [present(11), present(101), OptionalU64::default(), OptionalU64::default()],
            },
        }), RawWatermarkResult {
            state: RawWatermarkState {
                abi_version: 1, reserved: 0,
                retained: RawWatermark {
                    present: 1, reserved: 0,
                    fields: [present(11), present(101), present(20), present(200)],
                },
            },
            status: 1, continuous: 1, did_advance: 1, reserved: 0,
        });

        assert_eq!(beluga_core::beluga_core_microphone_forwarding_freshness_decide(RawFreshnessState {
            abi_version: 1, reserved: 0, advancement_count: 1,
            consecutive_stale_samples: 0, deadline: present(100),
        }, RawFreshnessEvent {
            abi_version: 1, reserved: 0, maximum_stale_samples: 3, now: present(99),
        }), RawFreshnessResult {
            abi_version: 1, status: 1, fresh: 1, reserved: 0,
        });
    }
}

#[cfg(test)]
mod result_correlation_controls {
    use super::evidence::*;
    use beluga_core::{
        beluga_core_microphone_forwarding_readiness_result_is_valid as ready_valid,
        beluga_core_microphone_forwarding_watermark_result_is_valid as mark_valid,
        beluga_core_microphone_forwarding_freshness_result_is_valid as fresh_valid,
    };

    fn present(value: u64) -> OptionalU64 { OptionalU64 { present: 1, reserved: 0, value } }
    fn ready_facts() -> RawReadinessFacts {
        RawReadinessFacts {
            abi_version: 1, reserved: 0, previous_present: 1, previous_reserved: 0,
            previous: RawProgress { queue_running: 1, reserved: 0, post_start_callback_count: 1,
                successful_pull_count: 1, successful_frame_count: 479, enqueue_failure_count: 0 },
            current: RawProgress { queue_running: 1, reserved: 0, post_start_callback_count: 2,
                successful_pull_count: 1, successful_frame_count: 480, enqueue_failure_count: 0 },
        }
    }
    fn watermark_pair() -> (RawWatermarkState, RawWatermarkEvent, RawWatermarkResult) {
        let before = RawWatermarkState { abi_version: 1, reserved: 0,
            retained: RawWatermark { present: 1, reserved: 0,
                fields: [present(10), present(100), present(20), present(200)] } };
        let event = RawWatermarkEvent { abi_version: 1, reserved: 0,
            current: RawWatermark { present: 1, reserved: 0,
                fields: [present(11), present(101), OptionalU64::default(), OptionalU64::default()] } };
        let expected = RawWatermarkResult {
            state: RawWatermarkState { abi_version: 1, reserved: 0,
                retained: RawWatermark { present: 1, reserved: 0,
                    fields: [present(11), present(101), present(20), present(200)] } },
            status: 1, continuous: 1, did_advance: 1, reserved: 0,
        };
        (before, event, expected)
    }
    fn freshness_pair() -> (RawFreshnessState, RawFreshnessEvent) {
        (RawFreshnessState { abi_version: 1, reserved: 0, advancement_count: 1,
            consecutive_stale_samples: 0, deadline: present(100) },
         RawFreshnessEvent { abi_version: 1, reserved: 0, maximum_stale_samples: 3,
            now: OptionalU64 { present: 0, reserved: 0, value: u64::MAX } })
    }

    #[test]
    fn readiness_correlation_accepts_literal_true_and_legitimate_false_results() {
        let facts = ready_facts();
        let expected = RawReadinessResult { abi_version: 1, status: 1, ready: 1, continuing: 1 };
        assert_eq!(readiness_decide(facts), expected);
        assert_eq!(ready_valid(facts, expected), 1);
        let mut absent = facts; absent.previous_present = 0;
        absent.previous.queue_running = 9; absent.previous.reserved = 7;
        let no_health = RawReadinessResult { continuing: 0, ..expected };
        assert_eq!(readiness_decide(absent), no_health);
        assert_eq!(ready_valid(absent, no_health), 1);
        let mut unready = facts; unready.current.successful_pull_count = 0;
        let false_vote = RawReadinessResult { ready: 0, continuing: 0, ..expected };
        assert_eq!(readiness_decide(unready), false_vote);
        assert_eq!(ready_valid(unready, false_vote), 1);
    }

    #[test]
    fn readiness_correlation_rejects_each_field_coherent_corruption_and_invalid_match() {
        let facts = ready_facts();
        let expected = RawReadinessResult { abi_version: 1, status: 1, ready: 1, continuing: 1 };
        for bad in [RawReadinessResult { abi_version: 2, ..expected },
                    RawReadinessResult { status: 0, ..expected },
                    RawReadinessResult { status: 2, ..expected },
                    RawReadinessResult { ready: 0, ..expected },
                    RawReadinessResult { continuing: 0, ..expected },
                    RawReadinessResult { ready: 0, continuing: 0, ..expected }] {
            assert_eq!(ready_valid(facts, bad), 0, "bad={bad:?}");
        }
        for mode in 0..8 {
            let mut bad = facts;
            match mode {
                0 => bad.abi_version = 2, 1 => bad.reserved = 1,
                2 => bad.current.queue_running = 2, 3 => bad.current.reserved = 1,
                4 => bad.previous_present = 2, 5 => bad.previous_reserved = 1,
                6 => bad.previous.queue_running = 2, _ => bad.previous.reserved = 1,
            }
            let invalid = RawReadinessResult { abi_version: 1, status: 0, ready: 0, continuing: 0 };
            assert_eq!(readiness_decide(bad), invalid);
            assert_eq!(ready_valid(bad, invalid), 0);
            assert_eq!(ready_valid(bad, RawReadinessResult { status: 1, ..invalid }), 0);
        }
    }

    #[test]
    fn watermark_correlation_accepts_literal_transition_and_exact_opaque_retention() {
        let (before, event, expected) = watermark_pair();
        assert_eq!(watermark_step(before, event), expected);
        assert_eq!(mark_valid(before, event, expected), 1);
        let mut regressed = event; regressed.current.fields[0].value = 9;
        let unchanged = RawWatermarkResult { state: before, status: 1, continuous: 0, did_advance: 0, reserved: 0 };
        assert_eq!(watermark_step(before, regressed), unchanged);
        assert_eq!(mark_valid(before, regressed, unchanged), 1);
        let opaque = RawWatermarkState { abi_version: 1, reserved: 0,
            retained: RawWatermark { present: 0, reserved: 0,
                fields: [OptionalU64 { present: 9, reserved: 7, value: u64::MAX }; 4] } };
        let absent = RawWatermarkEvent { abi_version: 1, reserved: 0, current: opaque.retained };
        let retained = RawWatermarkResult { state: opaque, ..unchanged };
        assert_eq!(watermark_step(opaque, absent), retained);
        assert_eq!(mark_valid(opaque, absent, retained), 1);
        let mut changed = retained; changed.state.retained.fields[3].value = 0;
        assert_eq!(mark_valid(opaque, absent, changed), 0);
    }

    #[test]
    fn watermark_correlation_rejects_all_nested_fields_coherent_noop_and_invalid_match() {
        let (before, event, expected) = watermark_pair();
        for mode in 0..20 {
            let mut bad = expected;
            match mode {
                0 => bad.state.abi_version = 2, 1 => bad.state.reserved = 1,
                2 => bad.state.retained.present = 0, 3 => bad.state.retained.reserved = 1,
                4..=15 => {
                    let field = &mut bad.state.retained.fields[(mode - 4) / 3];
                    match (mode - 4) % 3 { 0 => field.present = 0, 1 => field.reserved = 1,
                        _ => field.value = field.value.wrapping_add(1) }
                }
                16 => bad.status = 0, 17 => bad.continuous = 0, 18 => bad.did_advance = 0,
                _ => bad.reserved = 1,
            }
            assert_eq!(mark_valid(before, event, bad), 0, "mode={mode}");
        }
        let plausible_noop = RawWatermarkResult { state: before, status: 1, continuous: 0, did_advance: 0, reserved: 0 };
        assert_eq!(mark_valid(before, event, plausible_noop), 0);
        assert_eq!(mark_valid(before, event, RawWatermarkResult { status: 2, ..expected }), 0);
        for mode in 0..8 {
            let mut old = before; let mut input = event;
            match mode {
                0 => old.abi_version = 2, 1 => old.reserved = 1,
                2 => old.retained.present = 2, 3 => old.retained.fields[0].reserved = 1,
                4 => input.abi_version = 2, 5 => input.reserved = 1,
                6 => input.current.present = 2, _ => input.current.fields[0].present = 2,
            }
            let invalid = RawWatermarkResult { state: old, status: 0, continuous: 0, did_advance: 0, reserved: 0 };
            assert_eq!(watermark_step(old, input), invalid);
            assert_eq!(mark_valid(old, input, invalid), 0);
            assert_eq!(mark_valid(old, input, RawWatermarkResult { status: 1, ..invalid }), 0);
        }
    }

    #[test]
    fn freshness_correlation_accepts_literal_fresh_notfresh_and_needsnow() {
        let (before, event) = freshness_pair();
        let needs = RawFreshnessResult { abi_version: 1, status: 2, fresh: 0, reserved: 0 };
        assert_eq!(freshness_decide(before, event), needs);
        assert_eq!(fresh_valid(before, event, needs), 1);
        for (now, fresh) in [(99, 1), (100, 0), (u64::MAX, 0)] {
            let supplied = RawFreshnessEvent { now: present(now), ..event };
            let expected = RawFreshnessResult { abi_version: 1, status: 1, fresh, reserved: 0 };
            assert_eq!(freshness_decide(before, supplied), expected);
            assert_eq!(fresh_valid(before, supplied, expected), 1);
        }
        let no_deadline = RawFreshnessState { deadline: OptionalU64::default(), ..before };
        let not_fresh = RawFreshnessResult { abi_version: 1, status: 1, fresh: 0, reserved: 0 };
        assert_eq!(freshness_decide(no_deadline, event), not_fresh);
        assert_eq!(fresh_valid(no_deadline, event, not_fresh), 1);
    }

    #[test]
    fn freshness_correlation_rejects_each_field_coherent_clockplan_and_invalid_match() {
        let (before, event) = freshness_pair();
        let needs = RawFreshnessResult { abi_version: 1, status: 2, fresh: 0, reserved: 0 };
        for bad in [RawFreshnessResult { abi_version: 2, ..needs },
                    RawFreshnessResult { status: 1, ..needs },
                    RawFreshnessResult { status: 0, ..needs },
                    RawFreshnessResult { status: 3, ..needs },
                    RawFreshnessResult { fresh: 1, ..needs },
                    RawFreshnessResult { reserved: 1, ..needs },
                    RawFreshnessResult { status: 1, fresh: 1, ..needs }] {
            assert_eq!(fresh_valid(before, event, bad), 0, "bad={bad:?}");
        }
        let supplied = RawFreshnessEvent { now: present(99), ..event };
        assert_eq!(fresh_valid(before, supplied, needs), 0);
        let not_fresh = RawFreshnessResult { abi_version: 1, status: 1, fresh: 0, reserved: 0 };
        assert_eq!(fresh_valid(before, supplied, not_fresh), 0);
        for mode in 0..8 {
            let mut old = before; let mut input = event;
            match mode {
                0 => old.abi_version = 2, 1 => old.reserved = 1,
                2 => old.deadline.present = 2, 3 => old.deadline.reserved = 1,
                4 => input.abi_version = 2, 5 => input.reserved = 1,
                6 => input.now.present = 2, _ => input.now.reserved = 1,
            }
            let invalid = RawFreshnessResult { abi_version: 1, status: 0, fresh: 0, reserved: 0 };
            assert_eq!(freshness_decide(old, input), invalid);
            assert_eq!(fresh_valid(old, input, invalid), 0);
            assert_eq!(fresh_valid(old, input, RawFreshnessResult { status: 1, ..invalid }), 0);
            assert_eq!(fresh_valid(old, input, needs), 0);
        }
    }
}
