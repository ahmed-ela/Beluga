#!/usr/bin/env ruby
require_relative 'artifact_support'

BelugaCoreArtifact.verify_source!
work = BelugaCoreArtifact.work_directory
mutants = [
  ['visibility-coupled-to-target', 'src/lib.rs', 'policy', 'visible: snapshot.has_started as u32,',
   'visible: (snapshot.has_started && snapshot.target_present) as u32,',
   'stable_visibility_survives_missing_target_and_session_churn'],
  ['unknown-flags-ignored', 'src/lib.rs', 'policy', 'flags & !KNOWN_FLAGS != 0', 'false',
   'every_unknown_bit_fails_closed'],
  ['command-admission-removed', 'src/lib.rs', 'policy', '!self.command_installed', 'false',
   'each_original_enabled_guard_is_required'],
  ['availability-departure-clears-media', 'src/host_lifecycle.rs', 'host_lifecycle',
   '(Self::Paired { active: None, media }, Applied),',
   '(Self::Paired { active: None, media: None }, Applied),',
   'availability_reconnect_does_not_replace_or_clear_old_media_owner'],
  ['stale-media-end-clears-owner', 'src/host_lifecycle.rs', 'host_lifecycle',
   'Some(token)) if media == token =>', 'Some(token)) if true =>',
   'stale_media_end_preserves_current_media_owner'],
  ['transaction-busy-admission-removed', 'src/handoff_transactions.rs', 'handoff_transactions',
   'if self.host.is_busy() { return output; }', 'if false { return output; }',
   'host_busy_rejects_replacement_without_revocation'],
  ['transaction-receipt-match-removed', 'src/handoff_transactions.rs', 'handoff_transactions',
   'if owned_receipt == receipt && owned_envelope == envelope =>',
   'if owned_envelope == envelope =>', 'host_completion_requires_exact_receipt_and_envelope'],
  ['transaction-envelope-match-removed', 'src/handoff_transactions.rs', 'handoff_transactions',
   'if owned_receipt == receipt && owned_envelope == envelope =>',
   'if owned_receipt == receipt =>', 'host_completion_requires_exact_receipt_and_envelope'],
  ['transaction-conflicting-reply-accepted', 'src/handoff_transactions.rs', 'handoff_transactions',
   '&& cached == result =>', '=>', 'cached_reply_is_idempotent_and_conflicting_reply_rejected'],
  ['transaction-revocation-removed', 'src/handoff_transactions.rs', 'handoff_transactions',
   'output.effects |= REVOKE_HOST; output.revoked_receipt = receipt.raw();', 'let _ = receipt;',
   'host_revocation_occurs_on_finish_replacement_and_clear'],
  ['transaction-timeout-reports-success', 'src/handoff_transactions.rs', 'handoff_transactions',
   "emit(&mut output, viewer.offer, Completion::Unknown);\n                self.viewer = None;",
   "emit(&mut output, viewer.offer, Completion::MacPaused);\n                self.viewer = None;",
   'clear_and_expiry_report_unknown_once_without_pause_effect'],
  ['offers-source-identity-bypassed', 'src/handoff_offers.rs', 'handoff_offers',
   '|| !identity.exact()', '|| false',
   'commit_header_and_current_primary_identity_are_independent'],
  ['offers-commit-identity-bypassed', 'src/handoff_offers.rs', 'handoff_offers',
   '&& event.commit.exact()', '&& true',
   'commit_header_and_current_primary_identity_are_independent'],
  ['offers-receive-auth-bypassed', 'src/handoff_offers.rs', 'handoff_offers',
   'Operation::Receive => if offer_valid(e.envelope) && event.commit.authorization()',
   'Operation::Receive => if offer_valid(e.envelope) && true',
   'wire_authorization_and_exact_numeric_identity_guard_slots'],
  ['offers-receive-sequence-burn-removed', 'src/handoff_offers.rs', 'handoff_offers',
   'self.highest_received = e.envelope.sequence;', ';',
   'rejected_new_sequence_burns_and_retires_before_late_validation'],
  ['offers-receive-old-retirement-removed', 'src/handoff_offers.rs', 'handoff_offers',
   "self.highest_received = e.envelope.sequence;\n                self.retire_received(&mut out);",
   'self.highest_received = e.envelope.sequence;',
   'rejected_new_sequence_burns_and_retires_before_late_validation'],
  ['offers-receive-sequence-replay-admitted', 'src/handoff_offers.rs', 'handoff_offers',
   'e.envelope.sequence > self.highest_received', 'e.envelope.sequence >= self.highest_received',
   'rejected_new_sequence_burns_and_retires_before_late_validation'],
  ['offers-sent-consuming-retirement-removed', 'src/handoff_offers.rs', 'handoff_offers',
   "self.retire_sent(&mut out);\n                    if fresh(self.sent_at, now)",
   'if fresh(self.sent_at, now)',
   'matching_consumption_cannot_revive_after_late_failure'],
  ['offers-received-consuming-retirement-removed', 'src/handoff_offers.rs', 'handoff_offers',
   "self.retire_received(out);\n        event.commit.authorization()", 'event.commit.authorization()',
   'matching_consumption_cannot_revive_after_late_failure'],
  ['offers-phone-sample-age-widened', 'src/handoff_offers.rs', 'handoff_offers',
   'now - f(e.phone_observed_at) <= 0.75', 'now - f(e.phone_observed_at) <= 2.0',
   'wrong_identity_and_invalid_phone_observation_do_not_consume'],
  ['offers-freshness-inclusive', 'src/handoff_offers.rs', 'handoff_offers',
   'let age = now - at; age >= 0.0 && age < 2.0', 'let age = now - at; age >= 0.0 && age <= 2.0',
   'actual_double_adjacent_boundaries_have_expected_decisions'],
  ['offers-deadline-inclusive', 'src/handoff_offers.rs', 'handoff_offers',
   '!(now < f(self.wire.deadline))', '!(now <= f(self.wire.deadline))',
   'actual_double_adjacent_boundaries_have_expected_decisions'],
  ['offers-timeline-tolerance-widened', 'src/handoff_offers.rs', 'handoff_offers',
   'let uncertainty = 2.0 * f(self.wire.rate) + 0.25;',
   'let uncertainty = 2.0 * f(self.wire.rate) + 1.25;',
   'exact_freshness_sample_deadline_and_uncertainty_boundaries'],
  ['offers-host-position-tolerance-widened', 'src/handoff_offers.rs', 'handoff_offers',
   '<= 2.0 + 2.0 * f(pending.wire.rate)', '<= 3.0 + 2.0 * f(pending.wire.rate)',
   'actual_double_adjacent_boundaries_have_expected_decisions'],
  ['offers-clear-resets-counters', 'src/handoff_offers.rs', 'handoff_offers',
   'Operation::ClearTransient => { self.retire_sent(&mut out); self.retire_received(&mut out); self.sent_at = None; self.received_at = None; }',
   'Operation::ClearTransient => { self.retire_sent(&mut out); self.retire_received(&mut out); self.sent_at = None; self.received_at = None; self.next_sent = 1; self.highest_received = 0; }',
   'clear_preserves_counters_and_send_capacity_cannot_wrap'],
  ['offers-sent-sequence-reused', 'src/handoff_offers.rs', 'handoff_offers',
   'self.next_sent += 1;', 'self.next_sent = 1;',
   'clear_preserves_counters_and_send_capacity_cannot_wrap'],
  ['offers-unknown-operation-clears-state', 'src/handoff_offers.rs', 'handoff_offers',
   '_ => return None,', '_ => Self::ClearTransient,',
   'unknown_operation_is_invalid_unchanged_without_retirement_or_success'],
  ['phone-foreign-clock-before-identity', 'src/youtube_handoff_operation.rs', 'youtube_handoff_operation',
   "if !identity.operation || !identity.page { return None; }\n        if let Some(failure) = self.observe_time(now) { return self.fail(failure); }",
   "if let Some(failure) = self.observe_time(now) { return self.fail(failure); }\n        if !identity.operation || !identity.page { return None; }",
   'foreign_identity_returns_before_time_but_matching_replay_observes_time'],
  ['phone-stale-sequence-before-clock', 'src/youtube_handoff_operation.rs', 'youtube_handoff_operation',
   "if let Some(failure) = self.observe_time(now) { return self.fail(failure); }\n        if self.terminal() || sequence <= self.sequence { return None; }",
   "if self.terminal() || sequence <= self.sequence { return None; }\n        if let Some(failure) = self.observe_time(now) { return self.fail(failure); }",
   'foreign_identity_returns_before_time_but_matching_replay_observes_time'],
  ['phone-repeated-begin-reservation', 'src/youtube_handoff_operation.rs', 'youtube_handoff_operation',
   'if self.mac_pause != MacPause::NotRequested || !self.current(identity, now) { return ProductOutput::boolean(false); }',
   'if !self.current(identity, now) { return ProductOutput::boolean(false); }',
   'only_reserved_correlated_completion_moves_and_cannot_be_replayed'],
  ['phone-original-proof-age-refreshed', 'src/youtube_handoff_operation.rs', 'youtube_handoff_operation',
   '&& f(now) >= f(owned.observed_at) && f(now) - f(owned.observed_at) <= 0.75',
   '&& f(now) >= f(last) && f(now) - f(last) <= 0.75',
   'original_proof_age_never_renews_but_completion_uses_latest_sample'],
  ['phone-paused-outcome-forgotten', 'src/youtube_handoff_operation.rs', 'youtube_handoff_operation',
   "self.mac_pause = MacPause::Paused;\n                        if !(self.visible",
   "self.mac_pause = MacPause::Pending;\n                        if !(self.visible",
   'successful_native_pause_is_retained_even_when_phone_freshness_fails'],
  ['phone-pending-failure-keeps-reservation', 'src/youtube_handoff_operation.rs', 'youtube_handoff_operation',
   'if self.mac_pause == MacPause::Pending { self.mac_pause = MacPause::Unknown; }',
   'if self.mac_pause == MacPause::Pending { self.mac_pause = MacPause::NotRequested; }',
   'every_pending_failure_retains_proof_but_becomes_unknown_terminal']
]
mutants.each do |name, path, suite, original, changed, test|
  production = File.binread(File.join(BelugaCoreArtifact::CRATE, path))
  raise "Mutation anchor not unique: #{name}" unless production.scan(original).size == 1
  Dir.mktmpdir("mutant-#{name}-", work) do |copy|
    %w[Cargo.toml Cargo.lock rust-toolchain.toml src tests].each do |path|
      FileUtils.cp_r(File.join(BelugaCoreArtifact::CRATE, path), File.join(copy, path))
    end
    File.binwrite(File.join(copy, path), production.sub(original, changed))
    env = BelugaCoreArtifact.environment(File.join(copy, 'target'))
    output, error, status = Open3.capture3(env, BelugaCoreArtifact::CARGO, 'test', '--offline', '--locked',
      '--test', suite, test, '--', '--exact', '--test-threads=1', chdir: copy)
    combined = output + error
    puts combined
    raise "Mutant #{name} compiled unsuccessfully; not a behavioral oracle" if combined.include?('could not compile')
    raise "Mutant #{name} survived or lacked an assertion failure" unless status.exitstatus == 101 &&
      combined.include?('assertion `left == right` failed') && combined.include?("#{test} ... FAILED") &&
      combined.include?('1 failed')
    puts "Behavioral mutation rejected: #{name}"
    puts "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed"
  end
end
puts "BelugaCore mutation oracles PASS: #{mutants.size} assertion-failing mutants"
puts "BELUGA_CORE_MUTATIONS_PASS cases=#{mutants.size}"
