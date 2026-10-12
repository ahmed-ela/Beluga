#!/usr/bin/env ruby
require_relative 'artifact_support'

# Importable text/process decoder only; requiring this file never runs Cargo or creates work.
module BelugaCoreUpdaterMutationOracle
  CONTROLS = [
    ["UO-M01","src/update_operation.rs","update_operation","if raw.reserved != 0 || raw.reserved_tail != 0 { return None; } // UO-M01","if false { return None; } // UO-M01","updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all"],
    ["UO-M02","src/update_operation.rs","update_operation","if facts.iter().any(|value| *value > 1) { return None; } // UO-M02","if false { return None; } // UO-M02","updater_operation_malformed_event_domains_unknown_opcodes_and_unused_facts_preserve_state"],
    ["UO-M03","src/update_operation.rs","update_operation","_ => return None, // UO-M03","_ => return Some(Self::QueryPermitsFenceRelease), // UO-M03","updater_operation_malformed_event_domains_unknown_opcodes_and_unused_facts_preserve_state"],
    ["UO-M04","src/update_operation.rs","update_operation","if facts[used..].iter().any(|value| *value != 0) { return None; } // UO-M04","if false { return None; } // UO-M04","updater_operation_malformed_event_domains_unknown_opcodes_and_unused_facts_preserve_state"],
    ["UO-M05","src/update_operation.rs","update_operation","if raw.abi_version != ABI_VERSION || raw.reserved != 0 || raw.reserved_tail != 0 { return None; } // UO-M05","if false { return None; } // UO-M05","updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all"],
    ["UO-M06","src/update_operation.rs","update_operation","if abi_version != ABI_VERSION { return invalid; } // UO-M06","if false { return invalid; } // UO-M06","updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all"],
    ["UO-M07","src/update_operation.rs","update_operation","_ => return None, // UO-M07","_ => Stage::ReadyToRelease, // UO-M07","updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all"],
    ["UO-M08","src/update_operation.rs","update_operation","let presence = |value| match value { 0 => Some(Presence::Absent), 1 => Some(Presence::Present), _ => None }; // UO-M08","let presence = |value| match value { 0 => Some(Presence::Absent), 1 => Some(Presence::Present), _ => Some(Presence::Present) }; // UO-M08","updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all"],
    ["UO-M09","src/update_operation.rs","update_operation","let freshness = |value| match value { 0 => Some(Freshness::NotFresh), 1 => Some(Freshness::Fresh), _ => None }; // UO-M09","let freshness = |value| match value { 0 => Some(Freshness::NotFresh), 1 => Some(Freshness::Fresh), _ => Some(Freshness::Fresh) }; // UO-M09","updater_operation_malformed_abi_state_and_reserved_preserve_exact_old_state_deny_all"],
    ["UO-B01-1","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.stage != Stage::Prepared || self.broker != Presence::Absent // UO-B01","if false || self.stage != Stage::Prepared || self.broker != Presence::Absent // UO-B01","updater_operation_literal_broker_binding_is_once_prepared_and_exact"],
    ["UO-B01-2","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.stage != Stage::Prepared || self.broker != Presence::Absent // UO-B01","if binding != BindingMatch::Exact || false || self.broker != Presence::Absent // UO-B01","updater_operation_literal_broker_binding_is_once_prepared_and_exact"],
    ["UO-B01-3","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.stage != Stage::Prepared || self.broker != Presence::Absent // UO-B01","if binding != BindingMatch::Exact || self.stage != Stage::Prepared || false // UO-B01","updater_operation_literal_broker_binding_is_once_prepared_and_exact"],
    ["UO-B02-1","src/update_operation.rs","update_operation","|| valid != NativeValidity::Valid || version != NativeEquality::Equal || build != NativeEquality::Equal { return self.denied(); } // UO-B02","|| false || version != NativeEquality::Equal || build != NativeEquality::Equal { return self.denied(); } // UO-B02","updater_operation_literal_broker_binding_is_once_prepared_and_exact"],
    ["UO-B02-2","src/update_operation.rs","update_operation","|| valid != NativeValidity::Valid || version != NativeEquality::Equal || build != NativeEquality::Equal { return self.denied(); } // UO-B02","|| valid != NativeValidity::Valid || false || build != NativeEquality::Equal { return self.denied(); } // UO-B02","updater_operation_literal_broker_binding_is_once_prepared_and_exact"],
    ["UO-B02-3","src/update_operation.rs","update_operation","|| valid != NativeValidity::Valid || version != NativeEquality::Equal || build != NativeEquality::Equal { return self.denied(); } // UO-B02","|| valid != NativeValidity::Valid || version != NativeEquality::Equal || false { return self.denied(); } // UO-B02","updater_operation_literal_broker_binding_is_once_prepared_and_exact"],
    ["UO-C01-1","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.candidate != Presence::Absent // UO-C01","if false || self.candidate != Presence::Absent // UO-C01","updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage"],
    ["UO-C01-2","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.candidate != Presence::Absent // UO-C01","if binding != BindingMatch::Exact || false // UO-C01","updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage"],
    ["UO-C02-1","src/update_operation.rs","update_operation","|| !matches!(self.stage, Stage::Prepared | Stage::PossiblyArmed) // UO-C02","|| false // UO-C02","updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage"],
    ["UO-C03-1","src/update_operation.rs","update_operation","|| valid != NativeValidity::Valid || build != BuildProgress::Newer || executable != NativeDifference::Different { return self.denied(); } // UO-C03","|| false || build != BuildProgress::Newer || executable != NativeDifference::Different { return self.denied(); } // UO-C03","updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage"],
    ["UO-C03-2","src/update_operation.rs","update_operation","|| valid != NativeValidity::Valid || build != BuildProgress::Newer || executable != NativeDifference::Different { return self.denied(); } // UO-C03","|| valid != NativeValidity::Valid || false || executable != NativeDifference::Different { return self.denied(); } // UO-C03","updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage"],
    ["UO-C03-3","src/update_operation.rs","update_operation","|| valid != NativeValidity::Valid || build != BuildProgress::Newer || executable != NativeDifference::Different { return self.denied(); } // UO-C03","|| valid != NativeValidity::Valid || build != BuildProgress::Newer || false { return self.denied(); } // UO-C03","updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage"],
    ["UO-A01-1","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.stage != Stage::Prepared || self.broker != Presence::Present { return self.denied(); } // UO-A01","if false || self.stage != Stage::Prepared || self.broker != Presence::Present { return self.denied(); } // UO-A01","updater_operation_literal_arming_requires_exact_binding_and_bound_broker"],
    ["UO-A01-2","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.stage != Stage::Prepared || self.broker != Presence::Present { return self.denied(); } // UO-A01","if binding != BindingMatch::Exact || false || self.broker != Presence::Present { return self.denied(); } // UO-A01","updater_operation_literal_arming_requires_exact_binding_and_bound_broker"],
    ["UO-A01-3","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.stage != Stage::Prepared || self.broker != Presence::Present { return self.denied(); } // UO-A01","if binding != BindingMatch::Exact || self.stage != Stage::Prepared || false { return self.denied(); } // UO-A01","updater_operation_literal_arming_requires_exact_binding_and_bound_broker"],
    ["UO-I01-1","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.stage == Stage::Prepared || self.broker != Presence::Present // UO-I01","if false || self.stage == Stage::Prepared || self.broker != Presence::Present // UO-I01","updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion"],
    ["UO-I01-2","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.stage == Stage::Prepared || self.broker != Presence::Present // UO-I01","if binding != BindingMatch::Exact || false || self.broker != Presence::Present // UO-I01","updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion"],
    ["UO-I01-3","src/update_operation.rs","update_operation","if binding != BindingMatch::Exact || self.stage == Stage::Prepared || self.broker != Presence::Present // UO-I01","if binding != BindingMatch::Exact || self.stage == Stage::Prepared || false // UO-I01","updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion"],
    ["UO-I02-1","src/update_operation.rs","update_operation","|| self.installed != Freshness::NotFresh || self.candidate != Presence::Present || candidate != NativeEquality::Equal { return self.denied(); } // UO-I02","|| false || self.candidate != Presence::Present || candidate != NativeEquality::Equal { return self.denied(); } // UO-I02","updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion"],
    ["UO-I02-2","src/update_operation.rs","update_operation","|| self.installed != Freshness::NotFresh || self.candidate != Presence::Present || candidate != NativeEquality::Equal { return self.denied(); } // UO-I02","|| self.installed != Freshness::NotFresh || false || candidate != NativeEquality::Equal { return self.denied(); } // UO-I02","updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion"],
    ["UO-I02-3","src/update_operation.rs","update_operation","|| self.installed != Freshness::NotFresh || self.candidate != Presence::Present || candidate != NativeEquality::Equal { return self.denied(); } // UO-I02","|| self.installed != Freshness::NotFresh || self.candidate != Presence::Present || false { return self.denied(); } // UO-I02","updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion"],
    ["UO-I03","src/update_operation.rs","update_operation","if self.stage == Stage::PossiblyArmed { self.stage = Stage::InstalledVerified; } // UO-I03","if self.stage == Stage::PossiblyArmed { self.stage = Stage::ReadyToRelease; } // UO-I03","updater_operation_literal_complete_accepted_trace_is_not_runtime_authority"],
    ["UO-I04","src/update_operation.rs","update_operation","self.readiness = Freshness::NotFresh; // UO-I04","self.readiness = self.readiness; // UO-I04","updater_operation_literal_install_clears_only_ephemeral_readiness_and_challenge"],
    ["UO-I05","src/update_operation.rs","update_operation","self.challenge = Presence::Absent; // UO-I05","self.challenge = self.challenge; // UO-I05","updater_operation_literal_install_clears_only_ephemeral_readiness_and_challenge"],
    ["UO-H01a-1","src/update_operation.rs","update_operation","if self.installed != Freshness::Fresh || self.readiness != Freshness::NotFresh","if false || self.readiness != Freshness::NotFresh","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-H01a-2","src/update_operation.rs","update_operation","if self.installed != Freshness::Fresh || self.readiness != Freshness::NotFresh","if self.installed != Freshness::Fresh || false","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-H01b-1","src/update_operation.rs","update_operation","|| self.challenge != Presence::Absent || self.candidate != Presence::Present { return self.denied(); } // UO-H01","|| false || self.candidate != Presence::Present { return self.denied(); } // UO-H01","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-H01b-2","src/update_operation.rs","update_operation","|| self.challenge != Presence::Absent || self.candidate != Presence::Present { return self.denied(); } // UO-H01","|| self.challenge != Presence::Absent || false { return self.denied(); } // UO-H01","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-H02a-1","src/update_operation.rs","update_operation","if menu_valid != NativeValidity::Valid || nonce_valid != NativeValidity::Valid || new_menu != NativeDifference::Different","if false || nonce_valid != NativeValidity::Valid || new_menu != NativeDifference::Different","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-H02a-2","src/update_operation.rs","update_operation","if menu_valid != NativeValidity::Valid || nonce_valid != NativeValidity::Valid || new_menu != NativeDifference::Different","if menu_valid != NativeValidity::Valid || false || new_menu != NativeDifference::Different","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-H02a-3","src/update_operation.rs","update_operation","if menu_valid != NativeValidity::Valid || nonce_valid != NativeValidity::Valid || new_menu != NativeDifference::Different","if menu_valid != NativeValidity::Valid || nonce_valid != NativeValidity::Valid || false","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-H02b-1","src/update_operation.rs","update_operation","|| nonce_operation != NativeDifference::Different || nonce_predecessor != NativeDifference::Different","|| false || nonce_predecessor != NativeDifference::Different","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-H02b-2","src/update_operation.rs","update_operation","|| nonce_operation != NativeDifference::Different || nonce_predecessor != NativeDifference::Different","|| nonce_operation != NativeDifference::Different || false","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-H02c-1","src/update_operation.rs","update_operation","|| nonce_recorded != NativeDifference::Different { return self.denied(); } // UO-H02","|| false { return self.denied(); } // UO-H02","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-R01-1","src/update_operation.rs","update_operation","self.installed == Freshness::Fresh && self.challenge == Presence::Present && native.ready // UO-R01","true && self.challenge == Presence::Present && native.ready // UO-R01","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R01-2","src/update_operation.rs","update_operation","self.installed == Freshness::Fresh && self.challenge == Presence::Present && native.ready // UO-R01","self.installed == Freshness::Fresh && true && native.ready // UO-R01","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R01-3","src/update_operation.rs","update_operation","self.installed == Freshness::Fresh && self.challenge == Presence::Present && native.ready // UO-R01","self.installed == Freshness::Fresh && self.challenge == Presence::Present && true // UO-R01","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R02","src/update_operation.rs","update_operation","&& native.operation == NativeEquality::Equal // UO-R02","&& true // UO-R02","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R03","src/update_operation.rs","update_operation","&& native.target == NativeEquality::Equal // UO-R03","&& true // UO-R03","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R04","src/update_operation.rs","update_operation","&& native.candidate == NativeEquality::Equal // UO-R04","&& true // UO-R04","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R05","src/update_operation.rs","update_operation","&& native.menu == NativeEquality::Equal // UO-R05","&& true // UO-R05","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R06","src/update_operation.rs","update_operation","&& native.nonce == NativeEquality::Equal // UO-R06","&& true // UO-R06","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R07","src/update_operation.rs","update_operation","if !self.readiness_matches(native) || encoding != NativeBound::WithinBound { return self.denied(); } // UO-R07","if !self.readiness_matches(native) || false { return self.denied(); } // UO-R07","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R08","src/update_operation.rs","update_operation","self.accepted(Action::PrepareReadinessEncoding, false)","Self { stage: Stage::ReadyToRelease, ..self }.accepted(Action::PrepareReadinessEncoding, false)","updater_operation_literal_readiness_preflight_changes_no_state_before_encoding"],
    ["UO-R09","src/update_operation.rs","update_operation","self.recorded_readiness = Presence::Present;","self.recorded_readiness = self.recorded_readiness;","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R10","src/update_operation.rs","update_operation","self.stage = Stage::ReadyToRelease;","self.stage = Stage::InstalledVerified;","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-R11","src/update_operation.rs","update_operation","self.readiness = Freshness::Fresh;","self.readiness = self.readiness;","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-F01","src/update_operation.rs","update_operation","self.installed = Freshness::NotFresh; // UO-F01","self.installed = self.installed; // UO-F01","updater_operation_literal_failure_revokes_only_ephemeral_proof_and_challenge"],
    ["UO-F02","src/update_operation.rs","update_operation","self.readiness = Freshness::NotFresh; // UO-F02","self.readiness = self.readiness; // UO-F02","updater_operation_literal_failure_revokes_only_ephemeral_proof_and_challenge"],
    ["UO-F03","src/update_operation.rs","update_operation","self.challenge = Presence::Absent; // UO-F03","self.challenge = self.challenge; // UO-F03","updater_operation_literal_failure_revokes_only_ephemeral_proof_and_challenge"],
    ["UO-Q01","src/update_operation.rs","update_operation","Operation::QueryInstallerMayRemainArmed => self.accepted(Action::None, self.stage != Stage::Prepared), // UO-Q01","Operation::QueryInstallerMayRemainArmed => self.accepted(Action::None, false), // UO-Q01","updater_operation_literal_runtime_never_activates_and_armed_getter_is_stage_only"],
    ["UO-Q02-1","src/update_operation.rs","update_operation","let allowed = self.broker == Presence::Present && self.stage == Stage::ReadyToRelease // UO-Q02","let allowed = true && self.stage == Stage::ReadyToRelease // UO-Q02","updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs"],
    ["UO-Q02-2","src/update_operation.rs","update_operation","let allowed = self.broker == Presence::Present && self.stage == Stage::ReadyToRelease // UO-Q02","let allowed = self.broker == Presence::Present && true // UO-Q02","updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs"],
    ["UO-Q03-1","src/update_operation.rs","update_operation","&& self.installed == Freshness::Fresh && self.readiness == Freshness::Fresh; // UO-Q03","&& true && self.readiness == Freshness::Fresh; // UO-Q03","updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs"],
    ["UO-Q03-2","src/update_operation.rs","update_operation","&& self.installed == Freshness::Fresh && self.readiness == Freshness::Fresh; // UO-Q03","&& self.installed == Freshness::Fresh && true; // UO-Q03","updater_operation_literal_release_requires_broker_terminal_and_both_fresh_proofs"],
    ["UO-Q04","src/update_operation.rs","update_operation","Operation::QueryPermitsRuntimeActivation => self.accepted(Action::None, false), // UO-Q04","Operation::QueryPermitsRuntimeActivation => self.accepted(Action::None, true), // UO-Q04","updater_operation_literal_runtime_never_activates_and_armed_getter_is_stage_only"],
    ["UO-S01","src/update_operation.rs","update_operation","self.broker = Presence::Present;","self.broker = Presence::Absent;","updater_operation_literal_broker_binding_is_once_prepared_and_exact"],
    ["UO-S02","src/update_operation.rs","update_operation","self.candidate = Presence::Present;","self.candidate = Presence::Absent;","updater_operation_literal_candidate_requires_exact_new_artifact_and_early_stage"],
    ["UO-S03","src/update_operation.rs","update_operation","self.stage = Stage::PossiblyArmed;","self.stage = Stage::Prepared;","updater_operation_literal_arming_requires_exact_binding_and_bound_broker"],
    ["UO-S04","src/update_operation.rs","update_operation","self.installed = Freshness::Fresh;","self.installed = self.installed;","updater_operation_literal_install_requires_exact_candidate_broker_and_nonfresh_completion"],
    ["UO-S05","src/update_operation.rs","update_operation","self.challenge = Presence::Present;","self.challenge = Presence::Absent;","updater_operation_literal_challenge_requires_fresh_nonready_unissued_candidate_and_all_nonce_guards"],
    ["UO-S06","src/update_operation.rs","update_operation","self.challenge = Presence::Absent;\n                self.recorded_readiness = Presence::Present;","self.challenge = self.challenge;\n                self.recorded_readiness = Presence::Present;","updater_operation_literal_readiness_commit_requires_all_matches_and_bounded_encoding"],
    ["UO-S07","src/update_operation.rs","update_operation","Operation::ObserveIdle | Operation::ObserveCancelled => self.accepted(Action::None, false),","Operation::ObserveIdle => Self { installed: Freshness::NotFresh, readiness: Freshness::NotFresh, challenge: Presence::Absent, ..self }.accepted(Action::None, false),\n            Operation::ObserveCancelled => self.accepted(Action::None, false),","updater_operation_literal_cancellation_and_idle_never_release_fresh_or_armed_state"],
    ["UO-S08","src/update_operation.rs","update_operation","Operation::ObserveIdle | Operation::ObserveCancelled => self.accepted(Action::None, false),","Operation::ObserveIdle => self.accepted(Action::None, false),\n            Operation::ObserveCancelled => Self { installed: Freshness::NotFresh, readiness: Freshness::NotFresh, challenge: Presence::Absent, ..self }.accepted(Action::None, false),","updater_operation_literal_cancellation_and_idle_never_release_fresh_or_armed_state"],
    ["UO-S09","src/update_operation.rs","update_operation","if self.stage == Stage::PossiblyArmed { self.stage = Stage::InstalledVerified; } // UO-I03","self.stage = Stage::InstalledVerified; // UO-I03","updater_operation_literal_restored_terminal_needs_fresh_proof_but_retains_recorded_stage"],
    ["UO-S10","src/update_operation.rs","update_operation","self.installed = Freshness::Fresh;","self.installed = Freshness::Fresh;\n                self.recorded_readiness = Presence::Absent;","updater_operation_literal_restored_terminal_needs_fresh_proof_but_retains_recorded_stage"],
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze

  def self.updater_only?(arguments)
    return false if arguments == []
    return true if arguments == ['--updater-only']
    raise 'Mutation producer accepts no arguments or exact --updater-only only'
  end

  def self.lines(text)
    bytes = text.dup.force_encoding(Encoding::UTF_8)
    raise 'Updater mutation result is not UTF-8' unless bytes.valid_encoding?
    bytes.lines.map(&:chomp)
  end

  def self.validate_exit!(exit_status, signal, expected)
    raise 'Updater mutation process did not exit naturally with its exact status' unless
      exit_status == expected && signal.nil?
    nil
  end

  def self.validate_rejected!(text, test)
    values = lines(text)
    compiled = values.select { |line| line.match?(/\A\s*Finished\b/) }
    cases = values.select { |line| line.match?(/\Atest \S+ \.\.\. /) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    results = values.select { |line| line.start_with?('test result:') }
    errors = values.select { |line| line.start_with?('error') }
    raise 'Updater mutation lacks its compiled ordinary exact singleton assertion' unless
      compiled.length == 1 && compiled.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in [^\r\n]+\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      cases == ['test ' + test + ' ... FAILED'] &&
      panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at tests\/update_operation\.rs:\d+:\d+:\z/) &&
      assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
      results.length == 1 && results.first.match?(/\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 17 filtered out; finished in [^\r\n]+\z/) &&
      errors == ['error: test failed, to rerun pass `--test update_operation`'] &&
      values.none? { |line| line.include?('could not compile') || line.match?(/\bskipped\b/i) }
    nil
  end

  def self.validate_restored!(text, test)
    values = lines(text)
    compiled = values.select { |line| line.match?(/\A\s*Finished\b/) }
    cases = values.select { |line| line.match?(/\Atest \S+ \.\.\. /) }
    results = values.select { |line| line.start_with?('test result:') }
    raise 'Updater restored baseline lacks its compiled ordinary exact singleton pass' unless
      compiled.length == 1 && compiled.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in [^\r\n]+\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      cases == ['test ' + test + ' ... ok'] &&
      results.length == 1 && results.first.match?(/\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 17 filtered out; finished in [^\r\n]+\z/) &&
      values.none? { |line| line.start_with?('error', "thread '", 'assertion ') ||
        line.include?('could not compile') || line.match?(/\bskipped\b/i) }
    nil
  end
end

module BelugaCorePacketQueueMutationOracle
  CONTROLS = [
  [
    "PQ-THRESHOLD-SOFT",
    "src/packet_send_queue.rs",
    "packet_send_queue",
    "result.sample_inflated = u32::from(measured && delay > 0.100);",
    "result.sample_inflated = u32::from(measured && delay >= 0.100);",
    "packet_send_queue_literal_thresholds_and_adjacent_ieee_values"
  ],
  [
    "PQ-THRESHOLD-IMMEDIATE",
    "src/packet_send_queue.rs",
    "packet_send_queue",
    "result.immediate = u32::from(measured && delay >= 0.200);",
    "result.immediate = u32::from(measured && delay > 0.200);",
    "packet_send_queue_literal_thresholds_and_adjacent_ieee_values"
  ],
  [
    "PQ-THRESHOLD-UPGRADE",
    "src/packet_send_queue.rs",
    "packet_send_queue",
    "result.upgrade = u32::from((measured && delay <= 0.020)\n        || (!measured && result.state.low_present != 0 && low_fresh));",
    "result.upgrade = u32::from((measured && delay <= 0.021)\n        || (!measured && result.state.low_present != 0 && low_fresh));",
    "packet_send_queue_literal_thresholds_and_adjacent_ieee_values"
  ],
  [
    "PQ-LEASE-ONE-ATTOSECOND",
    "src/packet_send_queue.rs",
    "packet_send_queue",
    "const LEASE_ATTOSECONDS: i128 = 1_500_000_000_000_000_000;",
    "const LEASE_ATTOSECONDS: i128 = 1_500_000_000_000_000_001;",
    "packet_send_queue_soft_lease_is_exactly_closed_zero_through_one_point_five_seconds"
  ],
  [
    "PQ-NO-PACKETS-RENEWAL",
    "src/packet_send_queue.rs",
    "packet_send_queue",
    "} else if observation == OBSERVATION_NO_PACKETS && event.rtt_inflated == 0 {\n        if state.soft_present != 0 && !soft_fresh {",
    "} else if observation == OBSERVATION_NO_PACKETS && event.rtt_inflated == 0 {\n        result.soft_action = ACTION_STAMP_NOW;\n        if state.soft_present != 0 && !soft_fresh {",
    "packet_send_queue_no_packets_never_renew_low_or_soft_stamps"
  ],
  [
    "PQ-TIER-BASELINE-LOSS",
    "src/packet_send_queue.rs",
    "packet_send_queue",
    "if event.opcode == OP_PATH_RESET { result.state = RawState::empty(); }",
    "if event.opcode >= OP_TIER_RESET { result.state = RawState::empty(); }",
    "packet_send_queue_tier_reset_retains_raw_baseline_and_path_reset_clears_it"
  ],
  [
    "PQ-SOFT-COUNT-LOSS",
    "src/packet_send_queue.rs",
    "packet_send_queue",
    "result.state.pressure_count = (result.state.pressure_count + 1).min(i64::MAX as u64);",
    "result.state.pressure_count = 1;",
    "packet_send_queue_soft_pressure_requires_two_reports_and_stamps_each_measurement"
  ],
  [
    "PQ-CAPACITY-CONTAMINATION",
    "src/packet_send_queue.rs",
    "packet_send_queue",
    "if event.opcode == OP_CAPACITY {\n        result.inflated = u32::from(result.sample_inflated != 0",
    "if event.opcode == OP_CAPACITY {\n        result.state.pressure_count = 0;\n        result.inflated = u32::from(result.sample_inflated != 0",
    "packet_send_queue_capacity_never_accumulates_or_retires_ordinary_pressure"
  ]
].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze

  def self.validate!(text, test, passed:)
    values = BelugaCoreUpdaterMutationOracle.lines(text)
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_result = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 31 filtered out; finished in [^\r\n]+\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 31 filtered out; finished in [^\r\n]+\z/
    raise 'Queue mutation lacks compiled ordinary exact singleton outcome' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in [^\r\n]+\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_result.match?(lines.first) } &&
      values.none? { |line| line.include?('could not compile') || line.match?(/\bskipped\b/i) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    if passed
      raise 'Queue restored baseline contains error or assertion failure' unless
        panics.empty? && assertions.empty? && errors.empty?
    else
      raise 'Queue mutation lacks ordinary equality assertion failure' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at tests\/packet_send_queue\.rs:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        errors == ['error: test failed, to rerun pass `--test packet_send_queue`']
    end
    nil
  end
end

module BelugaCoreRTTEvidenceMutationOracle
  CONTROLS = [
    ["RTT-BOOTSTRAP-MEDIAN", "src/rtt_evidence.rs", "rtt_evidence", "state.baseline_bits = values[1];", "state.baseline_bits = values[0];", "rtt_evidence_legacy_three_sample_bootstrap_uses_sorted_median"],
    ["RTT-INFLATION-INCLUSIVE", "src/rtt_evidence.rs", "rtt_evidence", "f64::from_bits(bits) > threshold", "f64::from_bits(bits) >= threshold", "rtt_evidence_literal_inflation_thresholds_and_ieee_neighbors_are_unchanged"],
    ["RTT-BASELINE-FALL", "src/rtt_evidence.rs", "rtt_evidence", "state.baseline_bits = current.max(baseline - 0.010).to_bits();", "state.baseline_bits = current.max(baseline - 0.020).to_bits();", "rtt_evidence_baseline_falls_at_most_ten_milliseconds_and_never_rises"],
    ["RTT-LEASE-ONE-ATTOSECOND", "src/rtt_evidence.rs", "rtt_evidence", "const LEASE_ATTOSECONDS: i128 = 4_000_000_000_000_000_000;", "const LEASE_ATTOSECONDS: i128 = 4_000_000_000_000_000_001;", "rtt_evidence_cached_healthy_lease_is_closed_at_four_seconds_without_quantization"],
    ["RTT-DUPLICATE-CLOCK-RENEWAL", "src/rtt_evidence.rs", "rtt_evidence", "if !advanced {\n        if !optional_scalar_equal(1, current_bits,", "if !advanced {\n        result.clock_action = CLOCK_STAMP_NOW;\n        if !optional_scalar_equal(1, current_bits,", "rtt_evidence_cached_watermark_never_renews_clock_or_repeats_inflation_pressure"],
    ["RTT-DISTINCT-REFERENCE-COUNT", "src/rtt_evidence.rs", "rtt_evidence", "result.state.distinct_count = (result.state.distinct_count + 1).min(3);", "result.state.distinct_count = (result.state.distinct_count + 1).min(2);", "rtt_evidence_native_three_distinct_healthy_references_saturate_without_cached_credit"],
    ["RTT-INITIAL-PRIVILEGE-BYPASS", "src/rtt_evidence.rs", "rtt_evidence", "let first_for_peer = !had_watermark && result.state.permits_initial != 0;", "let first_for_peer = !had_watermark;", "rtt_evidence_disabled_initial_privilege_requires_seed_then_distinct_advancement"],
    ["RTT-FAST-PRESSURE-CONSUMPTION", "src/rtt_evidence.rs", "rtt_evidence", "if validation.fresh_pressure == 0 {", "if true {", "rtt_evidence_fast_pressure_preserves_watermark_for_one_ordinary_pressure_decision"],
    ["RTT-FAST-REFERENCE-CONTAMINATION", "src/rtt_evidence.rs", "rtt_evidence", "result.state.fence_current_bits = validation.state.fence_current_bits;", "result.state.fence_current_bits = validation.state.fence_current_bits;\n        result.state.baseline_bits = validation.state.baseline_bits;", "rtt_evidence_fast_positive_commits_only_fence_never_ordinary_reference_or_clock"],
    ["RTT-FENCE-SCALAR-CONTRADICTION", "src/rtt_evidence.rs", "rtt_evidence", "let contradictory_scalar = measurement_equal(event.measurement, previous_fence)", "let contradictory_scalar = false && measurement_equal(event.measurement, previous_fence)", "rtt_evidence_fast_fence_scalar_contradiction_cannot_be_reinterpreted_as_ordinary_advancement"]
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze

  def self.validate!(text, test, passed:)
    values = BelugaCoreUpdaterMutationOracle.lines(text)
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_result = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 33 filtered out; finished in [^\r\n]+\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 33 filtered out; finished in [^\r\n]+\z/
    raise 'RTT evidence mutation lacks compiled ordinary exact singleton outcome' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in [^\r\n]+\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_result.match?(lines.first) } &&
      values.none? { |line| line.include?('could not compile') || line.match?(/\bskipped\b/i) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    if passed
      raise 'RTT evidence restored baseline contains error or assertion failure' unless
        panics.empty? && assertions.empty? && errors.empty?
    else
      raise 'RTT evidence mutation lacks ordinary equality assertion failure' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at tests\/rtt_evidence\.rs:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        errors == ['error: test failed, to rerun pass `--test rtt_evidence`']
    end
    nil
  end
end

module BelugaCoreTierDemandMutationOracle
  CONTROLS = [
    ["TD-BASIS-HIGH", "src/tier_demand.rs", "tier_demand", "const BASIS_POINTS: [u32; 8] = [10_000, 6_700, 4_200, 2_100, 800, 300, 100, 25];", "const BASIS_POINTS: [u32; 8] = [10_000, 6_600, 4_200, 2_100, 800, 300, 100, 25];", "tier_demand_all_eight_literal_fifty_megabit_profiles_preserve_distinct_fields"],
    ["TD-BASELINE-DEMAND", "src/tier_demand.rs", "tier_demand", "const BASELINE_MAXIMUM_VIDEO: u64 = 9_344_000;", "const BASELINE_MAXIMUM_VIDEO: u64 = 9_343_999;", "tier_demand_basis_points_and_calibrated_baselines_do_not_follow_configured_ceiling"],
    ["TD-RESERVE", "src/tier_demand.rs", "tier_demand", "const AUDIO_CONTROL_RESERVE: f64 = 320_000.0;", "const AUDIO_CONTROL_RESERVE: f64 = 300_000.0;", "tier_demand_configured_video_budget_reserve_floor_and_tiny_cap_are_literal"],
    ["TD-BUDGET-FLOOR", "src/tier_demand.rs", "tier_demand", "(budget.floor() as u64).max(MINIMUM_VIDEO)", "(budget.ceil() as u64).max(MINIMUM_VIDEO)", "tier_demand_configured_video_budget_reserve_floor_and_tiny_cap_are_literal"],
    ["TD-INTEGER-QUOTIENT", "src/tier_demand.rs", "tier_demand", "let scaled_video = (reference_maximum * u64::from(tier.basis_points()) / 10_000)", "let scaled_video = ((reference_maximum * u64::from(tier.basis_points()) + 9_999) / 10_000)", "tier_demand_full_width_scaling_divides_as_integers_before_conversion"],
    ["TD-RTP-CEILING", "src/tier_demand.rs", "tier_demand", ".min(f64::from(facts.configured_cap)).ceil() as u32;", ".min(f64::from(facts.configured_cap)).floor() as u32;", "tier_demand_binary64_total_rtp_ceiling_artifacts_are_not_algebraically_removed"],
    ["TD-INITIAL-SURVIVAL-FLOOR", "src/tier_demand.rs", "tier_demand", "Tier(ceiling.0.max(5))", "Tier(ceiling.0.max(4))", "tier_demand_initial_tier_is_no_better_than_survival_even_at_full_capacity"],
    ["TD-SUSTAINABLE-INCLUSIVE", "src/tier_demand.rs", "tier_demand", "&& bandwidth >= tier.required())", "&& bandwidth > tier.required())", "tier_demand_sustainable_admission_is_inclusive_at_every_literal_ieee_neighbor"],
    ["TD-SUSTAINABLE-CAP", "src/tier_demand.rs", "tier_demand", "Tier::ALL.into_iter().find(|tier|\n            tier.required() <= f64::from(self.configured_cap)\n                && bandwidth >= tier.required())", "Tier::ALL.into_iter().find(|tier|\n            true\n                && bandwidth >= tier.required())", "tier_demand_sustainable_quality_cannot_bypass_configured_cap_with_huge_bandwidth"],
    ["TD-UPGRADE-MARGIN", "src/tier_demand.rs", "tier_demand", "const UPGRADE_MARGIN: f64 = 1.25;", "const UPGRADE_MARGIN: f64 = 1.20;", "tier_demand_upgrade_margin_is_independent_and_inclusive_at_ieee_neighbors"],
    ["TD-UPGRADE-INCLUSIVE", "src/tier_demand.rs", "tier_demand", "bandwidth >= threshold", "bandwidth > threshold", "tier_demand_upgrade_margin_is_independent_and_inclusive_at_ieee_neighbors"],
    ["TD-UPGRADE-CAP-ADMISSION", "src/tier_demand.rs", "tier_demand", "if required > f64::from(self.configured_cap) { return false; }", "if false { return false; }", "tier_demand_upgrade_threshold_saturates_at_cap_without_admitting_over_cap_demand"]
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze

  def self.validate!(text, test, passed:)
    values = BelugaCoreUpdaterMutationOracle.lines(text)
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_result = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 27 filtered out; finished in [^\r\n]+\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 27 filtered out; finished in [^\r\n]+\z/
    raise 'Tier demand mutation lacks compiled ordinary exact singleton outcome' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in [^\r\n]+\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_result.match?(lines.first) } &&
      values.none? { |line| line.include?('could not compile') || line.match?(/\bskipped\b/i) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    if passed
      raise 'Tier demand restored baseline contains error or assertion failure' unless
        panics.empty? && assertions.empty? && errors.empty?
    else
      raise 'Tier demand mutation lacks ordinary equality assertion failure' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at tests\/tier_demand\.rs:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        errors == ['error: test failed, to rerun pass `--test tier_demand`']
    end
    nil
  end
end

# Insert before the current `if __FILE__ == $PROGRAM_NAME` boundary.
# Importing this module does not run Cargo or create a work directory.
module BelugaCoreMediaCommandGateMutationOracle
  CONTROLS = [
    ["MCG-LIFECYCLE-OPEN", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Lifecycle => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle,",
     "Operation::Lifecycle => true && state.lifecycle == event.candidate_lifecycle,",
     "media_command_gate_initial_closed_state_refuses_all_queries_without_fault"],
    ["MCG-LIFECYCLE-ID", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Lifecycle => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle,",
     "Operation::Lifecycle => state.is_open == 1 && true,",
     "media_command_gate_lifecycle_query_ignores_command_epoch"],
    ["MCG-CAPTURE-OPEN", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Capture => state.is_open == 1 && event.context_is_current == 1,",
     "Operation::Capture => true && event.context_is_current == 1,",
     "media_command_gate_capture_uses_only_open_and_native_membership_fact"],
    ["MCG-CAPTURE-MEMBERSHIP", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Capture => state.is_open == 1 && event.context_is_current == 1,",
     "Operation::Capture => state.is_open == 1 && true,",
     "media_command_gate_capture_uses_only_open_and_native_membership_fact"],
    ["MCG-ADMIT-OPEN", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Admit => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle\n            && state.command_epoch == event.candidate_command_epoch && event.context_is_current == 1,",
     "Operation::Admit => true && state.lifecycle == event.candidate_lifecycle\n            && state.command_epoch == event.candidate_command_epoch && event.context_is_current == 1,",
     "media_command_gate_admission_requires_all_four_original_conditions"],
    ["MCG-ADMIT-LIFECYCLE", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Admit => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle\n            && state.command_epoch == event.candidate_command_epoch && event.context_is_current == 1,",
     "Operation::Admit => state.is_open == 1 && true\n            && state.command_epoch == event.candidate_command_epoch && event.context_is_current == 1,",
     "media_command_gate_admission_requires_all_four_original_conditions"],
    ["MCG-ADMIT-EPOCH", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Admit => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle\n            && state.command_epoch == event.candidate_command_epoch && event.context_is_current == 1,",
     "Operation::Admit => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle\n            && true && event.context_is_current == 1,",
     "media_command_gate_admission_requires_all_four_original_conditions"],
    ["MCG-ADMIT-MEMBERSHIP", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Admit => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle\n            && state.command_epoch == event.candidate_command_epoch && event.context_is_current == 1,",
     "Operation::Admit => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle\n            && state.command_epoch == event.candidate_command_epoch && true,",
     "media_command_gate_admission_requires_all_four_original_conditions"],
    ["MCG-OPEN-LIFECYCLE-WRAP", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Open => {\n            state.lifecycle = state.lifecycle.wrapping_add(1);",
     "Operation::Open => {\n            state.lifecycle = state.lifecycle.saturating_add(1);",
     "media_command_gate_open_wraps_each_full_uint64_counter_independently"],
    ["MCG-OPEN-EPOCH-WRAP", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Open => {\n            state.lifecycle = state.lifecycle.wrapping_add(1);\n            state.command_epoch = state.command_epoch.wrapping_add(1);",
     "Operation::Open => {\n            state.lifecycle = state.lifecycle.wrapping_add(1);\n            state.command_epoch = state.command_epoch.saturating_add(1);",
     "media_command_gate_open_wraps_each_full_uint64_counter_independently"],
    ["MCG-CLOSE-LIFECYCLE-WRAP", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Close => {\n            state.lifecycle = state.lifecycle.wrapping_add(1);",
     "Operation::Close => {\n            state.lifecycle = state.lifecycle.saturating_add(1);",
     "media_command_gate_close_wraps_each_full_uint64_counter_independently"],
    ["MCG-CLOSE-EPOCH-WRAP", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Close => {\n            state.lifecycle = state.lifecycle.wrapping_add(1);\n            state.command_epoch = state.command_epoch.wrapping_add(1);",
     "Operation::Close => {\n            state.lifecycle = state.lifecycle.wrapping_add(1);\n            state.command_epoch = state.command_epoch.saturating_add(1);",
     "media_command_gate_close_wraps_each_full_uint64_counter_independently"],
    ["MCG-INVALIDATE-EPOCH-WRAP", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Invalidate => {\n            state.command_epoch = state.command_epoch.wrapping_add(1);",
     "Operation::Invalidate => {\n            state.command_epoch = state.command_epoch.saturating_add(1);",
     "media_command_gate_invalidate_wraps_without_rotating_lifecycle_or_open"],
    ["MCG-INVALIDATE-LIFECYCLE", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Invalidate => {\n            state.command_epoch = state.command_epoch.wrapping_add(1);",
     "Operation::Invalidate => {\n            state.lifecycle = state.lifecycle.wrapping_add(1);\n            state.command_epoch = state.command_epoch.wrapping_add(1);",
     "media_command_gate_invalidation_changes_only_command_epoch"],
    ["MCG-STATE-ABI", "src/media_command_gate.rs", "media_command_gate",
     "self.abi_version == ABI_VERSION && self.is_open <= 1",
     "true && self.is_open <= 1",
     "media_command_gate_invalid_state_abi_and_boolean_tags_are_canonical_denial"],
    ["MCG-STATE-BOOLEAN", "src/media_command_gate.rs", "media_command_gate",
     "self.abi_version == ABI_VERSION && self.is_open <= 1",
     "self.abi_version == ABI_VERSION && true",
     "media_command_gate_invalid_state_abi_and_boolean_tags_are_canonical_denial"],
    ["MCG-EVENT-BOOLEAN", "src/media_command_gate.rs", "media_command_gate",
     "if event.context_is_current > 1 || event.reserved0 != 0 || event.reserved1 != 0 {",
     "if false || event.reserved0 != 0 || event.reserved1 != 0 {",
     "media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied"],
    ["MCG-EVENT-RESERVED0", "src/media_command_gate.rs", "media_command_gate",
     "if event.context_is_current > 1 || event.reserved0 != 0 || event.reserved1 != 0 {",
     "if event.context_is_current > 1 || false || event.reserved1 != 0 {",
     "media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied"],
    ["MCG-EVENT-RESERVED1", "src/media_command_gate.rs", "media_command_gate",
     "if event.context_is_current > 1 || event.reserved0 != 0 || event.reserved1 != 0 {",
     "if event.context_is_current > 1 || event.reserved0 != 0 || false {",
     "media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied"],
    ["MCG-MUTATING-PAYLOAD", "src/media_command_gate.rs", "media_command_gate",
     "0..=2 if event.context_is_current == 0 && event.candidate_lifecycle == 0\n            && event.candidate_command_epoch == 0 => match event.opcode {",
     "0..=2 => match event.opcode {",
     "media_command_gate_each_opcode_rejects_noncanonical_unused_payload"],
    ["MCG-LIFECYCLE-PAYLOAD", "src/media_command_gate.rs", "media_command_gate",
     "3 if event.context_is_current == 0 && event.candidate_command_epoch == 0 =>",
     "3 =>",
     "media_command_gate_each_opcode_rejects_noncanonical_unused_payload"],
    ["MCG-CAPTURE-PAYLOAD", "src/media_command_gate.rs", "media_command_gate",
     "4 if event.candidate_lifecycle == 0 && event.candidate_command_epoch == 0 =>",
     "4 =>",
     "media_command_gate_each_opcode_rejects_noncanonical_unused_payload"],
    ["MCG-UNKNOWN-OPCODE", "src/media_command_gate.rs", "media_command_gate",
     "_ => None,",
     "_ => Some(Operation::Admit),",
     "media_command_gate_unknown_opcode_reserved_and_membership_tags_are_denied"],
    ["MCG-VERIFIER-DENIAL", "src/media_command_gate.rs", "media_command_gate",
     "u32::from(expected.status == 1 && expected == result)",
     "u32::from(expected == result)",
     "media_command_gate_canonical_denial_cannot_be_validated_as_a_reset"],
    ["MCG-VERIFIER-COMPLETE", "src/media_command_gate.rs", "media_command_gate",
     "u32::from(expected.status == 1 && expected == result)",
     "u32::from(expected.status == 1 && expected.allowed == result.allowed)",
     "media_command_gate_verifier_rejects_each_of_all_forty_copied_bytes"],
    ["MCG-LIFECYCLE-QUERY-STATE", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Lifecycle => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle,",
     "Operation::Lifecycle => { state.command_epoch = state.command_epoch.wrapping_add(1); state.is_open == 1 && state.lifecycle == event.candidate_lifecycle },",
     "media_command_gate_accepted_queries_leave_every_state_word_unchanged"],
    ["MCG-CAPTURE-QUERY-STATE", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Capture => state.is_open == 1 && event.context_is_current == 1,",
     "Operation::Capture => { state.lifecycle = state.lifecycle.wrapping_add(1); state.is_open == 1 && event.context_is_current == 1 },",
     "media_command_gate_accepted_queries_leave_every_state_word_unchanged"],
    ["MCG-ADMIT-QUERY-STATE", "src/media_command_gate.rs", "media_command_gate",
     "Operation::Admit => state.is_open == 1 && state.lifecycle == event.candidate_lifecycle\n            && state.command_epoch == event.candidate_command_epoch && event.context_is_current == 1,",
     "Operation::Admit => { state.command_epoch = state.command_epoch.wrapping_add(1); state.is_open == 1 && state.lifecycle == event.candidate_lifecycle\n            && state.command_epoch == event.candidate_command_epoch && event.context_is_current == 1 },",
     "media_command_gate_accepted_queries_leave_every_state_word_unchanged"]
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze

  def self.validate!(text, test, passed:)
    values = BelugaCoreUpdaterMutationOracle.lines(text)
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_result = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 20 filtered out; finished in [^\r\n]+\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 20 filtered out; finished in [^\r\n]+\z/
    raise 'Media command gate mutation lacks compiled ordinary exact singleton outcome' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in [^\r\n]+\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_result.match?(lines.first) } &&
      values.none? { |line| line.include?('could not compile') || line.match?(/\bskipped\b/i) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    if passed
      raise 'Media command gate restored baseline contains error or assertion failure' unless
        panics.empty? && assertions.empty? && errors.empty?
    else
      raise 'Media command gate mutation lacks ordinary equality assertion failure' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at tests\/media_command_gate\.rs:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        errors == ['error: test failed, to rerun pass `--test media_command_gate`']
    end
    nil
  end
end

module BelugaCoreScreenSuspensionMutationOracle
  CONTROLS = [
    ["SS-INACTIVE-INCLUSIVE","src/screen_suspension.rs","screen_suspension","&& event.visibility_epoch >= state.visibility_epoch","&& event.visibility_epoch > state.visibility_epoch","screen_suspension_inactive_inclusive_visibility_and_each_foreign_axis_remain_exact"],
    ["SS-INACTIVE-REBIND","src/screen_suspension.rs","screen_suspension","                state.visibility_epoch = event.visibility_epoch;\n                state.inactive_confirmed = 1;","                state.visibility_epoch = state.visibility_epoch;\n                state.inactive_confirmed = 1;","screen_suspension_inactive_first_partial_none_action_publishes_rebinding_and_rejects_stale_cover"],
    ["SS-STALE-COVER","src/screen_suspension.rs","screen_suspension","if phase == Phase::Suspending && binding_matches(state, event) && notice_matches(state, event)","if phase == Phase::Suspending && true && notice_matches(state, event)","screen_suspension_inactive_first_partial_none_action_publishes_rebinding_and_rejects_stale_cover"],
    ["SS-EARLY-JOIN","src/screen_suspension.rs","screen_suspension","if state.inactive_confirmed == 1 {","if true {","screen_suspension_cover_first_then_inactive_joins_and_rebinds_entire_scalar_state"],
    ["SS-ZERO-SKIP","src/screen_suspension.rs","screen_suspension","if state.next_generation == 0 { state.next_generation = 1; }","if state.next_generation == 0 { state.next_generation = 0; }","screen_suspension_begin_wraps_full_uint64_and_skips_only_zero"],
    ["SS-RETIRE-COUNTER","src/screen_suspension.rs","screen_suspension","        Opcode::Retire => {\n            state = initial_with_counter(state.next_generation);","        Opcode::Retire => {\n            state = initial_with_counter(1);","screen_suspension_retire_every_phase_preserves_full_generator"],
    ["SS-ABORT-PRIOR","src/screen_suspension.rs","screen_suspension","state.suspension_generation = state.prior_suspension_generation;","state.suspension_generation = 0;","screen_suspension_abort_restores_prior_with_or_without_cover_but_not_after_inactive"],
    ["SS-COMPLETED-CUSTODY","src/screen_suspension.rs","screen_suspension","enter(&mut state, Phase::Active, 1);","enter(&mut state, Phase::Active, 0);","screen_suspension_exact_resume_sequence_preserves_full_state_and_final_mask_sixty_nine"],
    ["SS-STALE-CANCEL","src/screen_suspension.rs","screen_suspension","if state.custody_mask & 1 != 0 && binding_matches(state, event) {","if state.custody_mask & 1 != 0 && true {","screen_suspension_stale_cleanup_cannot_retire_or_suspend_any_foreign_binding"],
    ["SS-PROOF-ORDER","src/screen_suspension.rs","screen_suspension","if phase == Phase::AwaitingRealFrame && binding_matches(state, event) && notice_matches(state, event)","if phase != Phase::AwaitingRealFrame && binding_matches(state, event) && notice_matches(state, event)","screen_suspension_every_out_of_order_proof_and_stale_binding_is_ordinary_refusal"],
    ["SS-FULL-NATIVE-FACT","src/screen_suspension.rs","screen_suspension","&& notice_matches(state, event) && facts(event, 1 << 5) {","&& notice_matches(state, event) && true {","screen_suspension_each_resume_fact_is_required_independently_not_only_notice_pairs"],
    ["SS-QUERY-NONMUTATING","src/screen_suspension.rs","screen_suspension","        Opcode::Owns => { accepted = phase != Phase::Idle && binding_matches(state, event); },","        Opcode::Owns => { accepted = phase != Phase::Idle && binding_matches(state, event); state.next_generation = 1; },","screen_suspension_owns_and_authorizes_are_exact_nonmutating_full_state_queries"],
    ["SS-VERIFIER-BYPASS","src/screen_suspension.rs","screen_suspension","u32::from(expected.status == 1 && expected == result)","u32::from(expected.status == 1)","screen_suspension_verifier_rejects_every_one_of_all_128_copied_result_bytes"],
    ["SS-DENIAL-NOT-RESET","src/screen_suspension.rs","screen_suspension","u32::from(expected.status == 1 && expected == result)","u32::from(expected == result)","screen_suspension_unknown_operations_and_denial_never_validate_as_reset_or_grant"]
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze

  def self.validate!(text, test, passed:)
    values = BelugaCoreUpdaterMutationOracle.lines(text)
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_result = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 31 filtered out; finished in [^\r\n]+\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 31 filtered out; finished in [^\r\n]+\z/
    raise 'Screen suspension mutation lacks compiled ordinary exact singleton outcome' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in [^\r\n]+\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_result.match?(lines.first) } &&
      values.none? { |line| line.include?('could not compile') || line.match?(/\bskipped\b/i) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    if passed
      raise 'Screen suspension restored baseline contains error or assertion failure' unless
        panics.empty? && assertions.empty? && errors.empty?
    else
      raise 'Screen suspension mutation lacks ordinary equality assertion failure' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at tests\/screen_suspension\.rs:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        errors == ['error: test failed, to rerun pass `--test screen_suspension`']
    end
    nil
  end
end

# Importable control/text decoder snippet only. It never runs Cargo on require.
# Canonical runner adoption: append CONTROLS to mutants, add --phone-catalog-only,
# select ['--test', 'phone_catalog'], route failed/restored output through validate!,
# and include this owner in the exact restoration/test-body/production checks.
# Pass capture exitstatus/termsig and timed_out:false only after Open3 returns
# naturally; a timeout wrapper must pass its actual timed_out state.
module BelugaCorePhoneCatalogMutationOracle
  CONTROLS = [
    ['PC-header-schema-removed', 'src/phone_catalog.rs', 'phone_catalog',
     'Stage::Header => if raw.flags & 1 == 0 { 1 }',
     'Stage::Header => if false { 1 }',
     'phone_catalog_header_schema_host_capacity_precedence'],
    ['PC-duplicate-before-full-removed', 'src/phone_catalog.rs', 'phone_catalog',
     'Stage::RecordUniqueness | Stage::Add => if raw.duplicate_axes != 0 { 3 }',
     'Stage::RecordUniqueness | Stage::Add => if false { 3 }',
     'phone_catalog_add_duplicate_precedes_full_capacity'],
    ['PC-capacity-seven', 'src/phone_catalog.rs', 'phone_catalog',
     'else if matches!(input.stage, Stage::Add) && raw.count == 8 { 5 }',
     'else if matches!(input.stage, Stage::Add) && raw.count == 7 { 5 }',
     'phone_catalog_add_duplicate_precedes_full_capacity'],
    ['PC-token-foreign-admitted', 'src/phone_catalog.rs', 'phone_catalog',
     'Stage::Token => if raw.flags != 3 { 6 } else { 0 }',
     'Stage::Token => if raw.flags & 1 == 0 { 6 } else { 0 }',
     'phone_catalog_token_all_operations_missing_foreign_stale'],
    ['PC-binding-removed', 'src/phone_catalog.rs', 'phone_catalog',
     'if raw.flags == 0 { 8 }', 'if false { 8 }',
     'phone_catalog_binding_precedes_counter_and_phase_regressions'],
    ['PC-outbound-signed', 'src/phone_catalog.rs', 'phone_catalog',
     'raw.candidate_outbound < raw.previous_outbound',
     '(raw.candidate_outbound as i64) < (raw.previous_outbound as i64)',
     'phone_catalog_both_full_u64_counters_all_boundaries'],
    ['PC-accepted-counter-removed', 'src/phone_catalog.rs', 'phone_catalog',
     'raw.candidate_accepted < raw.previous_accepted', 'false',
     'phone_catalog_both_full_u64_counters_all_boundaries'],
    ['PC-issued-rank-wrong', 'src/phone_catalog.rs', 'phone_catalog',
     'Self::Active => 2, Self::AcceptedIssued => -1',
     'Self::Active => 2, Self::AcceptedIssued => 3',
     'phone_catalog_phase_rank_original_four_tags'],
    ['PC-invalid-recovery-removed', 'src/phone_catalog.rs', 'phone_catalog',
     'if previous == Some(Recovery::InvalidBridge) || candidate == Some(Recovery::InvalidBridge) { 10 }',
     'if false { 10 }', 'phone_catalog_recovery_invalid_bridge_precedes_retention'],
    ['PC-resend-retention-removed', 'src/phone_catalog.rs', 'phone_catalog',
     '&& raw.flags == 0 { 7 } else { 0 }',
     '&& false { 7 } else { 0 }', 'phone_catalog_recovery_same_phase_exact_resend_retention'],
    ['PC-select-unknown-admitted', 'src/phone_catalog.rs', 'phone_catalog',
     'Stage::Select => if raw.flags == 0 && raw.target_slot == 8 { 4 } else { 0 }',
     'Stage::Select => if false { 4 } else { 0 }',
     'phone_catalog_select_nil_member_and_unknown_every_count'],
    ['PC-add-implicit-selection', 'src/phone_catalog.rs', 'phone_catalog',
     'Operation::Add => { slots[count as usize] = 8; count += 1; }',
     'Operation::Add => { slots[count as usize] = 8; count += 1; selected = count - 1; }',
     'phone_catalog_plan_add_complete_append_no_implicit_selection'],
    ['PC-update-candidate-map-removed', 'src/phone_catalog.rs', 'phone_catalog',
     '&& source == raw.target_slot { 8 } else { source }',
     '&& source == raw.target_slot { source } else { source }',
     'phone_catalog_plan_update_exact_target_and_siblings_all_slots'],
    ['PC-forget-selection-reindex-removed', 'src/phone_catalog.rs', 'phone_catalog',
     'else if selected != 8 && selected > raw.target_slot { selected -= 1; }',
     'else if selected != 8 && selected > raw.target_slot { selected = selected; }',
     'phone_catalog_plan_forget_survivor_order_selection_reindex_original_target'],
    ['PC-target-remapped', 'src/phone_catalog.rs', 'phone_catalog',
     'selected_slot: selected, target_slot: raw.target_slot, reserved: 0,',
     'selected_slot: selected, target_slot: if input.operation == Operation::Forget { 8 } else { raw.target_slot }, reserved: 0,',
     'phone_catalog_plan_forget_survivor_order_selection_reindex_original_target'],
    ['PC-noop-uses-candidate-map', 'src/phone_catalog.rs', 'phone_catalog',
     'if raw.flags == 1 { return planned(&input, true, 2, raw.revision); }',
     'if raw.flags == 1 { return planned(&input, false, 2, raw.revision); }',
     'phone_catalog_finish_noop_original_sources_before_maximum'],
    ['PC-exhaustion-before-noop', 'src/phone_catalog.rs', 'phone_catalog',
     'if raw.flags == 1 { return planned(&input, true, 2, raw.revision); }',
     'if raw.revision == u64::MAX { return empty(1, 9); } if raw.flags == 1 { return planned(&input, true, 2, raw.revision); }',
     'phone_catalog_finish_noop_original_sources_before_maximum'],
    ['PC-revision-no-increment', 'src/phone_catalog.rs', 'phone_catalog',
     'planned(&input, false, 3, raw.revision + 1)',
     'planned(&input, false, 3, raw.revision)',
     'phone_catalog_finish_all_operations_exact_single_successor'],
    ['PC-unused-input-admitted', 'src/phone_catalog.rs', 'phone_catalog',
     'if raw != allowed { return None; }',
     'if raw.abi_version != allowed.abi_version { return None; }',
     'phone_catalog_every_unused_input_field_is_rejected'],
    ['PC-malformed-status-verified', 'src/phone_catalog.rs', 'phone_catalog',
     'u32::from(expected.status == 1 && expected == result)',
     'u32::from(expected == result)',
     'phone_catalog_verifier_malformed_status0_never_valid_business_denials_valid'],
    ['PC-verifier-ignores-output', 'src/phone_catalog.rs', 'phone_catalog',
     'u32::from(expected.status == 1 && expected == result)',
     'u32::from(expected.status == 1)',
     'phone_catalog_verifier_rejects_every_output_byte_after_actual_c'],
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'phone catalog outcome tag is not Boolean' unless passed == true || passed == false
    raise 'phone catalog intended test is not a named control' unless TESTS.include?(test)
    raise 'phone catalog timeout is not assertion evidence' unless timed_out == false
    expected_exit = passed ? 0 : 101
    raise 'phone catalog process did not exit naturally with exact status' unless
      exitstatus == expected_exit && termsig.nil?
    bytes = combined.dup.force_encoding(Encoding::UTF_8)
    raise 'phone catalog mutation result is not UTF-8' unless bytes.valid_encoding?
    lines = bytes.lines.map(&:chomp)
    raise 'phone catalog compile/timeout/signal text is not policy evidence' if lines.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    compiled = lines.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = lines.select { |line| line.match?(/\A\s*Running\b/) }
    raise 'phone catalog compiler did not finish exactly one test target' unless
      compiled.length == 1 && compiled.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/)
    raise 'phone catalog execution is not its actual integration target' unless
      executions.length == 1 && executions.first.match?(/\A\s*Running tests\/phone_catalog\.rs \((?:[^\r\n()]+\/)?phone_catalog-[0-9a-f]+\)\z/)
    raise 'phone catalog expected exactly one test execution' unless
      lines.select { |line| line.start_with?('running ') } == ['running 1 test']
    expected_test = "test #{test} ... #{passed ? 'ok' : 'FAILED'}"
    raise 'phone catalog wrong named test' unless
      lines.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_test]
    result_lines = lines.select { |line| line.start_with?('test result:') }
    expected_summary = passed ? /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 26 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 26 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'phone catalog test count/summary differs' unless result_lines.size == 1 && expected_summary.match?(result_lines.first)
    panics = lines.select { |line| line.start_with?("thread '") }
    assertions = lines.select { |line| line.start_with?('assertion ') }
    errors = lines.select { |line| line.start_with?('error') }
    failure_sections = lines.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'phone catalog restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && failure_sections.empty? && !lines.include?('failures:')
    else
      raise 'phone catalog lacks ordinary intended integration assertion failure' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at tests\/phone_catalog\.rs:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        failure_sections == ["---- #{test} stdout ----"] && lines.count('failures:') == 2 &&
        lines.count('    ' + test) == 1 &&
        errors == ['error: test failed, to rerun pass `--test phone_catalog`']
    end
    nil
  end
end

# Importable ordinary --lib assertion decoder for six complete-owner clocked controls.
# This uses the existing disposable-copy producer below, never a second runner.
module BelugaCoreOwnerClockedMutationOracle
  TEST_PATH = 'src/network_adaptation_owner_clocked_events_tests.rs'.freeze
  PREFIX = 'network_adaptation_owner_clocked_events_tests::'.freeze
  CONTROLS = [
    ['OC-REVISION', 'src/native_owner_clock_events.rs', 'owner_clocked',
      'invocation:r.invocation,revision:draft.revision,peer:',
      'invocation:r.invocation,revision:draft.revision.wrapping_add(1),peer:',
      PREFIX + 'product_owner_clocked_202_initial_stop_retains_revision_and_full_owner_tail'],
    ['OC-ROUTE', 'src/native_owner_clock_events.rs', 'owner_clocked',
      'peer_present:draft.policy.peer.is_some() as u32,bound,route,',
      'peer_present:draft.policy.peer.is_some() as u32,bound,route:0,',
      PREFIX + 'product_owner_clocked_212_route_invalidation_advances_and_clears_evidence_not_fast_applied'],
    ['OC-REFUSAL-PUBLICATION', 'src/native_owner_clock_events.rs', 'owner_clocked',
      'Err(status)=>status,',
      'Err(status)=>{unsafe{ptr::write(output_header,codec::Header::default());}status},',
      PREFIX + 'product_owner_clocked_every_lazy_callback_failure_refuses_whole_tuple'],
    ['OC-READ-CORRELATION', 'src/native_clock_assay.rs', 'owner_clocked',
      'reply.invocation != self.invocation || reply.reserved != 0',
      'false || reply.reserved != 0',
      PREFIX + 'product_owner_clocked_reply_correlation_and_native_range_refuse_each_read'],
    ['OC-TIME-MASK', 'src/native_owner_clock_events.rs', 'owner_clocked',
      '202|203|204|205|206|208|209|211|213|215|217=>0x00ef,',
      '202|203|204|205|206|208|209|211|213|215|217=>0x02ef,',
      PREFIX + 'product_owner_clocked_202_initial_stop_retains_revision_and_full_owner_tail'],
    ['OC-CLOSED-OPERATION', 'src/network_adaptation_owner_clocked_events.rs', 'owner_clocked',
      'if !matches!(operation, OWNER_END_SHOW_WITHOUT_REVISION | OWNER_ROUTE_INVALIDATED |',
      'if false && !matches!(operation, OWNER_END_SHOW_WITHOUT_REVISION | OWNER_ROUTE_INVALIDATED |',
      PREFIX + 'product_owner_clocked_policy_only_vote_is_closed_before_decode_or_provider'],
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  # Compare the complete copied source/test input, excluding the generated target.
  # No source restoration or source mutation occurs in this importable method.
  def self.source_fence(root)
    paths = %w[Cargo.toml Cargo.lock rust-toolchain.toml] + %w[src tests].flat_map { |directory|
      Dir.glob(File.join(root, directory, '**', '*'), File::FNM_DOTMATCH)
        .select { |path| File.file?(path) }.map { |path| path.delete_prefix(root + '/') }
    }
    paths.sort.to_h { |path| [path, Digest::SHA256.file(File.join(root, path)).hexdigest] }.freeze
  end

  def self.verify_source_fence!(root, expected)
    raise 'Owner clocked copied source/test input changed' unless source_fence(root) == expected
  end

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Owner clocked outcome is not Boolean' unless passed == true || passed == false
    raise 'Owner clocked intended test is not a named control' unless TESTS.include?(test)
    raise 'Owner clocked timeout is not assertion evidence' unless timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Owner clocked compile/timeout/signal text is not semantic evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Owner clocked result is not the compiled exact singleton library test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running unittests src\/lib\.rs \((?:[^\r\n()]+\/)?beluga_core-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Owner clocked restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Owner clocked lacks the intended ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--lib`']
    end
    nil
  end
end

# Four complete-Owner501 controls use the same disposable-copy producer below.
module BelugaCoreOwnerPrepareMutationOracle
  TEST_PATH = 'src/network_adaptation_owner_prepare_events_tests.rs'.freeze
  PREFIX = 'network_adaptation_owner_prepare_events_tests::'.freeze
  CONTROLS = [
    ['OP-ENTRY-REVISION', 'src/network_adaptation_owner_prepare_events.rs', 'owner_prepare',
      'owner.try_prepare_proposal(r.source_generation, r.expected_revision, entry, report,',
      'owner.try_prepare_proposal(r.source_generation, owner.revision, entry, report,',
      PREFIX + 'product_owner_prepare_zero_read_entry_none'],
    ['OP-REFUSAL-PUBLICATION', 'src/network_adaptation_owner_prepare_events.rs', 'owner_prepare',
      'Err(status) => status,',
      'Err(status) => { unsafe { ptr::write(output_header, codec::Header::default()); } status },',
      PREFIX + 'product_owner_prepare_provider_denial_all_seven_outputs_untouched'],
    ['OP-READ-TRANSCRIPT', 'src/network_adaptation_owner_prepare_events.rs', 'owner_prepare',
      'ptr::copy_nonoverlapping(clock.reads.as_ptr(), reads, read_count as usize);',
      'ptr::write_bytes(reads, 0, read_count as usize);',
      PREFIX + 'product_owner_prepare_late_none_preserves_real_read_transcript'],
    ['OP-TIME-JOURNAL', 'src/network_adaptation_owner_prepare_events.rs', 'owner_prepare',
      'bundle.edits[index] = encode_edit(edit)?;',
      'bundle.edits[index] = Edit::default();',
      PREFIX + 'product_owner_prepare_expiry_full222_literal_tail_and_journals'],
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Owner prepare outcome is not Boolean' unless passed == true || passed == false
    raise 'Owner prepare intended test is not a named control' unless TESTS.include?(test)
    raise 'Owner prepare timeout is not assertion evidence' unless timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Owner prepare compile/timeout/signal text is not semantic evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Owner prepare result is not the compiled exact singleton library test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running unittests src\/lib\.rs \((?:[^\r\n()]+\/)?beluga_core-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Owner prepare restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Owner prepare lacks the intended ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--lib`']
    end
    nil
  end
end

# Four complete-Owner601 controls reuse the same exact singleton/copy/restoration producer.
module BelugaCoreOwnerInactiveMutationOracle
  TEST_PATH = 'src/network_adaptation_owner_inactive_events_tests.rs'.freeze
  PREFIX = 'network_adaptation_owner_inactive_events_tests::'.freeze
  CONTROLS = [
    ['OI-EXPECTED-REVISION', 'src/network_adaptation_owner_inactive_events.rs', 'owner_inactive',
      'current.revision != prepared.expected_revision',
      'current.revision != prepared.applying_revision',
      PREFIX + 'product_owner_inactive_expected_revision_not_applying_and_wrap_once'],
    ['OI-PREPARED-ORIGIN', 'src/network_adaptation_owner_inactive_events.rs', 'owner_inactive',
      'edits[index] = encode_edit(edit)?;',
      'edits[index] = encode_edit(TimeEdit::Retain)?;',
      PREFIX + 'product_owner_inactive_equal_coordinates_import_all_nine_prepared_origins'],
    ['OI-REFUSAL-PUBLICATION', 'src/network_adaptation_owner_inactive_events.rs', 'owner_inactive',
      'Err(status) => status,',
      'Err(status) => { unsafe { ptr::write(output_header, codec::Header::default()); } status },',
      PREFIX + 'product_owner_inactive_each_provider_and_reply_denial_refuses_seven_outputs'],
    ['OI-SUSPENSION-COUNTER', 'src/network_adaptation_owner_inactive_events.rs', 'owner_inactive',
      'draft.try_adopt_inactive(prepared, peer, r.suspended == 1, clock, Dependencies::default())?',
      'draft.try_adopt_inactive(prepared, peer, false, clock, Dependencies::default())?',
      PREFIX + 'product_owner_inactive_healthy_L_read_adopts_or_requests_resume'],
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Owner inactive outcome is not Boolean' unless passed == true || passed == false
    raise 'Owner inactive intended test is not a named control' unless TESTS.include?(test)
    raise 'Owner inactive timeout is not assertion evidence' unless timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Owner inactive compile/timeout/signal text is not semantic evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Owner inactive result is not the compiled exact singleton library test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running unittests src\/lib\.rs \((?:[^\r\n()]+\/)?beluga_core-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Owner inactive restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Owner inactive lacks the intended ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--lib`']
    end
    nil
  end
end

# Eight active-before-await controls use the existing copy/restoration runner.
module BelugaCoreOwnerBeginActiveMutationOracle
  TEST_PATH = 'src/network_adaptation_owner_begin_active_events_tests.rs'.freeze
  PREFIX = 'network_adaptation_owner_begin_active_events_tests::'.freeze
  CONTROLS = [
    ['OA-RESOURCE-GATE', 'src/network_adaptation_candidate/service.rs', 'owner_begin_active',
      'if !resources.present() { return Ok(BeginActive::Return { retained_route_action: retained_route }); }',
      'if false { return Ok(BeginActive::Return { retained_route_action: retained_route }); }',
      PREFIX + 'active_begin_raw_each_missing_resource_returns_before_attempt_consumption'],
    ['OA-FAULT-PREFIX', 'src/network_adaptation_candidate/service.rs', 'owner_begin_active',
      'if prepared.policy.terminal_fault() {',
      'if false {',
      PREFIX + 'active_begin_raw_fault_retains_before_resource_return_without_positive_adoption'],
    ['OA-ATTEMPT-CONSUMPTION', 'src/network_adaptation_candidate/service.rs', 'owner_begin_active',
      'let mut consumption = self.policy; consumption.retain_attempt(prepared.policy);',
      'let consumption = self.policy;',
      PREFIX + 'active_begin_raw_attempt_only_changes_negative_fields_and_applying_revision'],
    ['OA-PROVIDER-STATUS', 'src/native_clock_assay.rs', 'owner_begin_active',
      'if returned != 1 { return Err(3); }',
      'if returned == 0 { return Err(3); }',
      PREFIX + 'active_begin_raw_same_peer_Q_success_and_all_five_new_peer_denial_prefixes'],
    ['OA-PREPARED-BODY', 'src/network_adaptation_owner_begin_active_events.rs', 'owner_begin_active',
      'returned_header = wire.header; returned_atoms.copy_from_slice(&wire.atoms);',
      'returned_header = wire.header; returned_atoms.fill(codec::Atom::default());',
      PREFIX + 'active_begin_raw_no_native_apply_skips_resources_but_changed_forces_return'],
    ['OA-REFUSAL-PUBLICATION', 'src/network_adaptation_owner_begin_active_events.rs', 'owner_begin_active',
      'Err(status) => status,',
      'Err(status) => { unsafe { ptr::write(output_header, codec::Header::default()); } status },',
      PREFIX + 'active_begin_raw_callback_correlation_and_unrepresentable_time_leave_all_nine_outputs'],
    ['OA-JOURNAL-CLEAR', 'src/network_adaptation_owner_begin_active_events.rs', 'owner_begin_active',
      'let mask = if bind_reachable { 0x01ffu16 } else { 0x00efu16 };',
      'let mask = if bind_reachable { 0x01ffu16 } else { 0x00e7u16 };',
      PREFIX + 'active_begin_raw_attempt_only_changes_negative_fields_and_applying_revision'],
    ['OA-OWNER-TAIL', 'src/network_adaptation_owner_begin_active_events.rs', 'owner_begin_active',
      'if owner.atoms[169..] != owner_atoms[169..] { return Err(5); }',
      'if owner.atoms[169..] == owner_atoms[169..] { return Err(5); }',
      PREFIX + 'active_begin_raw_no_invented_revision_peer_or_active_fence_and_exact222'],
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Owner begin-active outcome is not Boolean' unless passed == true || passed == false
    raise 'Owner begin-active intended test is not a named control' unless TESTS.include?(test)
    raise 'Owner begin-active timeout is not assertion evidence' unless timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Owner begin-active compile/timeout/signal text is not semantic evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Owner begin-active result is not the compiled exact singleton library test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running unittests src\/lib\.rs \((?:[^\r\n()]+\/)?beluga_core-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Owner begin-active restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Owner begin-active lacks the intended ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--lib`']
    end
    nil
  end
end

# Eighteen post-await controls keep success, validation, failure and final cuts distinct.
module BelugaCoreOwnerPostAwaitMutationOracle
  CONTROLS = [
  [
    "OCV-STALE", "src/network_adaptation_owner_completion_events.rs", "owner_post_await",
    "if let Some(validator) = validator {",
    "if let Some(validator) = validator.filter(|_| bundle.outcome.disposition != 0) {",
    "network_adaptation_owner_completion_events_tests::active_completion_validated_stale_same_fps_and_missing_thunks_are_explicit"
  ],
  [
    "OCV-SAMEFPS", "src/network_adaptation_owner_completion_events.rs", "owner_post_await",
    "if let Some(validator) = validator {",
    "if let Some(validator) = validator.filter(|_| bundle.outcome.disposition == 0 || bundle.output_fps.is_some()) {",
    "network_adaptation_owner_completion_events_tests::active_completion_validated_stale_same_fps_and_missing_thunks_are_explicit"
  ],
  [
    "OCV-RETURN", "src/network_adaptation_owner_completion_events.rs", "owner_post_await",
    "if accepted != 1 { return 3; }", "if accepted == 0 { return 3; }",
    "network_adaptation_owner_completion_events_tests::active_completion_validated_only_one_accepts_and_denial_never_effects_or_writes"
  ],
  [
    "OCV-HEADER-FIRST", "src/network_adaptation_owner_completion_events.rs", "owner_post_await",
    "    if let Some(validator) = validator {",
    "    if let Some(validator) = validator {\n        unsafe { ptr::write(output_header, bundle.state.header); }",
    "network_adaptation_owner_completion_events_tests::active_completion_validated_only_one_accepts_and_denial_never_effects_or_writes"
  ],
  [
    "OCV-INVOCATION", "src/network_adaptation_owner_completion_events.rs", "owner_post_await",
    "validator(context, request.invocation,", "validator(context, request.invocation.wrapping_add(1),",
    "network_adaptation_owner_completion_events_tests::active_completion_validated_int32_and_invocation_correlation_are_pre_effect"
  ],
  [
    "OCV-FPS-FIRST", "src/network_adaptation_owner_completion_events.rs", "owner_post_await",
    "    if let Some(validator) = validator {\n        let accepted = unsafe { validator(context, request.invocation,\n            &bundle.state.header, bundle.state.atoms.as_ptr(), 179,\n            &bundle.metadata, &bundle.outcome, bundle.edits.as_ptr(), 13,\n            bundle.coordinates.as_ptr(), 13) };\n        if accepted != 1 { return 3; }\n    }\n    // No allocation, fallible validation, await, recheck, or status branch after\n    // an effect. The callback MUST uphold the caller's non-reentry/no-unwind\n    // contract; raw integer ranges cannot prove that or any native identity.\n    if let (Some(fps), Some(callback)) = (bundle.output_fps, callback) {\n        unsafe { callback(context, request.invocation, fps); }\n    }",
    "    if let (Some(fps), Some(callback)) = (bundle.output_fps, callback) {\n        unsafe { callback(context, request.invocation, fps); }\n    }\n    if let Some(validator) = validator {\n        let accepted = unsafe { validator(context, request.invocation,\n            &bundle.state.header, bundle.state.atoms.as_ptr(), 179,\n            &bundle.metadata, &bundle.outcome, bundle.edits.as_ptr(), 13,\n            bundle.coordinates.as_ptr(), 13) };\n        if accepted != 1 { return 3; }\n    }\n    // No allocation, fallible validation, await, recheck, or status branch after\n    // an effect. The callback MUST uphold the caller's non-reentry/no-unwind\n    // contract; raw integer ranges cannot prove that or any native identity.",
    "network_adaptation_owner_completion_events_tests::active_completion_validated_private_full_bundle_precedes_fps_and_all_publication"
  ],
  [
    "OC-FRESH-FENCE",
    "src/network_adaptation_owner_completion_events.rs",
    "owner_post_await",
    "match draft.success_fence(prepared, outcome_facts(r)) {",
    "match draft.success_fence(prepared, outcome_facts(CompletionRequest { facts: 511, ..r })) {",
    "network_adaptation_owner_completion_events_tests::active_completion_raw_all_eleven_success_fences_rollback_without_effect_or_import"
  ],
  [
    "OC-EFFECT-ORDER",
    "src/network_adaptation_owner_completion_events.rs",
    "owner_post_await",
    "    if let (Some(fps), Some(callback)) = (bundle.output_fps, callback) {\n        unsafe { callback(context, request.invocation, fps); }\n    }\n    unsafe {\n        ptr::write(output_header, bundle.state.header);",
    "    unsafe {\n        ptr::write(output_header, bundle.state.header);\n        if let (Some(fps), Some(callback)) = (bundle.output_fps, callback) {\n            callback(context, request.invocation, fps);\n        }",
    "network_adaptation_owner_completion_events_tests::active_completion_raw_callback_carries_exact_invocation_and_fps_before_every_output_write"
  ],
  [
    "OC-LATE-CONVERSION",
    "src/network_adaptation_owner_completion_events.rs",
    "owner_post_await",
    "if let Some(fps) = output_fps { i32::try_from(fps).map_err(|_| 2u32)?; }",
    "let _ = output_fps;",
    "network_adaptation_owner_completion_events_tests::active_completion_raw_int32_conversion_is_only_for_reachable_changed_fps_effect"
  ],
  [
    "OC-APPLIED-PUBLICATION",
    "src/network_adaptation_owner_completion_events.rs",
    "owner_post_await",
    "draft.record_success_after_native_output(accepted);",
    "let _ = accepted;",
    "network_adaptation_owner_completion_events_tests::active_completion_raw_current_success_records_only_applied_without_policy_revision_or_import"
  ],
  [
    "OC-FINAL-FRESH",
    "src/network_adaptation_owner_completion_events.rs",
    "owner_post_await",
    "exact_peer: r.facts == 1,",
    "exact_peer: true,",
    "network_adaptation_owner_completion_events_tests::active_completion_raw_final_adopt_three_stale_fences_preserve_every_owner_word"
  ],
  [
    "OC-FINAL-OPAQUE",
    "src/network_adaptation_owner_completion_events.rs",
    "owner_post_await",
    "if state.atoms[169..] != owner_atoms[169..] { return Err(5); }",
    "if state.atoms[169..] == owner_atoms[169..] { return Err(5); }",
    "network_adaptation_owner_completion_events_tests::active_completion_raw_final_adopt_wraps_once_and_preserves_opaque_applied_ieee_tail"
  ],
  [
    "OF-PREFIX-DISCARD",
    "src/network_adaptation_owner_failure_events.rs",
    "owner_post_await",
    "Err(error) if (2..=4).contains(&error) => (4, 0, error),",
    "Err(error) if (2..=4).contains(&error) => return Err(error),",
    "network_adaptation_owner_failure_events_tests::active_failure_raw_FQ_denials_keep_live_pre_Q_prefix_and_success_alone_finishes_cleanup"
  ],
  [
    "OF-ERROR-REVISION",
    "src/network_adaptation_owner_failure_events.rs",
    "owner_post_await",
    "let complete = semantic_error == 0 && disposition != 0;",
    "let complete = disposition != 0;",
    "network_adaptation_owner_failure_events_tests::active_failure_raw_revision_wrap_waits_for_complete_retention_and_absent_timestamp_stays_absent"
  ],
  [
    "OF-ACCEPTED-ATTEMPT",
    "src/network_adaptation_owner_failure_events.rs",
    "owner_post_await",
    "read_count: clock.native.len as u32,",
    "read_count: clock.attempts,",
    "network_adaptation_owner_failure_events_tests::active_failure_raw_second_rejected_cut_keeps_one_accepted_F_and_exact_pre_Q_state"
  ],
  [
    "OF-PROVIDER-STATUS",
    "src/native_clock_assay.rs",
    "owner_post_await",
    "if returned != 1 { return Err(3); }",
    "if returned == 0 { return Err(3); }",
    "network_adaptation_owner_failure_events_tests::active_failure_raw_provider_denial_correlation_and_bad_coordinate_publish_not_discard_F_prefix"
  ],
  [
    "OF-JOURNAL-CLEAR",
    "src/network_adaptation_owner_failure_events.rs",
    "owner_post_await",
    "TimeEdit::Clear if 0x00efu16 & (1 << index) != 0 => None,",
    "TimeEdit::Clear if 0x00e7u16 & (1 << index) != 0 => None,",
    "network_adaptation_owner_failure_events_tests::active_failure_raw_ordinary_uses_applying_and_retains_only_negative_prefix_without_clocks"
  ],
  [
    "OF-REFUSAL-PUBLICATION",
    "src/network_adaptation_owner_failure_events.rs",
    "owner_post_await",
    "Err(status) => status,",
    "Err(status) => { unsafe { ptr::write(output_header, codec::Header::default()); } status },",
    "network_adaptation_owner_failure_events_tests::active_failure_raw_strict_request_headers_and_all401_atoms_reject_before_any_semantic_prefix"
  ]
].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze
  TEST_PATHS = TESTS.to_h { |test| [test, 'src/' + test.split('::').first + '.rs'] }.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Owner post-await outcome is not Boolean' unless passed == true || passed == false
    raise 'Owner post-await intended test is not a named control' unless TESTS.include?(test)
    raise 'Owner post-await timeout is not assertion evidence' unless timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Owner post-await compile/timeout/signal text is not semantic evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 269 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Owner post-await result is not the compiled exact singleton library test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running unittests src\/lib\.rs \((?:[^\r\n()]+\/)?beluga_core-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Owner post-await restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Owner post-await lacks the intended ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATHS.fetch(test))}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--lib`']
    end
    nil
  end
end

module BelugaCoreMicrophoneRetryMutationOracle
  TEST_PATH = 'tests/microphone_forwarding_retry.rs'.freeze
  SUITE = 'microphone_forwarding_retry'.freeze
  CORRELATION = 'result_correlation_rejects_every_coherent_or_malformed_changed_field'.freeze
  CONTROLS = [
    ['MIC-RETRY-BUDGET', 'src/microphone_forwarding_retry.rs', SUITE,
      '&& old.map_or(true, |h| h.may_retry && h.count < config.maximum_attempt_count));',
      '&& old.map_or(true, |h| h.may_retry && h.count <= config.maximum_attempt_count));',
      'eligibility_preserves_absence_fault_and_strict_budget_boundary'],
    ['MIC-RETRY-ADMISSION', 'src/microphone_forwarding_retry.rs', SUITE,
      "        2 | 3 | 5 | 6 | 9 | 10 => Some(true),\n        1 | 4 | 7 | 8 | 11 => Some(false),",
      "        2 | 3 | 4 | 5 | 6 | 9 | 10 => Some(true),\n        1 | 7 | 8 | 11 => Some(false),",
      'all_eleven_native_failure_categories_have_literal_retry_votes'],
    ['MIC-RETRY-ABSENT', 'src/microphone_forwarding_retry.rs', SUITE,
      'if marked { result.state.may_retry = 1; }',
      "if marked { result.state.may_retry = 1; }\n            else if old.is_none() {\n                result.state = RawState { present: 1, count: 1, ..result.state };\n            }",
      'retry_failure_never_creates_history_or_reopens_a_consumed_budget'],
    ['MIC-RETRY-CONSUME', 'src/microphone_forwarding_retry.rs', SUITE,
      "                present: 1,\n                may_retry: 0,",
      "                present: 1,\n                may_retry: u32::from(old.is_some_and(|h| h.may_retry)),",
      'recording_sets_one_or_increments_and_always_consumes_retry_permission'],
    ['MIC-RETRY-ABSENT-EXHAUST', 'src/microphone_forwarding_retry.rs', SUITE,
      "            if old.is_some() {\n                result.state.may_retry = 0;\n                result.redrive_action = REDRIVE_CLEAR;\n            }",
      "            if old.is_some() {\n                result.state.may_retry = 0;\n            }\n            result.redrive_action = REDRIVE_CLEAR;",
      'exhaust_absent_history_retains_redrive_but_existing_history_clears_it'],
    ['MIC-RETRY-CORRELATION', 'src/microphone_forwarding_retry.rs', SUITE,
      'u32::from(expected.status == STATUS_ACCEPTED && expected == result)',
      'u32::from(expected.status == STATUS_ACCEPTED && result.status == STATUS_ACCEPTED)',
      CORRELATION],
    ['MIC-RETRY-CLEANUP-CORRELATION', 'src/microphone_forwarding_retry.rs', SUITE,
      'u32::from(expected.status == STATUS_ACCEPTED && expected == result)',
      'u32::from(expected.status == STATUS_ACCEPTED && (matches!(event.opcode, OP_RECORD_ATTEMPT | OP_EXHAUST) || expected == result))',
      CORRELATION]
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Mic retry intended method is not a named control' unless TESTS.include?(test)
    raise 'Mic retry outcome/timeout is not exact' unless [true, false].include?(passed) && timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Mic retry compile/timeout/signal text is not assertion evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 9 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 9 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Mic retry result is not the compiled exact singleton integration test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running tests\/microphone_forwarding_retry\.rs \((?:[^\r\n()]+\/)?microphone_forwarding_retry-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Mic retry restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Mic retry lacks the mapped ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--test microphone_forwarding_retry`']
    end
    nil
  end
end


# Additive copied updater admission controls; import-only until runner guard.
module BelugaCoreUpdateAdmissionMutationOracle
  TEST_PATH = 'tests/update_admission.rs'.freeze
  SUITE = 'update_admission'.freeze
  MALFORMED = 'malformed_abi_and_each_unknown_flag_fail_closed'.freeze
  ADMISSION = 'each_owned_activity_and_missing_teardown_or_interactivity_denies_admission'.freeze
  PRECEDENCE = 'release_progress_and_menu_precedence_are_independent_of_admission'.freeze
  CORRELATION = 'every_result_field_corruption_is_rejected_for_every_valid_request'.freeze
  CONTROLS = [
    ['UA-M01', 'src/update_admission.rs', SUITE,
      'if request.abi_version != ABI_VERSION { return invalid; } // UA-M01',
      'if false { return invalid; } // UA-M01', MALFORMED],
    ['UA-M02', 'src/update_admission.rs', SUITE,
      'if request.flags & !KNOWN_FLAGS != 0 { return invalid; } // UA-M02',
      'if false { return invalid; } // UA-M02', MALFORMED],
    ['UA-M03', 'src/update_admission.rs', SUITE,
      'let permits_update = has(flags, INTERACTIVE) // UA-M03',
      'let permits_update = true // UA-M03', ADMISSION],
    ['UA-M04', 'src/update_admission.rs', SUITE,
      '&& !has(flags, ACTIVE_MEDIA) // UA-M04',
      '&& true // UA-M04', ADMISSION],
    ['UA-M05', 'src/update_admission.rs', SUITE,
      '&& !has(flags, PENDING_PAIRING) // UA-M05',
      '&& true // UA-M05', ADMISSION],
    ['UA-M06', 'src/update_admission.rs', SUITE,
      '&& !has(flags, AUDIO_SHARES) // UA-M06',
      '&& true // UA-M06', ADMISSION],
    ['UA-M07', 'src/update_admission.rs', SUITE,
      '&& has(flags, TEARDOWN_COMPLETE); // UA-M07',
      '&& true; // UA-M07', ADMISSION],
    ['UA-M08', 'src/update_admission.rs', SUITE,
      'let is_in_progress = release && (task_present || needs_readiness || failed); // UA-M08',
      'let is_in_progress = task_present || needs_readiness || failed; // UA-M08', PRECEDENCE],
    ['UA-M09', 'src/update_admission.rs', SUITE,
      'let task_present = has(flags, TASK_PRESENT); // UA-M09',
      'let task_present = false; // UA-M09', PRECEDENCE],
    ['UA-M10', 'src/update_admission.rs', SUITE,
      'let needs_readiness = has(flags, NEEDS_READINESS); // UA-M10',
      'let needs_readiness = false; // UA-M10', PRECEDENCE],
    ['UA-M11', 'src/update_admission.rs', SUITE,
      'let failed = has(flags, FAILED); // UA-M11',
      'let failed = false; // UA-M11', PRECEDENCE],
    ['UA-M12', 'src/update_admission.rs', SUITE,
      'KIND_RECOVERY // UA-M12', 'KIND_OWNED // UA-M12', PRECEDENCE],
    ['UA-M13', 'src/update_admission.rs', SUITE,
      'u32::from(expected.status == STATUS_VALID && expected == result) // UA-M13',
      'u32::from(expected.status == STATUS_VALID) // UA-M13', CORRELATION],
    ['UA-M14', 'src/update_admission.rs', SUITE,
      'let can_check = release && !is_in_progress && permits_update; // UA-M14',
      'let can_check = !is_in_progress && permits_update; // UA-M14', PRECEDENCE],
    ['UA-M15', 'src/update_admission.rs', SUITE,
      'KIND_DEVELOPMENT // UA-M15', 'KIND_READY // UA-M15', PRECEDENCE],
    ['UA-M16', 'src/update_admission.rs', SUITE,
      'KIND_OWNED // UA-M16', 'KIND_UNAVAILABLE // UA-M16', PRECEDENCE],
    ['UA-M17', 'src/update_admission.rs', SUITE,
      'KIND_READY // UA-M17', 'KIND_UNAVAILABLE // UA-M17', PRECEDENCE]
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Update admission intended method is not a named control' unless TESTS.include?(test)
    raise 'Update admission outcome/timeout is not exact' unless [true, false].include?(passed) && timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Update admission compile/timeout/signal text is not assertion evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 7 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 7 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Update admission result is not the compiled exact singleton integration test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running tests\/update_admission\.rs \((?:[^\r\n()]+\/)?update_admission-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Update admission restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Update admission lacks the mapped ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--test update_admission`']
    end
    nil
  end
end

# Additive copied two-phase SDK check admission controls; no native authority.
module BelugaCoreUpdateSparkleAdmissionMutationOracle
  TEST_PATH = 'tests/update_sparkle_admission.rs'.freeze
  SUITE = 'update_sparkle_admission'.freeze
  MALFORMED = 'malformed_abi_phase_and_each_phase_specific_unknown_flag_fail_closed'.freeze
  GUARDS = 'each_original_guard_preserves_error_precedence_and_phase_actions'.freeze
  PARITY = 'all_twelve_valid_carriers_match_literal_original_swift_guards'.freeze
  CORRELATION = 'every_result_field_corruption_is_rejected_for_all_valid_requests'.freeze
  CONTROLS = [
    ['USA-M01', 'src/update_sparkle_admission.rs', SUITE,
      '    if request.abi_version != ABI_VERSION { return invalid; } // USA-M01',
      '    if false { return invalid; } // USA-M01', MALFORMED],
    ['USA-M02', 'src/update_sparkle_admission.rs', SUITE,
      '        _ => return invalid, // USA-M02',
      '        _ => ACTION_QUERY_AUTHORITY, // USA-M02', MALFORMED],
    ['USA-M03', 'src/update_sparkle_admission.rs', SUITE,
      '            if request.flags & !PREFLIGHT_KNOWN_FLAGS != 0 { return invalid; } // USA-M03',
      '            if false { return invalid; } // USA-M03', MALFORMED],
    ['USA-M04', 'src/update_sparkle_admission.rs', SUITE,
      '            if request.flags & !AFTER_AUTHORITY_KNOWN_FLAGS != 0 { return invalid; } // USA-M04',
      '            if false { return invalid; } // USA-M04', MALFORMED],
    ['USA-M05', 'src/update_sparkle_admission.rs', SUITE,
      '            if !has(request.flags, EXACT_CALLBACK) { ACTION_FOREIGN } // USA-M05',
      '            if false { ACTION_FOREIGN } // USA-M05', GUARDS],
    ['USA-M06', 'src/update_sparkle_admission.rs', SUITE,
      '            else if !has(request.flags, MANUAL_UPDATES) { ACTION_NON_MANUAL } // USA-M06',
      '            else if false { ACTION_NON_MANUAL } // USA-M06', GUARDS],
    ['USA-M07', 'src/update_sparkle_admission.rs', SUITE,
      '            else if !has(request.flags, PRE_CALLBACK_RUNNING) { ACTION_AUTHORITY_NOT_RETAINED } // USA-M07',
      '            else if false { ACTION_AUTHORITY_NOT_RETAINED } // USA-M07', GUARDS],
    ['USA-M08', 'src/update_sparkle_admission.rs', SUITE,
      '            else { ACTION_QUERY_AUTHORITY } // USA-M08',
      '            else { ACTION_CONSUME_AND_ADMIT } // USA-M08', GUARDS],
    ['USA-M09', 'src/update_sparkle_admission.rs', SUITE,
      '            if !has(request.flags, RETAINED_AUTHORITY) { ACTION_AUTHORITY_NOT_RETAINED } // USA-M09',
      '            if false { ACTION_AUTHORITY_NOT_RETAINED } // USA-M09', GUARDS],
    ['USA-M10', 'src/update_sparkle_admission.rs', SUITE,
      '            else if !has(request.flags, FRESH_REQUESTED) { ACTION_CHECK_NOT_REQUESTED } // USA-M10',
      '            else if false { ACTION_CHECK_NOT_REQUESTED } // USA-M10', GUARDS],
    ['USA-M11', 'src/update_sparkle_admission.rs', SUITE,
      '            else { ACTION_CONSUME_AND_ADMIT } // USA-M11',
      '            else { ACTION_QUERY_AUTHORITY } // USA-M11', GUARDS],
    ['USA-M12', 'src/update_sparkle_admission.rs', SUITE,
      '        status: STATUS_INVALID, // USA-M12',
      '        status: STATUS_VALID, // USA-M12', MALFORMED],
    ['USA-M13', 'src/update_sparkle_admission.rs', SUITE,
      '        action: ACTION_NONE, // USA-M13',
      '        action: ACTION_CONSUME_AND_ADMIT, // USA-M13', MALFORMED],
    ['USA-M14', 'src/update_sparkle_admission.rs', SUITE,
      '        status: STATUS_VALID, // USA-M14',
      '        status: STATUS_INVALID, // USA-M14', PARITY],
    ['USA-M15', 'src/update_sparkle_admission.rs', SUITE,
      '    u32::from(input_is_valid && expected == result) // USA-M15',
      '    u32::from(input_is_valid) // USA-M15', CORRELATION],
    ['USA-M16', 'src/update_sparkle_admission.rs', SUITE,
      '    let input_is_valid = expected.status == STATUS_VALID; // USA-M16',
      '    let input_is_valid = true; // USA-M16', MALFORMED],
    ['USA-M17', 'src/update_sparkle_admission.rs', SUITE,
      '        abi_version: ABI_VERSION, // USA-M17',
      '        abi_version: ABI_VERSION + 1, // USA-M17', PARITY]
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Update Sparkle admission intended method is not a named control' unless TESTS.include?(test)
    raise 'Update Sparkle admission outcome/timeout is not exact' unless [true, false].include?(passed) && timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Update Sparkle admission compile/timeout/signal text is not assertion evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 7 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 7 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Update Sparkle admission result is not the compiled exact singleton integration test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running tests\/update_sparkle_admission\.rs \((?:[^\r\n()]+\/)?update_sparkle_admission-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Update Sparkle admission restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Update Sparkle admission lacks the mapped ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--test update_sparkle_admission`']
    end
    nil
  end
end

# Additive copied Mac source/position controls; identity/effects remain native.
module BelugaCoreHandoffSourceMutationOracle
  TEST_PATH = 'tests/handoff_source_position.rs'.freeze
  SUITE = 'handoff_source_position'.freeze
  FLAGS = 'every_native_flag_combination_preserves_missing_and_identity_refusals'.freeze
  SCALAR = 'preparation_scalar_edges_and_nonfinite_values_match_frozen_swift'.freeze
  MATCH = 'changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift'.freeze
  DRIFT = 'exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct'.freeze
  CLOCK = 'page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain'.freeze
  EXPORT = 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal'.freeze
  ALLOW = 'handoff_source_position::RawDecision { abi_version: 1, status: 1, allowed: 1, reserved: 0 }'.freeze
  CONTROLS = [
    ['prepare-rate-ceiling-widened', 'src/handoff_source_position.rs', SUITE, 'rate <= 16.0', 'rate <= 32.0', SCALAR],
    ['match-rate-equality-bypassed', 'src/handoff_source_position.rs', SUITE,
      '&& number(raw.current_rate) == number(raw.anchor_rate)', '&& true', MATCH],
    ['mac-drift-widened', 'src/handoff_source_position.rs', SUITE,
      '(position - (number(raw.anchor_position) + elapsed * number(raw.anchor_rate))).abs() <= 1.0',
      '(position - (number(raw.anchor_position) + elapsed * number(raw.anchor_rate))).abs() <= 2.0', DRIFT],
    ['phone-drift-widened', 'src/handoff_source_position.rs', SUITE,
      '(position - number(raw.phone_position)).abs() <= 2.0', '(position - number(raw.phone_position)).abs() <= 3.0', DRIFT],
    ['expiry-inclusive', 'src/handoff_source_position.rs', SUITE, 'elapsed < 30.0', 'elapsed <= 30.0', CLOCK],
    ['page-clock-wrong-unit', 'src/handoff_source_position.rs', SUITE, '/ 1000.0', '/ 1.0', CLOCK],
    ['prepare-position-presence-ignored', 'src/handoff_source_position.rs', SUITE,
      'raw.flags == PREPARE_FLAGS', '(raw.flags & !64) == (PREPARE_FLAGS & !64)', FLAGS],
    ['match-duration-presence-ignored', 'src/handoff_source_position.rs', SUITE,
      'raw.flags == MATCH_FLAGS', '(raw.flags & !32) == (MATCH_FLAGS & !32)', FLAGS],
    ['continuity-identity-ignored', 'src/handoff_source_position.rs', SUITE,
      'raw.flags == MATCH_FLAGS', '(raw.flags & !1) == (MATCH_FLAGS & !1)', FLAGS],
    ['video-identity-ignored', 'src/handoff_source_position.rs', SUITE,
      'raw.flags == MATCH_FLAGS', '(raw.flags & !2) == (MATCH_FLAGS & !2)', FLAGS],
    ['prepare-NaN-duration-accepted', 'src/handoff_source_position.rs', SUITE,
      'let duration = number(raw.duration);',
      'let duration = number(raw.duration); if duration.is_nan() { return decision(true); }', SCALAR],
    ['match-NaN-position-accepted', 'src/handoff_source_position.rs', SUITE,
      'let position = number(raw.current_position);',
      'let position = number(raw.current_position); if position.is_nan() { return decision(true); }', MATCH],
    ['actual-c-prepare-bypassed', 'src/lib.rs', SUITE,
      "    handoff_source_position::prepare(raw)\n}", "    #{ALLOW}\n}", EXPORT],
    ['actual-c-matches-bypassed', 'src/lib.rs', SUITE,
      "    handoff_source_position::matches(raw)\n}", "    #{ALLOW}\n}", EXPORT],
    ['actual-c-prepare-validator-bypassed', 'src/lib.rs', SUITE,
      'handoff_source_position::prepare_result_is_valid(raw, output)', '1', EXPORT],
    ['actual-c-matches-validator-bypassed', 'src/lib.rs', SUITE,
      'handoff_source_position::matches_result_is_valid(raw, output)', '1', EXPORT]
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Handoff source intended method is not a named control' unless TESTS.include?(test)
    raise 'Handoff source outcome/timeout is not exact' unless [true, false].include?(passed) && timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Handoff source compile/timeout/signal text is not assertion evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 10 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 10 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Handoff source result is not the compiled exact singleton integration test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running tests\/handoff_source_position\.rs \((?:[^\r\n()]+\/)?handoff_source_position-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Handoff source restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Handoff source lacks the mapped ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--test handoff_source_position`']
    end
    nil
  end
end

# Additive copied input-lease controls; native lease ownership/effects stay outside Rust.
module BelugaCoreMicrophoneInputLeaseMutationOracle
  TEST_PATH = 'tests/microphone_input_lease.rs'.freeze
  SUITE = 'microphone_input_lease'.freeze
  CONTROLS = [
    ['MIC-INPUT-ACQUIRE-BUDGET', 'src/microphone_input_lease.rs', SUITE,
      'if facts.attempt_count < facts.maximum_attempt_count { ACQUIRE }',
      'if facts.attempt_count <= facts.maximum_attempt_count { ACQUIRE }',
      'input_lease_acquisition_budget_preserves_literal_one_and_three_caps'],
    ['MIC-INPUT-ACQUIRED', 'src/microphone_input_lease.rs', SUITE,
      '1 => AUTHORIZE_ACQUIRED,', '1 => TERMINAL_ACQUISITION,',
      'input_lease_acquisition_native_outcomes_have_three_literal_actions'],
    ['MIC-INPUT-RELEASE-BUDGET', 'src/microphone_input_lease.rs', SUITE,
      'if facts.disposition == 2 && facts.attempt_count < facts.maximum_attempt_count {',
      'if facts.disposition == 2 && facts.attempt_count <= facts.maximum_attempt_count {',
      'input_lease_release_continuation_requires_retryable_and_strict_budget'],
    ['MIC-INPUT-FALLBACK', 'src/microphone_input_lease.rs', SUITE,
      '0 => USE_NATIVE_FALLBACK,', '0 => RELEASED,',
      'input_lease_release_outcome_preserves_native_fallback_and_external_result'],
    ['MIC-INPUT-CLOSED-WIRE', 'src/microphone_input_lease.rs', SUITE,
      'if facts.abi_version != ABI_VERSION || facts.reserved != 0 {',
      'if false {',
      'input_lease_closed_wire_rejects_all_unused_and_negative_domains'],
    ['MIC-INPUT-WHOLE-RESULT', 'src/microphone_input_lease.rs', SUITE,
      'u32::from(expected.status == 1 && result == expected)',
      'u32::from(expected.status == 1)',
      'input_lease_verifier_rejects_each_field_and_coherent_cross_operation_results'],
    ['MIC-INPUT-C-PRODUCER', 'src/lib.rs', SUITE,
      "    microphone_input_lease::decide(facts)\n}",
      "    microphone_input_lease::RawResult { abi_version: 1, status: 0, opcode: 0, action: 0, reserved: 0 }\n}",
      'input_lease_actual_c_exports_correlate_accepted_and_refused_results'],
    ['MIC-INPUT-C-VERIFIER', 'src/lib.rs', SUITE,
      'microphone_input_lease::result_is_valid(facts, result)', '1',
      'input_lease_actual_c_exports_correlate_accepted_and_refused_results']
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Input lease intended method is not a named control' unless TESTS.include?(test)
    raise 'Input lease outcome/timeout is not exact' unless [true, false].include?(passed) && timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Input lease compile/timeout/signal text is not assertion evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 7 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 7 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Input lease result is not the compiled exact singleton integration test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running tests\/microphone_input_lease\.rs \((?:[^\r\n()]+\/)?microphone_input_lease-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Input lease restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Input lease lacks the mapped ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--test microphone_input_lease`']
    end
    nil
  end
end

# Additive copied output-format controls; native getters and queue effects stay outside Rust.
module BelugaCoreMicrophoneOutputFormatMutationOracle
  TEST_PATH = 'tests/microphone_output_format.rs'.freeze
  SUITE = 'microphone_output_format'.freeze
  CONTROLS = [
    ['MIC-OUTPUT-FORMAT-CLOSED-WIRE', 'src/microphone_output_format.rs', SUITE,
      'if facts.abi_version != ABI_VERSION || facts.wire_reserved != 0 { return invalid(); }',
      'if false { return invalid(); }',
      'output_format_malformed_wire_is_not_an_ordinary_policy_rejection'],
    ['MIC-OUTPUT-FORMAT-FIRST-GUARD', 'src/microphone_output_format.rs', SUITE,
      "    if facts.stream_description_status != 0 {\n        return rejection(STREAM_DESCRIPTION_STATUS, facts.stream_description_status, 0, 0);\n    }\n    if facts.device_sample_rate_status != 0 {\n        return rejection(DEVICE_SAMPLE_RATE_STATUS, facts.device_sample_rate_status, 0, 0);\n    }",
      "    if facts.device_sample_rate_status != 0 {\n        return rejection(DEVICE_SAMPLE_RATE_STATUS, facts.device_sample_rate_status, 0, 0);\n    }\n    if facts.stream_description_status != 0 {\n        return rejection(STREAM_DESCRIPTION_STATUS, facts.stream_description_status, 0, 0);\n    }",
      'output_format_every_simultaneous_error_pair_preserves_first_guard'],
    ['MIC-OUTPUT-FORMAT-RATE-EXACT', 'src/microphone_output_format.rs', SUITE,
      'if f64::from_bits(facts.stream_sample_rate_bits) != REQUIRED_SAMPLE_RATE {',
      'if (f64::from_bits(facts.stream_sample_rate_bits) - REQUIRED_SAMPLE_RATE).abs() > 1.0 {',
      'output_format_rates_use_numeric_equality_but_rejections_keep_original_bits'],
    ['MIC-OUTPUT-FORMAT-SIGNED-STATUS', 'src/microphone_output_format.rs', SUITE,
      'actual_core_audio_status: status, actual_u32: word,',
      'actual_core_audio_status: status as u16 as i32, actual_u32: word,',
      'output_format_four_signed_statuses_preserve_negative_and_extreme_values'],
    ['MIC-OUTPUT-FORMAT-FULL-U32', 'src/microphone_output_format.rs', SUITE,
      'actual_core_audio_status: status, actual_u32: word,',
      'actual_core_audio_status: status, actual_u32: word as u16 as u32,',
      'output_format_integer_fields_are_exact_not_masks_ranges_or_truncated_values'],
    ['MIC-OUTPUT-FORMAT-WHOLE-RESULT', 'src/microphone_output_format.rs', SUITE,
      'u32::from(expected.status == 1 && result == expected)',
      'u32::from(expected.status == 1)',
      'output_format_authoritative_verifier_rejects_corruption_of_every_result_field'],
    ['MIC-OUTPUT-FORMAT-C-PRODUCER', 'src/lib.rs', SUITE,
      "    microphone_output_format::decide(facts)\n}",
      "    microphone_output_format::RawResult { abi_version: 1, ..Default::default() }\n}",
      'output_format_actual_c_exports_correlate_success_rejection_and_refusal'],
    ['MIC-OUTPUT-FORMAT-C-VERIFIER', 'src/lib.rs', SUITE,
      'microphone_output_format::result_is_valid(facts, result)', '1',
      'output_format_actual_c_exports_correlate_success_rejection_and_refusal']
  ].map(&:freeze).freeze
  NAMES = CONTROLS.map(&:first).freeze
  TESTS = CONTROLS.map(&:last).uniq.freeze

  def self.validate!(combined, test, passed:, exitstatus:, termsig:, timed_out:)
    raise 'Output format intended method is not a named control' unless TESTS.include?(test)
    raise 'Output format outcome/timeout is not exact' unless [true, false].include?(passed) && timed_out == false
    BelugaCoreUpdaterMutationOracle.validate_exit!(exitstatus, termsig, passed ? 0 : 101)
    values = BelugaCoreUpdaterMutationOracle.lines(combined)
    raise 'Output format compile/timeout/signal text is not assertion evidence' if values.any? { |line|
      line.include?('could not compile') || line.match?(/\b(?:skipped|timeout|timed\s*out|killed|aborted|signal)\b/i)
    }
    finished = values.select { |line| line.match?(/\A\s*Finished\b/) }
    executions = values.select { |line| line.match?(/\A\s*Running\b/) }
    expected_case = 'test ' + test + (passed ? ' ... ok' : ' ... FAILED')
    expected_summary = passed ?
      /\Atest result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; 11 filtered out; finished in \d+(?:\.\d+)?s\z/ :
      /\Atest result: FAILED\. 0 passed; 1 failed; 0 ignored; 0 measured; 11 filtered out; finished in \d+(?:\.\d+)?s\z/
    raise 'Output format result is not the compiled exact singleton integration test' unless
      finished.length == 1 && finished.first.match?(/\A\s*Finished `test` profile \[[^\r\n]+\] target\(s\) in (?:\d+(?:\.\d+)?s|[1-9]\d*m [0-5]?\ds)\z/) &&
      executions.length == 1 && executions.first.match?(/\A\s*Running tests\/microphone_output_format\.rs \((?:[^\r\n()]+\/)?microphone_output_format-[0-9a-f]+\)\z/) &&
      values.select { |line| line.start_with?('running ') } == ['running 1 test'] &&
      values.select { |line| line.match?(/\Atest \S+ \.\.\. /) } == [expected_case] &&
      values.select { |line| line.start_with?('test result:') }.then { |lines| lines.length == 1 && expected_summary.match?(lines.first) }
    panics = values.select { |line| line.start_with?("thread '") }
    assertions = values.select { |line| line.start_with?('assertion ') }
    errors = values.select { |line| line.start_with?('error') }
    sections = values.select { |line| line.match?(/\A---- \S+ stdout ----\z/) }
    if passed
      raise 'Output format restored baseline retained failure/error' unless
        panics.empty? && assertions.empty? && errors.empty? && sections.empty? && !values.include?('failures:')
    else
      raise 'Output format lacks the mapped ordinary equality assertion' unless
        panics.length == 1 && panics.first.match?(/\Athread '#{Regexp.escape(test)}'(?: \(\d+\))? panicked at #{Regexp.escape(TEST_PATH)}:\d+:\d+:\z/) &&
        assertions.length == 1 && assertions.first.match?(/\Aassertion `left == right` failed(?:: [^\r\n]*)?\z/) &&
        sections == ["---- #{test} stdout ----"] && values.count('failures:') == 2 &&
        values.count('    ' + test) == 1 && errors == ['error: test failed, to rerun pass `--test microphone_output_format`']
    end
    nil
  end
end


if __FILE__ == $PROGRAM_NAME
queue_only = ARGV == ['--packet-send-queue-only']
rtt_only = ARGV == ['--rtt-evidence-only']
tier_demand_only = ARGV == ['--tier-demand-only']
media_command_gate_only = ARGV == ['--media-command-gate-only']
screen_suspension_only = ARGV == ['--screen-suspension-only']
phone_catalog_only = ARGV == ['--phone-catalog-only']
owner_clocked_only = ARGV == ['--owner-clocked-events-only']
owner_prepare_only = ARGV == ['--owner-prepare-events-only']
owner_inactive_only = ARGV == ['--owner-inactive-events-only']
owner_begin_active_only = ARGV == ['--owner-begin-active-events-only']
owner_post_await_only = ARGV == ['--owner-post-await-events-only']
microphone_retry_only = ARGV == ['--microphone-forwarding-retry-only']
update_admission_only = ARGV == ['--update-admission-only']
update_sparkle_admission_only = ARGV == ['--update-sparkle-admission-only']
handoff_source_only = ARGV == ['--handoff-source-only']
microphone_input_lease_only = ARGV == ['--microphone-input-lease-only']
microphone_output_format_only = ARGV == ['--microphone-output-format-only']
updater_only = BelugaCoreUpdaterMutationOracle.updater_only?(queue_only || rtt_only || tier_demand_only || media_command_gate_only || screen_suspension_only || phone_catalog_only || owner_clocked_only || owner_prepare_only || owner_inactive_only || owner_begin_active_only || owner_post_await_only || microphone_retry_only || update_admission_only || update_sparkle_admission_only || handoff_source_only || microphone_input_lease_only || microphone_output_format_only ? [] : ARGV)
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
   'every_pending_failure_retains_proof_but_becomes_unknown_terminal'],
  ["invitation-phase-before-owner-and-consumed", 'src/invitation_acceptance.rs', 'invitation_acceptance',
   "if !matches || admission_consumed {", "if phase(event.phase).is_none() { return output(raw, Status::InvalidInput); }\n    if !matches || admission_consumed {",
   "foreign_admission_ignores_phase_before_any_error"],
  ["invitation-nil-admission-not-consumed", 'src/invitation_acceptance.rs', 'invitation_acceptance',
   "// MUTATION_ANCHOR: nil_admission_consumes\n                changed(success, false)", "// MUTATION_ANCHOR: nil_admission_consumes\n                changed(state, false)",
   "nil_admission_callback_still_consumes_after_accepted_issued"],
  ["invitation-prepared-state-committed-prematurely", 'src/invitation_acceptance.rs', 'invitation_acceptance',
   "let mut result = output(state.raw(), Status::NeedsCallback);", "let mut result = output(success.raw(), Status::NeedsCallback);",
   "callback_preparation_never_consumes_before_native_success"],
  ["invitation-thrown-callback-consumes", 'src/invitation_acceptance.rs', 'invitation_acceptance',
   "output(raw, Status::CallbackFailed)", "output(success.raw(), Status::CallbackFailed)",
   "thrown_admission_callback_remains_armed_retryable"],
  ["invitation-completion-requires-admission", 'src/invitation_acceptance.rs', 'invitation_acceptance',
   "prepared(state, CallbackKind::Completion, State::Idle)", "if raw.flags & ADMISSION_CONSUMED == 0 { output(raw, Status::Ignored) } else { prepared(state, CallbackKind::Completion, State::Idle) }",
   "active_completion_does_not_require_admission"],
  ["invitation-arm-keeps-consumed", 'src/invitation_acceptance.rs', 'invitation_acceptance',
   "changed(State::Armed { has_admission_callback: present, admission_consumed: false }, false)", "changed(State::Armed { has_admission_callback: present, admission_consumed: raw.flags & ADMISSION_CONSUMED != 0 }, false)",
   "arm_replaces_optional_callback_and_resets_consumed"],
  ["invitation-foreign-cancellation-clears-owner", 'src/invitation_acceptance.rs', 'invitation_acceptance',
   "Some(true) if state != State::Idle => changed(State::Idle, false),", "Some(_) if state != State::Idle => changed(State::Idle, false),",
   "cancellation_is_exact_and_rearm_cannot_be_cancelled_by_foreign_owner"],
  ["invitation-native-prepared-owner-ignored", 'src/invitation_acceptance.rs', 'invitation_acceptance',
   "if !owner_matches {", "if false {",
   "stale_callback_ack_rejects_same_flags_rearm_native_owner_mismatch"],
  ["invitation-success-callback-not-committed", 'src/invitation_acceptance.rs', 'invitation_acceptance',
   "changed(success, event.prepared_kind == CallbackKind::Completion as u32)", "changed(state, event.prepared_kind == CallbackKind::Completion as u32)",
   "successful_completion_clears_owner_callbacks_and_consumed"]
]
# Existing producer/gate exact ordinary assertion requirements remain unchanged.
mutants.concat([
  [
    "replay-zero-clamped",
    "src/replay_policy.rs",
    "replay_policy",
    "Self::Empty => (Self::Populated {\n                highest: input,",
    "Self::Empty => (Self::Populated {\n                highest: Sequence(input.0.max(1)),",
    "bounded_event_traces_match_frozen_original_at_every_step"
  ],
  [
    "replay-maximum-clamped",
    "src/replay_policy.rs",
    "replay_policy",
    "Self::Empty => (Self::Populated {\n                highest: input,",
    "Self::Empty => (Self::Populated {\n                highest: Sequence(input.0.min(u64::MAX - 1)),",
    "bounded_event_traces_match_frozen_original_at_every_step"
  ],
  [
    "replay-age63-refused",
    "src/replay_policy.rs",
    "replay_policy",
    "if age >= WINDOW_SIZE {",
    "if age >= WINDOW_SIZE - 1 {",
    "bounded_event_traces_match_frozen_original_at_every_step"
  ],
  [
    "replay-advance63-clears-history",
    "src/replay_policy.rs",
    "replay_policy",
    "if distance >= WINDOW_SIZE {",
    "if distance >= WINDOW_SIZE - 1 {",
    "bounded_event_traces_match_frozen_original_at_every_step"
  ],
  [
    "replay-duplicate-bit-ignored",
    "src/replay_policy.rs",
    "replay_policy",
    "if received.0.get() & mask != 0 {",
    "if received.0.get() & mask != 0 && false {",
    "bounded_event_traces_match_frozen_original_at_every_step"
  ],
  [
    "replay-short-advance-clears-history",
    "src/replay_policy.rs",
    "replay_policy",
    "(received.0.get() << distance) | 1",
    "{ let _ = received; 1 }",
    "bounded_event_traces_match_frozen_original_at_every_step"
  ],
  [
    "replay-reorder-clears-history",
    "src/replay_policy.rs",
    "replay_policy",
    "received.0.get() | mask",
    "mask | 1",
    "bounded_event_traces_match_frozen_original_at_every_step"
  ],
  [
    "replay-unknown-abi-resets-state",
    "src/replay_policy.rs",
    "replay_policy",
    "if abi_version != ABI_VERSION {\n        return RawResult { state: before, decision: Decision::InvalidInput as u32, reserved: 0 };\n    }",
    "if abi_version != ABI_VERSION {\n        return RawResult { state: initial(), decision: Decision::InvalidInput as u32, reserved: 0 };\n    }",
    "unknown_abi_rejects_without_canonicalizing_or_resetting"
  ],
  [
    "replay-malformed-state-resets-history",
    "src/replay_policy.rs",
    "replay_policy",
    "let Some(state) = ReplayState::from_raw(before) else {\n        return RawResult { state: before, decision: Decision::InvalidInput as u32, reserved: 0 };\n    };",
    "let Some(state) = ReplayState::from_raw(before) else {\n        return RawResult { state: initial(), decision: Decision::InvalidInput as u32, reserved: 0 };\n    };",
    "malformed_raw_state_is_unchanged_and_never_accepted"
  ],
  [
    "replay-populated-bit-zero-ignored",
    "src/replay_policy.rs",
    "replay_policy",
    "1 if raw.bitmap & 1 == 1 => {",
    "1 if raw.bitmap != 0 => {",
    "malformed_raw_state_is_unchanged_and_never_accepted"
  ],
  [
    "replay-impossible-past-bits-ignored",
    "src/replay_policy.rs",
    "replay_policy",
    "if raw.bitmap & !representable != 0 {",
    "if raw.bitmap & !representable != 0 && false {",
    "malformed_raw_state_is_unchanged_and_never_accepted"
  ]
])
mutants.concat([
  ["checkpoint-revoked-add-admitted", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "Operation::Add { owner } => {\n                if matches!(self.retirement, Retirement::Revoked)", "Operation::Add { owner } => {\n                if (matches!(self.retirement, Retirement::Revoked) && false)", "checkpoint_revocation_is_terminal_without_erasing_binding"],
  ["checkpoint-add-owner-bypassed", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "Operation::Add { owner } => {\n                if matches!(self.retirement, Retirement::Revoked)\n                    || matches!(owner, OwnerValidity::Invalid)", "Operation::Add { owner } => {\n                if matches!(self.retirement, Retirement::Revoked)\n                    || (matches!(owner, OwnerValidity::Invalid) && false)", "checkpoint_all_valid_states_and_boolean_facts_match_original"],
  ["checkpoint-update-owner-bypassed", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "Operation::Update { owner, binding } => {\n                if matches!(self.retirement, Retirement::Revoked)\n                    || matches!(owner, OwnerValidity::Invalid)", "Operation::Update { owner, binding } => {\n                if matches!(self.retirement, Retirement::Revoked)\n                    || (matches!(owner, OwnerValidity::Invalid) && false)", "checkpoint_all_valid_states_and_boolean_facts_match_original"],
  ["checkpoint-second-add-admitted", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "                    || matches!(self.binding, Binding::Present) {", "                    || (matches!(self.binding, Binding::Present) && false) {", "checkpoint_all_valid_states_and_boolean_facts_match_original"],
  ["checkpoint-update-tuple-bypassed", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "                    || matches!(binding, BindingMatch::Different) {", "                    || (matches!(binding, BindingMatch::Different) && false) {", "checkpoint_all_valid_states_and_boolean_facts_match_original"],
  ["checkpoint-readback-snapshot-bypassed", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "                if matches!(snapshot, SnapshotMatch::Different) {", "                if matches!(snapshot, SnapshotMatch::Different) && false {", "checkpoint_readback_ignores_revocation_and_owner_but_requires_snapshot"],
  ["checkpoint-revoke-erases-binding", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "Self { retirement: Retirement::Revoked, ..self }, Decision::Allowed,", "Self { binding: Binding::Empty, retirement: Retirement::Revoked }, Decision::Allowed,", "checkpoint_revocation_is_terminal_without_erasing_binding"],
  ["checkpoint-unknown-opcode-admitted", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "3 => Some(Self::Readback { snapshot }),\n            _ => None,", "3 => Some(Self::Readback { snapshot }),\n            _ => Some(Self::Revoke),", "checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed"],
  ["checkpoint-unknown-flags-admitted", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "if raw.abi_version != ABI_VERSION || raw.flags & !KNOWN_FLAGS != 0 {", "if raw.abi_version != ABI_VERSION {", "checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed"],
  ["checkpoint-unknown-abi-admitted", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "if abi_version != ABI_VERSION { return refused(); }", "if abi_version == ABI_VERSION.wrapping_add(1024) { return refused(); }", "checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed"],
  ["checkpoint-unbound-update-admitted", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "                    || matches!(self.binding, Binding::Empty)", "                    || (matches!(self.binding, Binding::Empty) && false)", "checkpoint_all_valid_states_and_boolean_facts_match_original"],
  ["checkpoint-revoked-readback-denied", "src/pairing_catalog_checkpoint.rs", "pairing_catalog_checkpoint", "if matches!(snapshot, SnapshotMatch::Different) {", "if matches!(snapshot, SnapshotMatch::Different) || matches!(self.retirement, Retirement::Revoked) {", "checkpoint_readback_ignores_revocation_and_owner_but_requires_snapshot"]
])
mutants.concat([
  ["reconnect-outbound-zero-refused", "src/reconnect_counters.rs", "reconnect_counters",
   "if raw.abi_version != ABI_VERSION || raw.reserved != 0 { return None; }",
   "if raw.abi_version != ABI_VERSION || raw.reserved != 0 || raw.next_outbound == 0 { return None; }",
   "reconnect_outbound_zero_and_maximum_preserve_native_ordering"],
  ["reconnect-outbound-maximum-wraps", "src/reconnect_counters.rs", "reconnect_counters",
   "if self.outbound.0 == u64::MAX {\n                    return (self, Decision::SequenceExhausted);\n                }",
   "if self.outbound.0 == u64::MAX {\n                    return (Self { outbound: OutboundSequence(0), ..self }, Decision::Proposed);\n                }",
   "reconnect_outbound_zero_and_maximum_preserve_native_ordering"],
  ["reconnect-outbound-increment-removed", "src/reconnect_counters.rs", "reconnect_counters",
   "outbound: OutboundSequence(self.outbound.0 + 1),", "outbound: self.outbound,",
   "reconnect_all_bounded_numeric_inputs_match_original"],
  ["reconnect-equal-inbound-admitted", "src/reconnect_counters.rs", "reconnect_counters",
   "if incoming.0 <= self.highest.0 {", "if incoming.0 < self.highest.0 {",
   "reconnect_inbound_strict_newer_includes_authenticated_maximum"],
  ["reconnect-inbound-highwater-removed", "src/reconnect_counters.rs", "reconnect_counters",
   "highest: AcceptedPeerSequence(incoming.0),", "highest: self.highest,",
   "reconnect_inbound_strict_newer_includes_authenticated_maximum"],
  ["reconnect-outbound-resets-inbound", "src/reconnect_counters.rs", "reconnect_counters",
   "highest: self.highest,", "highest: AcceptedPeerSequence(0),",
   "reconnect_opposite_counters_never_change"],
  ["reconnect-inbound-resets-outbound", "src/reconnect_counters.rs", "reconnect_counters",
   "outbound: self.outbound,", "outbound: OutboundSequence(0),",
   "reconnect_opposite_counters_never_change"],
  ["reconnect-unknown-abi-admitted", "src/reconnect_counters.rs", "reconnect_counters",
   "if abi_version != ABI_VERSION { return refused(); }",
   "if abi_version == ABI_VERSION.wrapping_add(1024) { return refused(); }",
   "reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed"],
  ["reconnect-state-reserved-ignored", "src/reconnect_counters.rs", "reconnect_counters",
   "if raw.abi_version != ABI_VERSION || raw.reserved != 0 { return None; }",
   "if raw.abi_version != ABI_VERSION { return None; }",
   "reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed"],
  ["reconnect-event-reserved-ignored", "src/reconnect_counters.rs", "reconnect_counters",
   "if raw.reserved != 0 { return None; }", "if raw.reserved != 0 && false { return None; }",
   "reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed"],
  ["reconnect-unknown-opcode-admitted", "src/reconnect_counters.rs", "reconnect_counters",
   "_ => None,", "_ => Some(Self::ReserveOutbound),",
   "reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed"],
  ["reconnect-unused-outbound-sequence-admitted", "src/reconnect_counters.rs", "reconnect_counters",
   "0 if raw.request_sequence == 0 => Some(Self::ReserveOutbound),", "0 => Some(Self::ReserveOutbound),",
   "reconnect_outbound_unused_request_sequence_is_rejected"]
])
# Pairing commit behavioral controls: every mutation must compile and fail its mapped assertion.
mutants.concat([
  ["pairing-commit-issued-cached-ack-skips-auth", "src/pairing_commit.rs", "pairing_commit",
   "return self.ready(Action::ExactCachedCommit, AuthPhase::Proposal);",
   "return self.ready(Action::ExactCachedCommit, AuthPhase::None);",
   "pairing_commit_ack_cached_replay_still_authenticates_and_does_not_tighten_cache"],
  ["pairing-commit-host-ack-replay-drops-cache", "src/pairing_commit.rs", "pairing_commit",
   "return self.ready(Action::None, AuthPhase::Acknowledgement);",
   "return Self { cached: Absent, ..self }.ready(Action::None, AuthPhase::Acknowledgement);",
   "pairing_commit_host_ack_replay_reauthenticates_and_preserves_exact_cache"],
  ["pairing-commit-active-completion-reopens-host", "src/pairing_commit.rs", "pairing_commit",
   "return self.ready(Action::MintCompletion, AuthPhase::None);",
   "return Self { state: AcceptedReceived, cached: Completion, ..self }.ready(Action::MintCompletion, AuthPhase::None);",
   "pairing_commit_active_host_completion_is_ephemeral_not_reopened"],
  ["pairing-commit-completion-send-activates-host", "src/pairing_commit.rs", "pairing_commit",
   "(AcceptedReceived, Completion) | (Active, Absent) => self.ready(Action::None, AuthPhase::None),",
   "(AcceptedReceived, Completion) | (Active, Absent) => Self { state: Active, cached: Absent, ..self }.ready(Action::None, AuthPhase::None),",
   "pairing_commit_send_success_never_activates_or_retires_completion"],
  ["pairing-commit-active-completion-refusal-before-auth", "src/pairing_commit.rs", "pairing_commit",
   "return Plan { candidate: self, decision: Decision::PostAuthRejected,\n                        action: Action::None, auth: AuthPhase::Completion };",
   "return self.reject();",
   "pairing_commit_active_viewer_authenticates_before_missing_cache_refusal"],
  ["pairing-commit-active-cached-completion-skips-auth", "src/pairing_commit.rs", "pairing_commit",
   "return self.ready(Action::ExactCachedCommit, AuthPhase::Completion);",
   "return self.ready(Action::ExactCachedCommit, AuthPhase::None);",
   "pairing_commit_active_viewer_authenticates_before_missing_cache_refusal"],
  ["pairing-commit-activation-replay-skips-auth", "src/pairing_commit.rs", "pairing_commit",
   "Self { state: Active, cached: Absent, ..self }.ready(Action::None, AuthPhase::Activation)",
   "Self { state: Active, cached: Absent, ..self }.ready(Action::None, AuthPhase::None)",
   "pairing_commit_activation_ack_authenticates_active_replay_and_retires_cache"],
  ["pairing-commit-activation-keeps-obsolete-cache", "src/pairing_commit.rs", "pairing_commit",
   "Self { state: Active, cached: Absent, ..self }.ready(Action::None, AuthPhase::Activation)",
   "Self { state: Active, ..self }.ready(Action::None, AuthPhase::Activation)",
   "pairing_commit_activation_ack_authenticates_active_replay_and_retires_cache"],
  ["pairing-commit-issued-viewer-forgets-activation-constructor", "src/pairing_commit.rs", "pairing_commit",
   ".ready(Action::MintActivation, AuthPhase::Completion)",
   ".ready(Action::None, AuthPhase::Completion)",
   "pairing_commit_issued_viewer_requires_completion_auth_and_activation_constructor"],
  ["pairing-commit-pending-ack-forgets-constructor", "src/pairing_commit.rs", "pairing_commit",
   ".ready(Action::MintAcknowledgement, AuthPhase::Proposal)",
   ".ready(Action::ExactCachedCommit, AuthPhase::Proposal)",
   "pairing_commit_ack_cached_replay_still_authenticates_and_does_not_tighten_cache"],
  ["pairing-commit-proposal-retains-empty-cache", "src/pairing_commit.rs", "pairing_commit",
   "Absent => Self { cached: Proposal, ..self }.ready(Action::MintProposal, AuthPhase::None),",
   "Absent => self.ready(Action::MintProposal, AuthPhase::None),",
   "pairing_commit_proposal_preserves_cache_or_requires_original_constructor"],
  ["pairing-commit-recovery-tighter-than-original", "src/pairing_commit.rs", "pairing_commit",
   "Operation::RecoveryAction => {\n                if self.cached != Absent {",
   "Operation::RecoveryAction => {\n                if self.role == Role::Host && self.state == AcceptedIssued { return self.reject(); }\n                if self.cached != Absent {",
   "pairing_commit_recovery_getter_is_not_global_stored_shape_validation"],
  ["pairing-commit-active-stored-shape-allows-cache", "src/pairing_commit.rs", "pairing_commit",
   "| (Role::Host, Active, Absent)", "| (Role::Host, Active, _)",
   "pairing_commit_stored_shape_exactly_matches_original_eight_allowed_shapes"],
  ["pairing-commit-mark-uuid-mismatch-admitted", "src/pairing_commit.rs", "pairing_commit",
   "if self.role != Role::Host || !matches!(exact, CommitIDMatch::Exact) { return self.reject(); }",
   "if self.role != Role::Host { return self.reject(); }",
   "pairing_commit_send_success_never_activates_or_retires_completion"],
  ["pairing-commit-outer-abi-ignored", "src/pairing_commit.rs", "pairing_commit",
   "if abi_version != ABI_VERSION { return refused(); }", "if abi_version == 1024 { return refused(); }",
   "pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot"],
  ["pairing-commit-state-reserved-ignored", "src/pairing_commit.rs", "pairing_commit",
   "if raw.abi_version != ABI_VERSION || raw.reserved != 0 || raw.reserved_tail != 0 {",
   "if raw.abi_version != ABI_VERSION {",
   "pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot"],
  ["pairing-commit-event-reserved-ignored", "src/pairing_commit.rs", "pairing_commit",
   "if raw.reserved != 0 || raw.reserved_tail != 0 { return None; }",
   "if false { return None; }",
   "pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot"],
  ["pairing-commit-unused-uuid-fact-admitted", "src/pairing_commit.rs", "pairing_commit",
   "if raw.opcode != 5 && raw.commit_id_matches != 0 { return None; }",
   "if false { return None; }",
   "pairing_commit_unused_uuid_fact_is_not_an_alternative_authorization"],
  ["pairing-commit-host-ack-phase-guard-removed", "src/pairing_commit.rs", "pairing_commit",
   "if self.role != Role::Host || !matches!(self.state, Pending | AcceptedReceived | Active) { return self.reject(); }",
   "if self.role != Role::Host { return self.reject(); }",
   "pairing_commit_role_and_phase_guards_precede_inbound_authentication"],
  ["pairing-commit-invalid-role-canonicalized", "src/pairing_commit.rs", "pairing_commit",
   "let role = match raw.local_role { 0 => Role::Host, 1 => Role::Viewer, _ => return None };",
   "let role = match raw.local_role { 0 => Role::Host, _ => Role::Viewer };",
   "pairing_commit_invalid_abi_domains_and_reserved_fields_preserve_raw_snapshot"]
])
mutants.concat([
  ["supported-player-retry-requires-both-children", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "if facts.browser == ChildObservation::Retry || facts.music == ChildObservation::Retry {",
   "if facts.browser == ChildObservation::Retry && facts.music == ChildObservation::Retry {",
   "a_retry_from_either_child_beats_a_playing_successor"],
  ["supported-player-retry-forgets-selection-hold", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "return Decision::RetryClearingAuthority { selection_hold: facts.selected };",
   "return Decision::RetryClearingAuthority { selection_hold: None };",
   "retry_retains_selected_provider_even_when_absent"],
  ["supported-player-selected-playing-is-not-sticky", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "facts.observation(*source) == ChildObservation::SnapshotPlaying",
   "facts.observation(*source) == ChildObservation::Retry",
   "selected_playing_music_beats_browser_playing_fallback"],
  ["supported-player-playing-fallback-prefers-music", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "} else if facts.browser == ChildObservation::SnapshotPlaying {\n        Some(Source::Browser)\n    } else if facts.music == ChildObservation::SnapshotPlaying {\n        Some(Source::Music)",
   "} else if facts.music == ChildObservation::SnapshotPlaying {\n        Some(Source::Music)\n    } else if facts.browser == ChildObservation::SnapshotPlaying {\n        Some(Source::Browser)",
   "playing_tie_without_selection_bootstraps_browser"],
  ["supported-player-paused-current-source-is-not-retained", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "facts.observation(*source).is_available()",
   "facts.observation(*source) == ChildObservation::Retry",
   "paused_selected_music_is_retained_over_browser_available_fallback"],
  ["supported-player-available-fallback-prefers-music", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "} else if facts.browser.is_available() {\n        Some(Source::Browser)\n    } else if facts.music.is_available() {\n        Some(Source::Music)",
   "} else if facts.music.is_available() {\n        Some(Source::Music)\n    } else if facts.browser.is_available() {\n        Some(Source::Browser)",
   "paused_tie_without_selection_bootstraps_browser"],
  ["supported-player-no-media-fabricates-browser", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "} else {\n        None\n    };\n    Decision::PublishCatalog { primary }",
   "} else {\n        Some(Source::Browser)\n    };\n    Decision::PublishCatalog { primary }",
   "absence_publishes_none_and_does_not_retain_stale_selection"],
  ["supported-player-unknown-abi-is-accepted", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "if input.abi_version != ABI_VERSION || input.reserved != 0 {",
   "if input.reserved != 0 {",
   "unsupported_abi_is_canonical_invalid_not_a_selection"],
  ["supported-player-reserved-input-is-accepted", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "if input.abi_version != ABI_VERSION || input.reserved != 0 {",
   "if input.abi_version != ABI_VERSION {",
   "reserved_input_is_canonical_invalid_not_a_selection"],
  ["supported-player-unknown-selection-is-normalized-none", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "0 => Some(None),\n            1 => Some(Some(Self::Browser)),\n            2 => Some(Some(Self::Music)),\n            _ => None,",
   "0 => Some(None),\n            1 => Some(Some(Self::Browser)),\n            2 => Some(Some(Self::Music)),\n            _ => Some(None),",
   "unknown_selected_source_is_not_normalized_to_none"],
  ["supported-player-unknown-child-is-normalized-retry", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "0 => Some(Self::NoActiveMedia),\n            1 => Some(Self::SnapshotNotPlaying),\n            2 => Some(Self::SnapshotPlaying),\n            3 => Some(Self::Retry),\n            _ => None,",
   "0 => Some(Self::NoActiveMedia),\n            1 => Some(Self::SnapshotNotPlaying),\n            2 => Some(Self::SnapshotPlaying),\n            3 => Some(Self::Retry),\n            _ => Some(Self::Retry),",
   "unknown_child_observation_is_not_normalized_to_retry"],
  ["supported-player-reserved-output-is-nonzero", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "ArbitrationOutput { abi_version: ABI_VERSION, action, primary_or_hold, reserved: 0 }",
   "ArbitrationOutput { abi_version: ABI_VERSION, action, primary_or_hold, reserved: 1 }",
   "every_valid_output_has_closed_action_source_and_zero_reserved"],
  ["supported-player-input-field-offsets-are-reordered", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "pub selected_source: u32,\n    pub browser_observation: u32,",
   "pub browser_observation: u32,\n    pub selected_source: u32,",
   "copied_layout_pins_every_field_offset_size_and_alignment"],
  ["supported-player-output-field-offsets-are-reordered", "src/supported_player_arbitration.rs", "supported_player_arbitration",
   "pub action: u32,\n    // 0 = none; 1 = browser; 2 = music. A retry carries the unchanged hold.\n    pub primary_or_hold: u32,",
   "pub primary_or_hold: u32,\n    // 0 = none; 1 = browser; 2 = music. A retry carries the unchanged hold.\n    pub action: u32,",
   "copied_layout_pins_every_field_offset_size_and_alignment"]
])
mutants.concat([
  ["availability-valid-reset-removed", "src/availability_retry.rs", "availability_retry",
   "candidate: State::Validated,",
   "candidate: State::AwaitingValidation(self.delay()),",
   "availability_retry_reset_and_became_marker_match_each_state"],
  ["availability-repeated-valid-marker-inverted", "src/availability_retry.rs", "availability_retry",
   "became: !matches!(self, Self::Validated)", "became: matches!(self, Self::Validated)",
   "availability_retry_repeated_valid_state_is_reported_only_once"],
  ["availability-failure-returns-doubled-delay", "src/availability_retry.rs", "availability_retry",
   "action: Action::RetryAfter(old_delay),", "action: Action::RetryAfter(old_delay.successor()),",
   "availability_retry_failure_returns_old_delay_and_clears_validation"],
  ["availability-failure-state-not-advanced-or-cleared", "src/availability_retry.rs", "availability_retry",
   "candidate: State::AwaitingValidation(old_delay.successor()),", "candidate: self,",
   "availability_retry_all_fourteen_literal_transitions_match"],
  ["availability-sixteen-never-reaches-cap", "src/availability_retry.rs", "availability_retry",
   "Self::Sixteen => Self::Thirty,", "Self::Sixteen => Self::Sixteen,",
   "availability_retry_failures_double_then_saturate_at_thirty"],
  ["availability-cap-wraps-to-one", "src/availability_retry.rs", "availability_retry",
   "Self::Thirty => Self::Thirty,", "Self::Thirty => Self::One,",
   "availability_retry_failures_double_then_saturate_at_thirty"],
  ["availability-zero-delay-normalized", "src/availability_retry.rs", "availability_retry",
   "1 => Some(Self::One), 2 => Some(Self::Two),",
   "0 | 1 => Some(Self::One), 2 => Some(Self::Two),",
   "availability_retry_closed_raw_state_domains_never_normalize"],
  ["availability-validated-delay-invariant-removed", "src/availability_retry.rs", "availability_retry",
   "1 if delay == Delay::One => Some(Self::Validated),", "1 => Some(Self::Validated),",
   "availability_retry_closed_raw_state_domains_never_normalize"],
  ["availability-nonboolean-validation-accepted", "src/availability_retry.rs", "availability_retry",
   "1 if delay == Delay::One => Some(Self::Validated),", "1 | 2 if delay == Delay::One => Some(Self::Validated),",
   "availability_retry_closed_raw_state_domains_never_normalize"],
  ["availability-call-abi-ignored", "src/availability_retry.rs", "availability_retry",
   "if abi_version != ABI_VERSION { return invalid(); }", "if false { return invalid(); }",
   "availability_retry_unknown_call_abi_is_invalid_unchanged"],
  ["availability-state-abi-ignored", "src/availability_retry.rs", "availability_retry",
   "if raw.abi_version != ABI_VERSION { return None; }", "if false { return None; }",
   "availability_retry_closed_raw_state_domains_never_normalize"],
  ["availability-state-reserved-ignored", "src/availability_retry.rs", "availability_retry",
   "if raw.reserved != 0 { return None; }\n        let delay", "if false { return None; }\n        let delay",
   "availability_retry_closed_raw_state_domains_never_normalize"],
  ["availability-event-reserved-ignored", "src/availability_retry.rs", "availability_retry",
   "if raw.reserved != 0 { return None; }\n        match raw.opcode", "if false { return None; }\n        match raw.opcode",
   "availability_retry_closed_event_opcode_and_reserved_never_reset"],
  ["availability-unknown-operation-becomes-failure", "src/availability_retry.rs", "availability_retry",
   "1 => Some(Self::Failure),\n            _ => None,", "1 => Some(Self::Failure),\n            _ => Some(Self::Failure),",
   "availability_retry_closed_event_opcode_and_reserved_never_reset"],
  ["availability-refusal-resets-raw-state", "src/availability_retry.rs", "availability_retry",
   "candidate_state: before,", "candidate_state: State::AwaitingValidation(Delay::One).raw(),",
   "availability_retry_two_invalid_fields_preserve_exact_raw_state"],
  ["availability-result-reserved-not-zero", "src/availability_retry.rs", "availability_retry",
   "retry_delay_seconds,\n            reserved: 0,", "retry_delay_seconds,\n            reserved: 1,",
   "availability_retry_all_fourteen_literal_transitions_match"]
])
mutants.concat([
  ["safe-output-budget-tick-equality", "src/safe_output_retry.rs", "safe_output_retry", "Event::Tick => {\n                if self.failed_attempt_count >= self.config.maximum_failed_attempt_count {", "Event::Tick => {\n                if self.failed_attempt_count > self.config.maximum_failed_attempt_count {", "literal_cooldown_does_not_probe_one_tick_early_or_rearm_at_cap"],
  ["safe-output-cooldown-stalls", "src/safe_output_retry.rs", "safe_output_retry", "self.cooldown_tick_count -= 1;\n                        return (self, Some(false));", "return (self, Some(false));", "literal_cooldown_does_not_probe_one_tick_early_or_rearm_at_cap"],
  ["safe-output-cap-rearms-partly-elapsed-cooldown", "src/safe_output_retry.rs", "safe_output_retry", "Event::Failure => {\n                if self.failed_attempt_count >= self.config.maximum_failed_attempt_count {\n                    return (self, None);", "Event::Failure => {\n                if self.failed_attempt_count >= self.config.maximum_failed_attempt_count {\n                    self.cooldown_tick_count = self.config.capped_cooldown_tick_count;\n                    return (self, None);", "failure_when_exhausted_preserves_partially_elapsed_cooldown"],
  ["safe-output-exponent-cap-thirty-one", "src/safe_output_retry.rs", "safe_output_retry", "let shift = (self.failed_attempt_count - 1).min(30) as u32;", "let shift = (self.failed_attempt_count - 1).min(31) as u32;", "exponent_caps_at_thirty_without_an_invented_sixty_four_entry_limit"],
  ["safe-output-clamp-failed-to-two", "src/safe_output_retry.rs", "safe_output_retry", "maximum_failed_attempt_count: maximum_failed.max(1),", "maximum_failed_attempt_count: maximum_failed.max(2),", "signed_constructor_preserves_every_limit_domain_and_clamps_to_one"],
  ["safe-output-clamp-backoff-to-two", "src/safe_output_retry.rs", "safe_output_retry", "maximum_backoff_tick_count: maximum_backoff.max(1),", "maximum_backoff_tick_count: maximum_backoff.max(2),", "signed_constructor_preserves_every_limit_domain_and_clamps_to_one"],
  ["safe-output-clamp-cooldown-to-two", "src/safe_output_retry.rs", "safe_output_retry", "capped_cooldown_tick_count: cooldown.max(1),", "capped_cooldown_tick_count: cooldown.max(2),", "signed_constructor_preserves_every_limit_domain_and_clamps_to_one"],
  ["safe-output-no-capped-cooldown", "src/safe_output_retry.rs", "safe_output_retry", "self.cooldown_tick_count = self.config.capped_cooldown_tick_count;", "self.cooldown_tick_count = 0;", "default_failure_budget_has_exact_literal_delays_and_sixty_tick_cooldown"],
  ["safe-output-backoff-tick-admits", "src/safe_output_retry.rs", "safe_output_retry", "if self.backoff_tick_count != 0 {\n                    self.backoff_tick_count -= 1;\n                    return (self, Some(false));", "if self.backoff_tick_count != 0 {\n                    self.backoff_tick_count -= 1;\n                    return (self, Some(true));", "literal_cooldown_does_not_probe_one_tick_early_or_rearm_at_cap"],
  ["safe-output-reset-leaves-one-failure", "src/safe_output_retry.rs", "safe_output_retry", "Event::Reset => {\n                self.failed_attempt_count = 0;", "Event::Reset => {\n                self.failed_attempt_count = 1;", "copies_are_independent_and_read_only_ticks_do_not_create_failure_history"],
  ["system-audio-resume-needs-authorization", "src/system_audio_start.rs", "system_audio_start", "&& facts.has_sink && !facts.has_valid_authorization && facts.peer_generation_matches {", "&& facts.has_sink && facts.has_valid_authorization && facts.peer_generation_matches {", "sixty_four_literal_cases_and_frozen_guards_match_actual_production"],
  ["system-audio-resume-ignores-peer-generation", "src/system_audio_start.rs", "system_audio_start", "&& facts.has_sink && !facts.has_valid_authorization && facts.peer_generation_matches {", "&& facts.has_sink && !facts.has_valid_authorization {", "new_start_ignores_generation_but_resume_and_live_require_it"],
  ["system-audio-new-start-adds-generation-fence", "src/system_audio_start.rs", "system_audio_start", "&& !facts.has_sink && !facts.has_valid_authorization {", "&& !facts.has_sink && !facts.has_valid_authorization && facts.peer_generation_matches {", "new_start_ignores_generation_but_resume_and_live_require_it"],
  ["system-audio-live-accepts-paused", "src/system_audio_start.rs", "system_audio_start", "if facts.is_live && !facts.is_paused_for_recovery && facts.has_source", "if facts.is_live && facts.is_paused_for_recovery && facts.has_source", "sixty_four_literal_cases_and_frozen_guards_match_actual_production"],
  ["system-audio-invalid-boolean-becomes-false", "src/system_audio_start.rs", "system_audio_start", "match raw { 0 => Some(false), 1 => Some(true), _ => None }", "match raw { 0 => Some(false), 1 => Some(true), _ => Some(false) }", "every_closed_field_refuses_against_every_valid_combination"],
  ["hosted-call-equal-watermark-admits", "src/hosted_call_policy.rs", "hosted_call_policy", "if facts.observation_sequence <= facts.highest_admitted_sequence { return false; }", "if facts.observation_sequence < facts.highest_admitted_sequence { return false; }", "literal_observation_watermarks_are_strict_and_never_wrap_at_u64_max"],
  ["hosted-call-ignores-challenge-sequence", "src/hosted_call_policy.rs", "hosted_call_policy", "current.is_valid() && observation.sequence == current.sequence", "current.is_valid()", "old_sequence_nonce_and_epoch_each_refuse_independently"],
  ["hosted-call-ignores-observation-nonce", "src/hosted_call_policy.rs", "hosted_call_policy", "&& observation.nonce == current.nonce\n        && observation.call_epoch_nonce == current.call_epoch_nonce", "&& observation.call_epoch_nonce == current.call_epoch_nonce", "old_sequence_nonce_and_epoch_each_refuse_independently"],
  ["hosted-call-ignores-observation-epoch", "src/hosted_call_policy.rs", "hosted_call_policy", "&& observation.call_epoch_nonce == current.call_epoch_nonce\n}", "\n}", "old_sequence_nonce_and_epoch_each_refuse_independently"],
  ["hosted-call-accepts-other-positive-protocol", "src/hosted_call_policy.rs", "hosted_call_policy", "self.protocol_version == CURRENT_PROTOCOL_VERSION && self.sequence > 0", "self.protocol_version > 0 && self.sequence > 0", "invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error"],
  ["hosted-call-accepts-zero-challenge-sequence", "src/hosted_call_policy.rs", "hosted_call_policy", "self.protocol_version == CURRENT_PROTOCOL_VERSION && self.sequence > 0", "self.protocol_version == CURRENT_PROTOCOL_VERSION", "invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error"],
  ["hosted-call-accepts-zero-nonce", "src/hosted_call_policy.rs", "hosted_call_policy", "&& self.nonce != [0; 16] && self.call_epoch_nonce != [0; 16]", "&& self.call_epoch_nonce != [0; 16]", "invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error"],
  ["hosted-call-accepts-zero-epoch", "src/hosted_call_policy.rs", "hosted_call_policy", "&& self.nonce != [0; 16] && self.call_epoch_nonce != [0; 16]", "&& self.nonce != [0; 16]", "invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error"],
  ["hosted-call-accepts-identical-nonce-and-epoch", "src/hosted_call_policy.rs", "hosted_call_policy", "&& self.nonce != self.call_epoch_nonce\n    }", "\n    }", "invalid_or_missing_challenge_is_legitimate_refusal_not_bridge_error"],
  ["hosted-call-peer-current-zero-admits", "src/hosted_call_policy.rs", "hosted_call_policy", "current > 0 && audio == Some(current) && challenge == Some(current)", "audio == Some(current) && challenge == Some(current)", "literal_peer_fence_distinguishes_absence_zero_and_extreme_generation"],
  ["hosted-call-peer-ignores-audio-generation", "src/hosted_call_policy.rs", "hosted_call_policy", "current > 0 && audio == Some(current) && challenge == Some(current)", "current > 0 && challenge == Some(current)", "literal_peer_fence_distinguishes_absence_zero_and_extreme_generation"],
  ["hosted-call-peer-ignores-challenge-generation", "src/hosted_call_policy.rs", "hosted_call_policy", "current > 0 && audio == Some(current) && challenge == Some(current)", "current > 0 && audio == Some(current)", "literal_peer_fence_distinguishes_absence_zero_and_extreme_generation"],
  ["hosted-call-poison-becomes-active", "src/hosted_call_policy.rs", "hosted_call_policy", "(true, true) => None,", "(true, true) => Some(EvidenceState::Active),", "four_literal_evidence_states_distinguish_poison_from_empty_prospective_arm"],
  ["hosted-call-inactive-becomes-none", "src/hosted_call_policy.rs", "hosted_call_policy", "(false, false) => Some(EvidenceState::Inactive),", "(false, false) => None,", "four_literal_evidence_states_distinguish_poison_from_empty_prospective_arm"],
  ["hosted-call-invalid-boolean-becomes-true", "src/hosted_call_policy.rs", "hosted_call_policy", "match raw { 0 => Some(false), 1 => Some(true), _ => None }", "match raw { 0 => Some(false), 1 => Some(true), _ => Some(true) }", "invalid_evidence_fields_do_not_alias_legitimate_poison"]
])
mutants.concat([
  ["safe-output-initializer-envelope-or-becomes-and","src/safe_output_retry.rs","safe_output_retry","pub fn initialize(raw: RawConfig) -> RawResult {\n    if raw.abi_version != ABI_VERSION || raw.reserved != 0 {","pub fn initialize(raw: RawConfig) -> RawResult {\n    if raw.abi_version != ABI_VERSION && raw.reserved != 0 {","invalid_constructor_envelope_preserves_requested_values_but_is_not_accepted"],
  ["safe-output-invalid-initializer-fabricates-failure-counter","src/safe_output_retry.rs","safe_output_retry","failed_attempt_count: 0, backoff_tick_count: 0, cooldown_tick_count: 0,","failed_attempt_count: 1, backoff_tick_count: 0, cooldown_tick_count: 0,","invalid_constructor_envelope_preserves_requested_values_but_is_not_accepted"],
  ["hosted-call-peer-accepts-zero-abi","src/hosted_call_policy.rs","hosted_call_policy","pub fn decide_peer_generation(raw: RawPeerFacts) -> RawDecision {\n    if raw.abi_version != ABI_VERSION || raw.reserved != 0 { return invalid(); }","pub fn decide_peer_generation(raw: RawPeerFacts) -> RawDecision {\n    if raw.abi_version > ABI_VERSION || raw.reserved != 0 { return invalid(); }","invalid_peer_fields_refuse_even_with_matching_generation_payloads"],
  ["hosted-call-peer-ignores-reserved-one","src/hosted_call_policy.rs","hosted_call_policy","pub fn decide_peer_generation(raw: RawPeerFacts) -> RawDecision {\n    if raw.abi_version != ABI_VERSION || raw.reserved != 0 { return invalid(); }","pub fn decide_peer_generation(raw: RawPeerFacts) -> RawDecision {\n    if raw.abi_version != ABI_VERSION || raw.reserved > 1 { return invalid(); }","invalid_peer_fields_refuse_even_with_matching_generation_payloads"]
])
# PRIVATE DRAFT ONLY: append only after the authoritative module/test draft is
# reviewed. This fragment was never loaded or executed. Each production snippet
# must match exactly once in src/display_admission.rs before replacement.
# Tuple fields match the existing runner: id, source, integration target,
# original production bytes, mutant production bytes, exact ordinary test name.
mutants.concat([
  ['display-envelope-version-ignored', 'src/display_admission.rs', 'display_admission',
   'version == ABI_VERSION && reserved == 0', 'reserved == 0',
   'display_requirement_unknown_abi_is_invalid_independent_of_policy_result'],
  ['display-envelope-reserved-ignored', 'src/display_admission.rs', 'display_admission',
   'version == ABI_VERSION && reserved == 0', 'version == ABI_VERSION',
   'display_requirement_reserved_is_invalid_independent_of_policy_result'],
  ['display-requirement-envelope-bypassed', 'src/display_admission.rs', 'display_admission',
   "pub fn requirement_admission(raw: RawDisplayFacts) -> RawBooleanDecision {\n    if !envelope(raw.abi_version, raw.reserved)",
   "pub fn requirement_admission(raw: RawDisplayFacts) -> RawBooleanDecision {\n    if false",
   'display_requirement_unknown_abi_is_invalid_independent_of_policy_result'],
  ['display-kind-envelope-bypassed', 'src/display_admission.rs', 'display_admission',
   "pub fn dimension_kind(raw: RawKindFacts) -> RawKindDecision {\n    if !envelope(raw.abi_version, raw.reserved)",
   "pub fn dimension_kind(raw: RawKindFacts) -> RawKindDecision {\n    if false",
   'source_kind_unknown_abi_and_reserved_are_independent_invalid_inputs'],
  ['display-source-envelope-bypassed', 'src/display_admission.rs', 'display_admission',
   "pub fn source_dimensions(raw: RawSourceFacts) -> RawSourceDecision {\n    if !envelope(raw.abi_version, raw.reserved)",
   "pub fn source_dimensions(raw: RawSourceFacts) -> RawSourceDecision {\n    if false",
   'source_dimensions_invalid_bridge_is_distinct_from_legitimate_owned_absence'],
  ['display-stability-envelope-bypassed', 'src/display_admission.rs', 'display_admission',
   "pub fn dimensions_stable(raw: RawStabilityFacts) -> RawBooleanDecision {\n    if !envelope(raw.abi_version, raw.reserved)",
   "pub fn dimensions_stable(raw: RawStabilityFacts) -> RawBooleanDecision {\n    if false",
   'source_stability_unknown_abi_and_reserved_are_independent_invalid_inputs'],
  ['display-raw-sole-boolean-domain-opened', 'src/display_admission.rs', 'display_admission',
   'raw.requires_sole_main_display > 1', 'false',
   'display_requirement_each_raw_boolean_domain_is_closed_even_if_ignored'],
  ['display-raw-online-boolean-domain-opened', 'src/display_admission.rs', 'display_admission',
   'raw.is_online > 1', 'false',
   'display_requirement_each_raw_boolean_domain_is_closed_even_if_ignored'],
  ['display-raw-active-boolean-domain-opened', 'src/display_admission.rs', 'display_admission',
   'raw.is_active > 1', 'false',
   'display_requirement_each_raw_boolean_domain_is_closed_even_if_ignored'],
  ['display-online-admission-removed', 'src/display_admission.rs', 'display_admission',
   'raw.is_online == 0', 'false',
   'display_requirement_each_original_identity_and_liveness_guard_is_independent'],
  ['display-active-admission-removed', 'src/display_admission.rs', 'display_admission',
   'raw.is_active == 0', 'false',
   'display_requirement_each_original_identity_and_liveness_guard_is_independent'],
  ['display-vendor-identity-admission-removed', 'src/display_admission.rs', 'display_admission',
   'raw.observed_vendor_id != raw.required_vendor_id', 'false',
   'display_requirement_each_original_identity_and_liveness_guard_is_independent'],
  ['display-product-identity-admission-removed', 'src/display_admission.rs', 'display_admission',
   'raw.observed_product_id != raw.required_product_id', 'false',
   'display_requirement_each_original_identity_and_liveness_guard_is_independent'],
  ['display-serial-identity-admission-removed', 'src/display_admission.rs', 'display_admission',
   'raw.observed_serial_number != raw.required_serial_number', 'false',
   'display_requirement_each_original_identity_and_liveness_guard_is_independent'],
  ['display-identity-vendor-truncated-to-u16', 'src/display_admission.rs', 'display_admission',
   'raw.observed_vendor_id != raw.required_vendor_id',
   '(raw.observed_vendor_id as u16) != (raw.required_vendor_id as u16)',
   'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum'],
  ['display-identity-product-truncated-to-u16', 'src/display_admission.rs', 'display_admission',
   'raw.observed_product_id != raw.required_product_id',
   '(raw.observed_product_id as u16) != (raw.required_product_id as u16)',
   'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum'],
  ['display-identity-serial-truncated-to-u16', 'src/display_admission.rs', 'display_admission',
   'raw.observed_serial_number != raw.required_serial_number',
   '(raw.observed_serial_number as u16) != (raw.required_serial_number as u16)',
   'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum'],
  ['display-zero-id-refused', 'src/display_admission.rs', 'display_admission',
   'if raw.is_online == 0 || raw.is_active == 0',
   'if raw.is_online == 0 || raw.is_active == 0 || raw.display_id == 0',
   'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum'],
  ['display-optional-topology-still-required', 'src/display_admission.rs', 'display_admission',
   'if raw.requires_sole_main_display == 0 {', 'if false {',
   'display_requirement_optional_topology_ignores_main_count_and_singleton'],
  ['display-main-id-admission-removed', 'src/display_admission.rs', 'display_admission',
   'boolean_decision(true, raw.main_display_id == raw.display_id',
   'boolean_decision(true, true',
   'display_requirement_sole_main_mismatch_alone_refuses'],
  ['display-main-id-truncated-to-u16', 'src/display_admission.rs', 'display_admission',
   'raw.main_display_id == raw.display_id',
   '(raw.main_display_id as u16) == (raw.display_id as u16)',
   'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum'],
  ['display-singleton-count-widened-to-membership', 'src/display_admission.rs', 'display_admission',
   'raw.online_display_count == 1', 'raw.online_display_count >= 1',
   'display_requirement_sole_topology_is_exact_singleton_including_duplicates'],
  ['display-singleton-count-truncated-to-u32', 'src/display_admission.rs', 'display_admission',
   'raw.online_display_count == 1', '(raw.online_display_count as u32) == 1',
   'display_requirement_sole_topology_is_exact_singleton_including_duplicates'],
  ['display-singleton-id-admission-removed', 'src/display_admission.rs', 'display_admission',
   'raw.sole_online_display_id == raw.display_id', 'true',
   'display_requirement_sole_topology_is_exact_singleton_including_duplicates'],
  ['display-singleton-id-truncated-to-u16', 'src/display_admission.rs', 'display_admission',
   'raw.sole_online_display_id == raw.display_id',
   '(raw.sole_online_display_id as u16) == (raw.display_id as u16)',
   'display_requirement_identity_and_display_ids_preserve_zero_and_u32_maximum'],
  ['display-source-kind-vendor-restriction-removed', 'src/display_admission.rs', 'display_admission',
   'vendor == 0x6f73 &&', 'true &&',
   'source_kind_frozen_literal_table_selects_only_the_two_owned_products'],
  ['display-source-kind-phone-product-removed', 'src/display_admission.rs', 'display_admission',
   'product == 0x1717 || product == 0x1718', 'product == 0x1718',
   'source_kind_frozen_literal_table_selects_only_the_two_owned_products'],
  ['display-source-kind-combined-product-removed', 'src/display_admission.rs', 'display_admission',
   'product == 0x1717 || product == 0x1718', 'product == 0x1717',
   'source_kind_frozen_literal_table_selects_only_the_two_owned_products'],
  ['display-source-kind-unknown-product-admitted', 'src/display_admission.rs', 'display_admission',
   'product == 0x1717 || product == 0x1718',
   'product == 0x1717 || product == 0x1718 || product == 0x1719',
   'source_kind_frozen_literal_table_selects_only_the_two_owned_products'],
  ['display-ordinary-source-filter-finite-guard-introduced', 'src/display_admission.rs', 'display_admission',
   'if kind == 0 {', 'if kind == 0 && raw.filter_content_width.is_finite() {',
   'ordinary_source_preserves_entire_signed_domain_before_any_metadata_guard'],
  ['display-ordinary-source-clamps-signed-dimensions', 'src/display_admission.rs', 'display_admission',
   'has_dimensions: 1, width: raw.logical_width, height: raw.logical_height',
   'has_dimensions: 1, width: raw.logical_width.max(2), height: raw.logical_height.max(2)',
   'ordinary_source_preserves_entire_signed_domain_before_any_metadata_guard'],
  ['display-owned-logical-width-minimum-tightened-to-three', 'src/display_admission.rs', 'display_admission',
   'raw.logical_width < 2', 'raw.logical_width < 3',
   'owned_source_logical_width_and_height_minimum_are_two'],
  ['display-owned-logical-height-minimum-tightened-to-three', 'src/display_admission.rs', 'display_admission',
   'raw.logical_height < 2', 'raw.logical_height < 3',
   'owned_source_logical_width_and_height_minimum_are_two'],
  ['display-owned-logical-width-maximum-removed', 'src/display_admission.rs', 'display_admission',
   'raw.logical_width > 32_768', 'false',
   'owned_source_logical_width_and_height_maximum_are_32768'],
  ['display-owned-logical-height-maximum-removed', 'src/display_admission.rs', 'display_admission',
   'raw.logical_height > 32_768', 'false',
   'owned_source_logical_width_and_height_maximum_are_32768'],
  ['display-owned-filter-width-finite-guard-removed', 'src/display_admission.rs', 'display_admission',
   '!raw.filter_content_width.is_finite()', 'false',
   'owned_source_filter_width_must_be_finite'],
  ['display-owned-filter-height-finite-guard-removed', 'src/display_admission.rs', 'display_admission',
   '!raw.filter_content_height.is_finite()', 'false',
   'owned_source_filter_height_must_be_finite'],
  ['display-owned-scale-lower-bound-tightened', 'src/display_admission.rs', 'display_admission',
   '!(1.0..=4.0).contains(&raw.point_pixel_scale)',
   '!(1.0000000000000002..=4.0).contains(&raw.point_pixel_scale)',
   'owned_source_scale_includes_one_and_four_and_refuses_actual_double_neighbors'],
  ['display-owned-scale-upper-bound-exclusive', 'src/display_admission.rs', 'display_admission',
   '!(1.0..=4.0).contains(&raw.point_pixel_scale)',
   '!(1.0..4.0).contains(&raw.point_pixel_scale)',
   'owned_source_scale_includes_one_and_four_and_refuses_actual_double_neighbors'],
  ['display-owned-scale-range-removed', 'src/display_admission.rs', 'display_admission',
   '!(1.0..=4.0).contains(&raw.point_pixel_scale)', 'false',
   'owned_source_scale_includes_one_and_four_and_refuses_actual_double_neighbors'],
  ['display-owned-cg-logical-width-minimum-tightened-to-three', 'src/display_admission.rs', 'display_admission',
   'raw.core_graphics_logical_width < 2', 'raw.core_graphics_logical_width < 3',
   'owned_source_core_graphics_logical_minimum_literals_and_exact_snapshot_equality'],
  ['display-owned-cg-logical-height-minimum-tightened-to-three', 'src/display_admission.rs', 'display_admission',
   'raw.core_graphics_logical_height < 2', 'raw.core_graphics_logical_height < 3',
   'owned_source_core_graphics_logical_minimum_literals_and_exact_snapshot_equality'],
  ['display-owned-pixel-width-minimum-removed', 'src/display_admission.rs', 'display_admission',
   'raw.core_graphics_pixel_width < 2', 'false',
   'owned_source_pixel_width_and_height_minimum_are_two'],
  ['display-owned-pixel-height-minimum-removed', 'src/display_admission.rs', 'display_admission',
   'raw.core_graphics_pixel_height < 2', 'false',
   'owned_source_pixel_width_and_height_minimum_are_two'],
  ['display-owned-pixel-width-maximum-removed', 'src/display_admission.rs', 'display_admission',
   'raw.core_graphics_pixel_width > 32_768', 'false',
   'owned_source_pixel_width_and_height_maximum_are_32768'],
  ['display-owned-pixel-height-maximum-removed', 'src/display_admission.rs', 'display_admission',
   'raw.core_graphics_pixel_height > 32_768', 'false',
   'owned_source_pixel_width_and_height_maximum_are_32768'],
  ['display-owned-cg-logical-width-equality-removed', 'src/display_admission.rs', 'display_admission',
   'raw.logical_width != raw.core_graphics_logical_width', 'false',
   'owned_source_core_graphics_width_snapshot_mismatch_alone_refuses'],
  ['display-owned-cg-logical-height-equality-removed', 'src/display_admission.rs', 'display_admission',
   'raw.logical_height != raw.core_graphics_logical_height', 'false',
   'owned_source_core_graphics_height_snapshot_mismatch_alone_refuses'],
  ['display-owned-filter-width-half-pixel-exclusive', 'src/display_admission.rs', 'display_admission',
   '(raw.filter_content_width - raw.logical_width as f64).abs() > 0.5',
   '(raw.filter_content_width - raw.logical_width as f64).abs() >= 0.5',
   'owned_source_filter_width_half_pixel_boundary_is_inclusive_both_directions'],
  ['display-owned-filter-height-half-pixel-exclusive', 'src/display_admission.rs', 'display_admission',
   '(raw.filter_content_height - raw.logical_height as f64).abs() > 0.5',
   '(raw.filter_content_height - raw.logical_height as f64).abs() >= 0.5',
   'owned_source_filter_height_half_pixel_boundary_is_inclusive_both_directions'],
  ['display-owned-filter-width-half-pixel-widened-to-one', 'src/display_admission.rs', 'display_admission',
   '(raw.filter_content_width - raw.logical_width as f64).abs() > 0.5',
   '(raw.filter_content_width - raw.logical_width as f64).abs() > 1.0',
   'owned_source_filter_width_half_pixel_boundary_is_inclusive_both_directions'],
  ['display-owned-filter-height-half-pixel-widened-to-one', 'src/display_admission.rs', 'display_admission',
   '(raw.filter_content_height - raw.logical_height as f64).abs() > 0.5',
   '(raw.filter_content_height - raw.logical_height as f64).abs() > 1.0',
   'owned_source_filter_height_half_pixel_boundary_is_inclusive_both_directions'],
  ['display-owned-refusal-mislabeled-invalid-bridge', 'src/display_admission.rs', 'display_admission',
   "let refused = RawSourceDecision { abi_version: ABI_VERSION, status: 1, kind,\n        has_dimensions: 0, width: 0, height: 0 };",
   "let refused = RawSourceDecision { abi_version: ABI_VERSION, status: 0, kind,\n        has_dimensions: 0, width: 0, height: 0 };",
   'source_dimensions_invalid_bridge_is_distinct_from_legitimate_owned_absence'],
  ['display-owned-refusal-retains-nonzero-payload', 'src/display_admission.rs', 'display_admission',
   "let refused = RawSourceDecision { abi_version: ABI_VERSION, status: 1, kind,\n        has_dimensions: 0, width: 0, height: 0 };",
   "let refused = RawSourceDecision { abi_version: ABI_VERSION, status: 1, kind,\n        has_dimensions: 0, width: 1, height: 0 };",
   'source_dimensions_invalid_bridge_is_distinct_from_legitimate_owned_absence'],
  ['display-owned-pixels-replaced-with-logical', 'src/display_admission.rs', 'display_admission',
   'width: raw.core_graphics_pixel_width, height: raw.core_graphics_pixel_height',
   'width: raw.logical_width, height: raw.logical_height',
   'owned_source_returns_current_framebuffer_independent_of_scale_ratio_or_rounding'],
  ['display-owned-pixels-encoder-rounded-prematurely', 'src/display_admission.rs', 'display_admission',
   'width: raw.core_graphics_pixel_width, height: raw.core_graphics_pixel_height',
   'width: raw.core_graphics_pixel_width & !1, height: raw.core_graphics_pixel_height & !1',
   'owned_source_returns_current_framebuffer_independent_of_scale_ratio_or_rounding'],
  ['display-stability-width-equality-removed', 'src/display_admission.rs', 'display_admission',
   'raw.before_width == raw.after_width', 'true',
   'source_stability_requires_both_dimensions_exactly_equal_without_sanity_limits'],
  ['display-stability-height-equality-removed', 'src/display_admission.rs', 'display_admission',
   'raw.before_height == raw.after_height', 'true',
   'source_stability_requires_both_dimensions_exactly_equal_without_sanity_limits'],
  ['display-stability-unrequested-dimension-sanity-introduced', 'src/display_admission.rs', 'display_admission',
   'boolean_decision(true, raw.before_width == raw.after_width',
   'boolean_decision(true, raw.before_width >= 2 && raw.before_width == raw.after_width',
   'source_stability_requires_both_dimensions_exactly_equal_without_sanity_limits'],
])

# PRIVATE ADDITIVE DRAFT ONLY. No runner was loaded or executed.
# Exact original production snippets must each match once in source_kind in the
# frozen src/display_admission.rs. The new ordinary test calls actual C first.
mutants.concat([
  ['display-source-kind-vendor-truncated-to-u16', 'src/display_admission.rs', 'display_admission',
   'vendor == 0x6f73 &&', '(vendor as u16) == 0x6f73 &&',
   'source_kind_and_dimensions_high_bit_identity_aliases_remain_ordinary'],
  ['display-source-kind-product-truncated-to-u16', 'src/display_admission.rs', 'display_admission',
   '(product == 0x1717 || product == 0x1718)',
   '((product as u16) == 0x1717 || (product as u16) == 0x1718)',
   'source_kind_and_dimensions_high_bit_identity_aliases_remain_ordinary'],
])

# PRIVATE exact singleton controls. Uncompiled/unexecuted; no kills claimed.
mutants.concat([
  ['output-source-width-minimum-weakened', 'src/output_dimensions.rs', 'output_dimensions',
   'raw.source_width < 2', 'raw.source_width < 1', 'output_each_original_signed_guard_refuses_before_arithmetic'],
  ['output-source-height-minimum-weakened', 'src/output_dimensions.rs', 'output_dimensions',
   'raw.source_height < 2', 'raw.source_height < 1', 'output_each_original_signed_guard_refuses_before_arithmetic'],
  ['output-maximum-width-minimum-weakened', 'src/output_dimensions.rs', 'output_dimensions',
   'raw.maximum_width < 2', 'raw.maximum_width < 1', 'output_each_original_signed_guard_refuses_before_arithmetic'],
  ['output-width-cap-discarded', 'src/output_dimensions.rs', 'output_dimensions',
   'let capped_width = raw.source_width.min(raw.maximum_width);', 'let capped_width = raw.source_width;',
   'output_width_cap_is_a_minimum_without_upscaling'],
  ['output-width-upscaled-to-cap', 'src/output_dimensions.rs', 'output_dimensions',
   'let capped_width = raw.source_width.min(raw.maximum_width);', 'let capped_width = raw.source_width.max(raw.maximum_width);',
   'output_width_cap_is_a_minimum_without_upscaling'],
  ['output-even-width-adjustment-removed', 'src/output_dimensions.rs', 'output_dimensions',
   'let width = capped_width - capped_width % 2;', 'let width = capped_width;',
   'output_even_width_is_chosen_before_scaling'],
  ['output-nearest-rounding-truncated', 'src/output_dimensions.rs', 'output_dimensions',
   '/ (raw.source_width as f64)).round();', '/ (raw.source_width as f64)).trunc();',
   'output_positive_half_ties_round_away_before_even_height'],
  ['output-nearest-rounding-to-even', 'src/output_dimensions.rs', 'output_dimensions',
   '/ (raw.source_width as f64)).round();', '/ (raw.source_width as f64)).round_ties_even();',
   'output_positive_half_ties_round_away_before_even_height'],
  ['output-nearest-rounding-ceiling', 'src/output_dimensions.rs', 'output_dimensions',
   '/ (raw.source_width as f64)).round();', '/ (raw.source_width as f64)).ceil();',
   'output_non_ties_keep_nearest_not_floor_or_ceil'],
  ['output-float-math-replaced-by-integer-ratio', 'src/output_dimensions.rs', 'output_dimensions',
   "((raw.source_height as f64) * (width as f64)\n        / (raw.source_width as f64)).round();",
   '((raw.source_height / raw.source_width) as f64 * width as f64).round();',
   'output_float_multiply_then_divide_is_not_integer_ratio'],
  ['output-height-chroma-adjustment-removed', 'src/output_dimensions.rs', 'output_dimensions',
   'let height = 2.max(scaled_height - scaled_height % 2);', 'let height = 2.max(scaled_height);',
   'output_height_chroma_adjustment_rounds_down_after_nearest'],
  ['output-two-pixel-height-floor-removed', 'src/output_dimensions.rs', 'output_dimensions',
   'let height = 2.max(scaled_height - scaled_height % 2);', 'let height = scaled_height - scaled_height % 2;',
   'output_height_floor_keeps_two_when_scaled_rounds_to_zero_or_one'],
  ['output-source-width-narrowed-to-u16', 'src/output_dimensions.rs', 'output_dimensions',
   'let capped_width = raw.source_width.min(raw.maximum_width);',
   'let capped_width = (raw.source_width as u16 as i64).min(raw.maximum_width);',
   'output_full_signed_projection_does_not_narrow_source_or_cap'],
  ['output-height-narrowed-to-u32', 'src/output_dimensions.rs', 'output_dimensions',
   '((raw.source_height as f64) * (width as f64)', '((raw.source_height as u32 as f64) * (width as f64)',
   'output_full_signed_projection_does_not_narrow_source_or_cap'],
  ['output-maximum-width-narrowed-to-u16', 'src/output_dimensions.rs', 'output_dimensions',
   'let capped_width = raw.source_width.min(raw.maximum_width);',
   'let capped_width = raw.source_width.min(raw.maximum_width as u16 as i64);',
   'output_full_signed_projection_does_not_narrow_source_or_cap'],
  ['output-upper-exclusive-conversion-boundary-weakened', 'src/output_dimensions.rs', 'output_dimensions',
   'rounded_height >= DOUBLE_I64_UPPER_EXCLUSIVE', 'rounded_height > DOUBLE_I64_UPPER_EXCLUSIVE',
   'output_two_to_sixty_three_is_distinct_refusal_not_saturation_or_dimensions'],
  ['output-malformed-envelope-classified-as-legitimate', 'src/output_dimensions.rs', 'output_dimensions',
   'return empty(0);', 'return empty(1);',
   'output_malformed_envelope_is_not_a_legitimate_dimension_error'],
  ['output-unknown-version-admitted', 'src/output_dimensions.rs', 'output_dimensions',
   'raw.abi_version != ABI_VERSION', 'false',
   'output_malformed_envelope_is_not_a_legitimate_dimension_error'],
  ['output-nonzero-reserved-admitted', 'src/output_dimensions.rs', 'output_dimensions',
   'raw.reserved != 0', 'false',
   'output_malformed_envelope_is_not_a_legitimate_dimension_error'],
 ])

# Exact ICE controls from the frozen proposal; each must compile and fail its mapped assertion.
mutants.concat([
  ["ice-grace-discarded", "src/ice_recovery.rs", "ice_recovery", "self.phase = if grace { Phase::Grace } else { Phase::Attempting };", "self.phase = if grace && false { Phase::Grace } else { Phase::Attempting };", "ice_grace_acceleration_advances_epoch_and_coalesces_attempts"],
  ["ice-grace-not-accelerated", "src/ice_recovery.rs", "ice_recovery", "Opcode::Failed | Opcode::Request if [Phase::Idle, Phase::Grace].contains(&s.phase) =>", "Opcode::Failed | Opcode::Request if [Phase::Idle].contains(&s.phase) =>", "ice_grace_acceleration_advances_epoch_and_coalesces_attempts"],
  ["ice-start-epoch-subtracts", "src/ice_recovery.rs", "ice_recovery", "self.epoch = self.epoch.wrapping_add(1);", "self.epoch = self.epoch.wrapping_sub(1);", "ice_epoch_wrap_zero_is_a_current_workflow"],
  ["ice-task-cancellation-ignored", "src/ice_recovery.rs", "ice_recovery", "e.workflow_epoch == self.epoch && e.task_cancelled == 0 && self.phase != Phase::Cancelled", "e.workflow_epoch == self.epoch && self.phase != Phase::Cancelled", "ice_task_cancellation_admission_stops_but_finish_is_epoch_only"],
  ["ice-terminal-signal-guard-removed", "src/ice_recovery.rs", "ice_recovery", "if s.phase == Phase::Cancelled && opcode != Opcode::Cancel { return out; }", "if false { return out; }", "ice_direct_cancel_repeats_but_cancelled_ice_signals_do_not"],
  ["ice-finish-stale-epoch-ignored", "src/ice_recovery.rs", "ice_recovery", "if event.workflow_epoch == s.epoch {", "if true {", "ice_stale_finish_cannot_release_replacement_task"],
  ["ice-finish-wrongly-requires-current-task", "src/ice_recovery.rs", "ice_recovery", "if event.workflow_epoch == s.epoch {", "if event.workflow_epoch == s.epoch && event.task_cancelled == 0 {", "ice_task_cancellation_admission_stops_but_finish_is_epoch_only"],
  ["ice-first-attempt-skipped", "src/ice_recovery.rs", "ice_recovery", "s.attempts += 1;", "s.attempts += 2;", "ice_zero_grace_starts_attempting_without_grace_effect"],
  ["ice-retries-reset-count", "src/ice_recovery.rs", "ice_recovery", "s.attempts += 1;", "s.attempts = 1;", "ice_success_wait_retry_then_exactly_once_exhaustion"],
  ["ice-failed-restart-waits", "src/ice_recovery.rs", "ice_recovery", "if event.succeeded == 1 { s.phase = Phase::Awaiting;", "if true { s.phase = Phase::Awaiting;", "ice_failed_restart_consumes_attempt_and_skips_timeout"],
  ["ice-failed-sleep-continues", "src/ice_recovery.rs", "ice_recovery", "if event.succeeded == 0 { Effect::Stop }", "if false { Effect::Stop }", "ice_each_failed_sleep_stops_then_same_epoch_finish_resets_idle"],
  ["ice-exhaustion-not-committed", "src/ice_recovery.rs", "ice_recovery", "s.delivered = true; s.phase = Phase::Exhausted;", "s.delivered = false; s.phase = Phase::Exhausted;", "ice_success_wait_retry_then_exactly_once_exhaustion"],
  ["ice-nonfinal-attempt-exhausts", "src/ice_recovery.rs", "ice_recovery", "if s.attempts == s.maximum { s.cursor = Cursor::ExhaustAdmission;", "if true { s.cursor = Cursor::ExhaustAdmission;", "ice_failed_restart_consumes_attempt_and_skips_timeout"],
  ["ice-cancel-erases-delivery", "src/ice_recovery.rs", "ice_recovery", "s.phase = Phase::Cancelled; s.cursor = Cursor::None;", "s.delivered = false; s.phase = Phase::Cancelled; s.cursor = Cursor::None;", "ice_cancel_retains_delivered_flag_but_clears_attempts"],
  ["ice-config-zero-accepted", "src/ice_recovery.rs", "ice_recovery", "config.maximum_attempts <= 0", "config.maximum_attempts < 0", "ice_initializer_refuses_nonpositive_reserved_and_noncanonical"],
  ["ice-event-boolean-two-accepted", "src/ice_recovery.rs", "ice_recovery", "e.task_cancelled > 1", "e.task_cancelled > 2", "ice_event_envelope_rejects_alias_boolean_reserved_and_unused_fields"],
  ["ice-state-abi-not-checked", "src/ice_recovery.rs", "ice_recovery", "s.abi_version != ABI || s.maximum_attempts <= 0", "false || s.maximum_attempts <= 0", "ice_state_envelope_rejects_every_closed_field_corruption"],
  ["ice-current-wait-kind-ignored", "src/ice_recovery.rs", "ice_recovery", "&& s.wait_kind() != event.wait_kind", "&& false", "ice_current_wait_kind_and_program_counter_are_exact"],
  ["ice-before-copy-corrupted", "src/ice_recovery.rs", "ice_recovery", "copied_before: before, copied_event: event,", "copied_before: State::default(), copied_event: event,", "ice_success_wait_retry_then_exactly_once_exhaustion"],
  ["ice-event-copy-corrupted", "src/ice_recovery.rs", "ice_recovery", "copied_before: before, copied_event: event,", "copied_before: before, copied_event: Event::default(),", "ice_success_wait_retry_then_exactly_once_exhaustion"],
])

# Exact liveness unit controls; old integration controls retain their original selection.
mutants.concat([
  ["liveness-intentional-cover-state-replaced", "src/screen_liveness.rs", "screen_liveness", "if sample.cover == 1 { 0 }", "if sample.cover == 1 { 3 }", "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence"],
  ["liveness-other-covers-ignored", "src/screen_liveness.rs", "screen_liveness", "else if sample.cover != 0 { 1 }", "else if false && sample.cover != 0 { 1 }", "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence"],
  ["liveness-track-guard-ignored", "src/screen_liveness.rs", "screen_liveness", "else if sample.track_attached == 0 { 2 }", "else if false && sample.track_attached == 0 { 2 }", "screen_liveness::tests::missing_track_precedes_initial_and_render_evidence"],
  ["liveness-reset-awaiting-ignored", "src/screen_liveness.rs", "screen_liveness", "else if reset_reason != 0 { 3 }", "else if false && reset_reason != 0 { 3 }", "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock"],
  ["liveness-initial-floor-forgotten", "src/screen_liveness.rs", "screen_liveness", "if before.previous_present == 0 { 1 }", "if before.previous_present == 2 { 1 }", "screen_liveness::tests::cover_before_track_before_initial_and_reset_evidence"],
  ["liveness-generation-change-ignored", "src/screen_liveness.rs", "screen_liveness", "else if before.previous.generation != sample.generation { 2 }", "else if false && before.previous.generation != sample.generation { 2 }", "screen_liveness::tests::generation_inequality_wins_over_regression_including_max_to_zero"],
  ["liveness-regression-counter-0-ignored", "src/screen_liveness.rs", "screen_liveness", "current.iter().zip(previous).any(|(current, previous)|\n            current.zip(previous).is_some_and(|(current, previous)| current < previous))", "current.iter().zip(previous).enumerate().any(|(index, (current, previous))|\n            index != 0 && current.zip(previous).is_some_and(|(current, previous)| current < previous))", "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock"],
  ["liveness-regression-counter-1-ignored", "src/screen_liveness.rs", "screen_liveness", "current.iter().zip(previous).any(|(current, previous)|\n            current.zip(previous).is_some_and(|(current, previous)| current < previous))", "current.iter().zip(previous).enumerate().any(|(index, (current, previous))|\n            index != 1 && current.zip(previous).is_some_and(|(current, previous)| current < previous))", "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock"],
  ["liveness-regression-counter-2-ignored", "src/screen_liveness.rs", "screen_liveness", "current.iter().zip(previous).any(|(current, previous)|\n            current.zip(previous).is_some_and(|(current, previous)| current < previous))", "current.iter().zip(previous).enumerate().any(|(index, (current, previous))|\n            index != 2 && current.zip(previous).is_some_and(|(current, previous)| current < previous))", "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock"],
  ["liveness-regression-counter-3-ignored", "src/screen_liveness.rs", "screen_liveness", "current.iter().zip(previous).any(|(current, previous)|\n            current.zip(previous).is_some_and(|(current, previous)| current < previous))", "current.iter().zip(previous).enumerate().any(|(index, (current, previous))|\n            index != 3 && current.zip(previous).is_some_and(|(current, previous)| current < previous))", "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock"],
  ["liveness-regression-counter-4-ignored", "src/screen_liveness.rs", "screen_liveness", "current.iter().zip(previous).any(|(current, previous)|\n            current.zip(previous).is_some_and(|(current, previous)| current < previous))", "current.iter().zip(previous).enumerate().any(|(index, (current, previous))|\n            index != 4 && current.zip(previous).is_some_and(|(current, previous)| current < previous))", "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock"],
  ["liveness-regression-counter-5-ignored", "src/screen_liveness.rs", "screen_liveness", "current.iter().zip(previous).any(|(current, previous)|\n            current.zip(previous).is_some_and(|(current, previous)| current < previous))", "current.iter().zip(previous).enumerate().any(|(index, (current, previous))|\n            index != 5 && current.zip(previous).is_some_and(|(current, previous)| current < previous))", "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock"],
  ["liveness-reset-retains-recent-change", "src/screen_liveness.rs", "screen_liveness", "let last_change = if reset_reason != 0 { None }", "let last_change = if reset_reason != 0 { before.last_change_at.value() }", "screen_liveness::tests::each_single_counter_regression_clears_all_six_deltas_and_recent_clock"],
  ["liveness-positive-change-clock-is-not-current", "src/screen_liveness.rs", "screen_liveness", "Some(sample.observed_at)", "Some(before.previous.observed_at)", "screen_liveness::tests::covered_samples_still_advance_floor_and_change_clock"],
  ["liveness-last-change-forgotten-without-new-change", "src/screen_liveness.rs", "screen_liveness", "else { before.last_change_at.value() };", "else { None };", "screen_liveness::tests::advancing_unchanged_frame_ignores_recent_content_clock_then_retained_frame_uses_it"],
  ["liveness-covered-floor-not-committed", "src/screen_liveness.rs", "screen_liveness", "previous: sample }, snapshot", "previous: if sample.cover == 0 { sample } else { before.previous } }, snapshot", "screen_liveness::tests::covered_samples_still_advance_floor_and_change_clock"],
  ["liveness-missing-track-floor-not-committed", "src/screen_liveness.rs", "screen_liveness", "previous: sample }, snapshot", "previous: if sample.track_attached == 1 { sample } else { before.previous } }, snapshot", "screen_liveness::tests::missing_track_samples_still_advance_floor_and_change_clock"],
  ["liveness-counter-u32-truncation", "src/screen_liveness.rs", "screen_liveness", "current.checked_sub(previous)", "(current as u32 as u64).checked_sub(previous as u32 as u64)", "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped"],
  ["liveness-counter-f64-rounding", "src/screen_liveness.rs", "screen_liveness", "current.checked_sub(previous)", "Some((current as f64 - previous as f64) as u64)", "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped"],
  ["liveness-absent-counter-is-zero", "src/screen_liveness.rs", "screen_liveness", "(self.present == 1).then_some(self.value)", "Some(self.value)", "screen_liveness::tests::optional_counter_holes_only_break_adjacent_comparison"],
  ["liveness-age-ceil-replaces-floor", "src/screen_liveness.rs", "screen_liveness", "(ns / 1_000_000).min(MAX_PRESENTATION_AGE_MS)", "(ns / 1_000_000 + u64::from(ns % 1_000_000 != 0)).min(MAX_PRESENTATION_AGE_MS)", "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct"],
  ["liveness-presentation-freshness-exclusive", "src/screen_liveness.rs", "screen_liveness", "age <= FRESH_PRESENTATION_NS / 1_000_000", "age < FRESH_PRESENTATION_NS / 1_000_000", "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct"],
  ["liveness-content-freshness-exclusive", "src/screen_liveness.rs", "screen_liveness", "sample.observed_at - change <= FRESH_PRESENTATION_NS", "sample.observed_at - change < FRESH_PRESENTATION_NS", "screen_liveness::tests::presentation_floor_milliseconds_and_content_exact_nanoseconds_remain_distinct"],
  ["liveness-future-content-change-is-fresh", "src/screen_liveness.rs", "screen_liveness", "sample.observed_at >= change && sample.observed_at - change <= FRESH_PRESENTATION_NS", "sample.observed_at.abs_diff(change) <= FRESH_PRESENTATION_NS", "screen_liveness::tests::future_presentation_is_zero_age_but_future_content_change_is_not_fresh"],
  ["liveness-future-presentation-age-not-zero", "src/screen_liveness.rs", "screen_liveness", "let ns = if sample.observed_at >= sample.presented_at {\n            sample.observed_at - sample.presented_at\n        } else { 0 };", "let ns = sample.observed_at.abs_diff(sample.presented_at);", "screen_liveness::tests::future_presentation_is_zero_age_but_future_content_change_is_not_fresh"],
  ["liveness-age-saturation-removed", "src/screen_liveness.rs", "screen_liveness", "(ns / 1_000_000).min(MAX_PRESENTATION_AGE_MS)", "ns / 1_000_000", "screen_liveness::tests::presentation_age_saturates_after_safe_full_width_subtraction"],
  ["liveness-presented-progress-ignored", "src/screen_liveness.rs", "screen_liveness", "else if deltas[3].is_some_and(|value| value > 0) {", "else if false && deltas[3].is_some_and(|value| value > 0) {", "screen_liveness::tests::presented_progress_precedes_stale_age_and_inbound_decode_stalls"],
  ["liveness-advancing-unchanged-frame-uses-recent-clock", "src/screen_liveness.rs", "screen_liveness", "if deltas[5].is_some_and(|value| value > 0) { 8 } else { 7 }", "if content_fresh { 8 } else { 7 }", "screen_liveness::tests::advancing_unchanged_frame_ignores_recent_content_clock_then_retained_frame_uses_it"],
  ["liveness-fresh-presentation-zero-content-is-enough", "src/screen_liveness.rs", "screen_liveness", "presentation_fresh && sample.content_samples > 0", "presentation_fresh", "screen_liveness::tests::fresh_presentation_still_requires_positive_content_samples"],
  ["liveness-zero-inbound-precedence-removed", "src/screen_liveness.rs", "screen_liveness", "if inbound.iter().any(Option::is_some) && inbound.iter().flatten().all(|value| *value == 0) { 4 }", "if false && inbound.iter().any(Option::is_some) && inbound.iter().flatten().all(|value| *value == 0) { 4 }", "screen_liveness::tests::zero_inbound_precedes_decoded_progress_and_optional_positive_order_is_original"],
  ["liveness-missing-decoded-evidence-is-presentation-stall", "src/screen_liveness.rs", "screen_liveness", "Some(_) => 6, None => 3", "Some(_) => 6, None => 6", "screen_liveness::tests::zero_inbound_precedes_decoded_progress_and_optional_positive_order_is_original"],
  ["liveness-dimension-one-rejected", "src/screen_liveness.rs", "screen_liveness", "(1..=32_768).contains(&(*bits as i64))", "(2..=32_768).contains(&(*bits as i64))", "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds"],
  ["liveness-dimension-32768-rejected", "src/screen_liveness.rs", "screen_liveness", "(1..=32_768).contains(&(*bits as i64))", "(1..=32_767).contains(&(*bits as i64))", "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds"],
  ["liveness-dimension-u32-alias-admitted", "src/screen_liveness.rs", "screen_liveness", "(1..=32_768).contains(&(*bits as i64))", "(1..=32_768).contains(&(*bits as u32 as i64))", "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds"],
  ["liveness-render-width-fallback-erased", "src/screen_liveness.rs", "screen_liveness", "dimension(render_width)\n            .or_else(|| dimension(sample.inbound_width.value()))", "dimension(render_width)", "screen_liveness::tests::dimensions_choose_each_axis_independently_with_inclusive_original_bounds"],
  ["liveness-fps-zero-rejected", "src/screen_liveness.rs", "screen_liveness", "(0.0..=1_000.0).contains(&value)", "(f64::EPSILON..=1_000.0).contains(&value)", "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range"],
  ["liveness-fps-1000-rejected", "src/screen_liveness.rs", "screen_liveness", "(0.0..=1_000.0).contains(&value)", "(0.0..=999.0).contains(&value)", "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range"],
  ["liveness-inbound-record-presence-erased", "src/screen_liveness.rs", "screen_liveness", "previous: sample }, snapshot", "previous: RawSample { inbound_present: 0, ..sample } }, snapshot", "screen_liveness::tests::metadata_only_inbound_record_presence_is_not_fabricated_or_erased"],
  ["liveness-generation-u32-truncation", "src/screen_liveness.rs", "screen_liveness", "generation: sample.generation,", "generation: sample.generation as u32 as u64,", "screen_liveness::tests::full_width_counters_are_neither_truncated_rounded_nor_wrapped"],
  ["liveness-raw-fps-payload-normalized", "src/screen_liveness.rs", "screen_liveness", "previous: sample }, snapshot", "previous: RawSample { frames_per_second_bits: RawOptional::some(0), ..sample } }, snapshot", "screen_liveness::tests::fps_option_preserves_raw_bits_and_filters_only_original_finite_range"],
  ["liveness-raw-abi-zero-is-admitted", "src/screen_liveness.rs", "screen_liveness", "if abi_version != ABI_VERSION || !before.valid() || !sample.valid() {", "if (abi_version != 0 && abi_version != ABI_VERSION) || !before.valid() || !sample.valid() {", "screen_liveness::tests::unknown_zero_and_full_width_abi_refuse_complete_copied_state"],
  ["liveness-raw-abi-max-is-admitted", "src/screen_liveness.rs", "screen_liveness", "if abi_version != ABI_VERSION || !before.valid() || !sample.valid() {", "if (abi_version != u64::MAX && abi_version != ABI_VERSION) || !before.valid() || !sample.valid() {", "screen_liveness::tests::unknown_zero_and_full_width_abi_refuse_complete_copied_state"],
  ["liveness-absent-inbound-payload-is-admitted", "src/screen_liveness.rs", "screen_liveness", "(self.inbound_present == 1 || [self.inbound_bytes, self.inbound_packets,", "(true || [self.inbound_bytes, self.inbound_packets,", "screen_liveness::tests::absent_inbound_record_rejects_each_nonzero_optional_payload_unchanged"],
  ["liveness-malformed-change-option-is-admitted", "src/screen_liveness.rs", "screen_liveness", "self.previous_present <= 1 && self.last_change_at.valid()", "self.previous_present <= 1", "screen_liveness::tests::malformed_recent_change_option_refuses_complete_before_state_unchanged"],
  ["liveness-absent-before-payload-is-admitted", "src/screen_liveness.rs", "screen_liveness", "&& (self.previous_present == 1\n                || (self.previous == RawSample::default()", "&& (true\n                || (self.previous == RawSample::default()", "screen_liveness::tests::absent_previous_sample_and_change_payloads_refuse_complete_before_state_unchanged"],
])

# The old 306 controls keep their failure-only contract. New updater controls require restoration too.
mutants.concat(BelugaCoreUpdaterMutationOracle::CONTROLS)
mutants.concat(BelugaCorePacketQueueMutationOracle::CONTROLS)
mutants.concat(BelugaCoreRTTEvidenceMutationOracle::CONTROLS)
mutants.concat(BelugaCoreTierDemandMutationOracle::CONTROLS)
mutants.concat(BelugaCoreMediaCommandGateMutationOracle::CONTROLS)
mutants.concat(BelugaCoreScreenSuspensionMutationOracle::CONTROLS)
mutants.concat(BelugaCorePhoneCatalogMutationOracle::CONTROLS)
mutants.concat(BelugaCoreOwnerClockedMutationOracle::CONTROLS)
mutants.concat(BelugaCoreOwnerPrepareMutationOracle::CONTROLS)
mutants.concat(BelugaCoreOwnerInactiveMutationOracle::CONTROLS)
mutants.concat(BelugaCoreOwnerBeginActiveMutationOracle::CONTROLS)
mutants.concat(BelugaCoreOwnerPostAwaitMutationOracle::CONTROLS)
mutants.concat(BelugaCoreMicrophoneRetryMutationOracle::CONTROLS)
mutants.concat(BelugaCoreUpdateAdmissionMutationOracle::CONTROLS)
mutants.concat(BelugaCoreUpdateSparkleAdmissionMutationOracle::CONTROLS)
mutants.concat(BelugaCoreHandoffSourceMutationOracle::CONTROLS)
mutants.concat(BelugaCoreMicrophoneInputLeaseMutationOracle::CONTROLS)
mutants.concat(BelugaCoreMicrophoneOutputFormatMutationOracle::CONTROLS)
mutants = BelugaCoreUpdaterMutationOracle::CONTROLS if updater_only
mutants = BelugaCorePacketQueueMutationOracle::CONTROLS if queue_only
mutants = BelugaCoreRTTEvidenceMutationOracle::CONTROLS if rtt_only
mutants = BelugaCoreTierDemandMutationOracle::CONTROLS if tier_demand_only
mutants = BelugaCoreMediaCommandGateMutationOracle::CONTROLS if media_command_gate_only
mutants = BelugaCoreScreenSuspensionMutationOracle::CONTROLS if screen_suspension_only
mutants = BelugaCorePhoneCatalogMutationOracle::CONTROLS if phone_catalog_only
mutants = BelugaCoreOwnerClockedMutationOracle::CONTROLS if owner_clocked_only
mutants = BelugaCoreOwnerPrepareMutationOracle::CONTROLS if owner_prepare_only
mutants = BelugaCoreOwnerInactiveMutationOracle::CONTROLS if owner_inactive_only
mutants = BelugaCoreOwnerBeginActiveMutationOracle::CONTROLS if owner_begin_active_only
mutants = BelugaCoreOwnerPostAwaitMutationOracle::CONTROLS if owner_post_await_only
mutants = BelugaCoreMicrophoneRetryMutationOracle::CONTROLS if microphone_retry_only
mutants = BelugaCoreUpdateAdmissionMutationOracle::CONTROLS if update_admission_only
mutants = BelugaCoreUpdateSparkleAdmissionMutationOracle::CONTROLS if update_sparkle_admission_only
mutants = BelugaCoreHandoffSourceMutationOracle::CONTROLS if handoff_source_only
mutants = BelugaCoreMicrophoneInputLeaseMutationOracle::CONTROLS if microphone_input_lease_only
mutants = BelugaCoreMicrophoneOutputFormatMutationOracle::CONTROLS if microphone_output_format_only

mutants.each do |name, path, suite, original, changed, test|
  update_admission = BelugaCoreUpdateAdmissionMutationOracle::NAMES.include?(name)
  update_sparkle_admission = BelugaCoreUpdateSparkleAdmissionMutationOracle::NAMES.include?(name)
  handoff_source = BelugaCoreHandoffSourceMutationOracle::NAMES.include?(name)
  microphone_input_lease = BelugaCoreMicrophoneInputLeaseMutationOracle::NAMES.include?(name)
  microphone_output_format = BelugaCoreMicrophoneOutputFormatMutationOracle::NAMES.include?(name)
  owner_clocked = BelugaCoreOwnerClockedMutationOracle::NAMES.include?(name)
  owner_prepare = BelugaCoreOwnerPrepareMutationOracle::NAMES.include?(name)
  owner_inactive = BelugaCoreOwnerInactiveMutationOracle::NAMES.include?(name)
  owner_begin_active = BelugaCoreOwnerBeginActiveMutationOracle::NAMES.include?(name)
  owner_post_await = BelugaCoreOwnerPostAwaitMutationOracle::NAMES.include?(name)
  owner_full = owner_clocked || owner_prepare || owner_inactive || owner_begin_active || owner_post_await
  owner_source_before = BelugaCoreOwnerClockedMutationOracle.source_fence(BelugaCoreArtifact::CRATE) if owner_full
  production = File.binread(File.join(BelugaCoreArtifact::CRATE, path))
  raise "Mutation anchor not unique: #{name}" unless production.scan(original).size == 1
  Dir.mktmpdir("mutant-#{name}-", work) do |copy|
    %w[Cargo.toml Cargo.lock rust-toolchain.toml src tests].each do |path|
      FileUtils.cp_r(File.join(BelugaCoreArtifact::CRATE, path), File.join(copy, path))
    end
    File.binwrite(File.join(copy, path), production.sub(original, changed))
    env = BelugaCoreArtifact.environment(File.join(copy, 'target'))
    selection = suite == 'screen_liveness' || owner_full ? ['--lib'] : ['--test', suite]
    updater = BelugaCoreUpdaterMutationOracle::NAMES.include?(name)
    queue = BelugaCorePacketQueueMutationOracle::NAMES.include?(name)
    rtt = BelugaCoreRTTEvidenceMutationOracle::NAMES.include?(name)
    tier_demand = BelugaCoreTierDemandMutationOracle::NAMES.include?(name)
    media_command_gate = BelugaCoreMediaCommandGateMutationOracle::NAMES.include?(name)
    screen_suspension = BelugaCoreScreenSuspensionMutationOracle::NAMES.include?(name)
    phone_catalog = BelugaCorePhoneCatalogMutationOracle::NAMES.include?(name)
    microphone_retry = BelugaCoreMicrophoneRetryMutationOracle::NAMES.include?(name)
    begin
      output, error, status = Open3.capture3(env, BelugaCoreArtifact::CARGO, 'test', '--offline', '--locked',
        *selection, test, '--', '--exact', '--test-threads=1', chdir: copy)
      combined = output + error
      puts combined
      raise "Mutant #{name} compiled unsuccessfully; not a behavioral oracle" if combined.include?('could not compile')
      raise "Mutant #{name} survived or lacked an assertion failure" unless status.exitstatus == 101 &&
        combined.include?('assertion `left == right` failed') && combined.include?("#{test} ... FAILED") &&
        combined.include?('1 failed')
      if updater
        BelugaCoreUpdaterMutationOracle.validate_exit!(status.exitstatus, status.termsig, 101)
        BelugaCoreUpdaterMutationOracle.validate_rejected!(combined, test)
      end
      if queue
        BelugaCoreUpdaterMutationOracle.validate_exit!(status.exitstatus, status.termsig, 101)
        BelugaCorePacketQueueMutationOracle.validate!(combined, test, passed: false)
      end
      if rtt
        BelugaCoreUpdaterMutationOracle.validate_exit!(status.exitstatus, status.termsig, 101)
        BelugaCoreRTTEvidenceMutationOracle.validate!(combined, test, passed: false)
      end
      if tier_demand
        BelugaCoreUpdaterMutationOracle.validate_exit!(status.exitstatus, status.termsig, 101)
        BelugaCoreTierDemandMutationOracle.validate!(combined, test, passed: false)
      end
      if media_command_gate
        BelugaCoreUpdaterMutationOracle.validate_exit!(status.exitstatus, status.termsig, 101)
        BelugaCoreMediaCommandGateMutationOracle.validate!(combined, test, passed: false)
      end
      if screen_suspension
        BelugaCoreUpdaterMutationOracle.validate_exit!(status.exitstatus, status.termsig, 101)
        BelugaCoreScreenSuspensionMutationOracle.validate!(combined, test, passed: false)
      end
      if phone_catalog
        BelugaCorePhoneCatalogMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if owner_clocked
        BelugaCoreOwnerClockedMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if owner_prepare
        BelugaCoreOwnerPrepareMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if owner_inactive
        BelugaCoreOwnerInactiveMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if owner_begin_active
        BelugaCoreOwnerBeginActiveMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if owner_post_await
        BelugaCoreOwnerPostAwaitMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if microphone_retry
        BelugaCoreMicrophoneRetryMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if update_admission
        BelugaCoreUpdateAdmissionMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if update_sparkle_admission
        BelugaCoreUpdateSparkleAdmissionMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if handoff_source
        BelugaCoreHandoffSourceMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if microphone_input_lease
        BelugaCoreMicrophoneInputLeaseMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if microphone_output_format
        BelugaCoreMicrophoneOutputFormatMutationOracle.validate!(combined, test, passed: false,
          exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
      end
      if owner_full
        BelugaCoreOwnerClockedMutationOracle.verify_source_fence!(copy,
          owner_source_before.merge(path => Digest::SHA256.hexdigest(production.sub(original, changed))))
      end
      puts "Behavioral mutation rejected: #{name}"
      puts "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed"
      if updater || queue || rtt || tier_demand || media_command_gate || screen_suspension || phone_catalog || owner_full || microphone_retry || update_admission || update_sparkle_admission || handoff_source || microphone_input_lease || microphone_output_format
        # Restore only the disposable copy; production and its exact test bytes remain unchanged.
        File.binwrite(File.join(copy, path), production)
        raise "Updater source restoration differs: #{name}" unless File.binread(File.join(copy, path)) == production
        output, error, status = Open3.capture3(env, BelugaCoreArtifact::CARGO, 'test', '--offline', '--locked',
          *selection, test, '--', '--exact', '--test-threads=1', chdir: copy)
        combined = output + error
        puts combined
        BelugaCoreUpdaterMutationOracle.validate_exit!(status.exitstatus, status.termsig, 0)
        if updater
          BelugaCoreUpdaterMutationOracle.validate_restored!(combined, test)
        elsif queue
          BelugaCorePacketQueueMutationOracle.validate!(combined, test, passed: true)
        elsif rtt
          BelugaCoreRTTEvidenceMutationOracle.validate!(combined, test, passed: true)
        elsif tier_demand
          BelugaCoreTierDemandMutationOracle.validate!(combined, test, passed: true)
        elsif media_command_gate
          BelugaCoreMediaCommandGateMutationOracle.validate!(combined, test, passed: true)
        elsif screen_suspension
          BelugaCoreScreenSuspensionMutationOracle.validate!(combined, test, passed: true)
        elsif owner_clocked
          BelugaCoreOwnerClockedMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif owner_prepare
          BelugaCoreOwnerPrepareMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif owner_inactive
          BelugaCoreOwnerInactiveMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif owner_begin_active
          BelugaCoreOwnerBeginActiveMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif owner_post_await
          BelugaCoreOwnerPostAwaitMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif microphone_retry
          BelugaCoreMicrophoneRetryMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif update_admission
          BelugaCoreUpdateAdmissionMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif update_sparkle_admission
          BelugaCoreUpdateSparkleAdmissionMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif handoff_source
          BelugaCoreHandoffSourceMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif microphone_input_lease
          BelugaCoreMicrophoneInputLeaseMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        elsif microphone_output_format
          BelugaCoreMicrophoneOutputFormatMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        else
          BelugaCorePhoneCatalogMutationOracle.validate!(combined, test, passed: true,
            exitstatus: status.exitstatus, termsig: status.termsig, timed_out: false)
        end
        raise "Updater restored source changed during baseline: #{name}" unless File.binread(File.join(copy, path)) == production
        test_path = if owner_clocked
          BelugaCoreOwnerClockedMutationOracle::TEST_PATH
        elsif owner_prepare
          BelugaCoreOwnerPrepareMutationOracle::TEST_PATH
        elsif owner_inactive
          BelugaCoreOwnerInactiveMutationOracle::TEST_PATH
        elsif owner_begin_active
          BelugaCoreOwnerBeginActiveMutationOracle::TEST_PATH
        elsif owner_post_await
          BelugaCoreOwnerPostAwaitMutationOracle::TEST_PATHS.fetch(test)
        else
          File.join('tests', suite + '.rs')
        end
        raise "Updater test body changed: #{name}" unless
          File.binread(File.join(copy, test_path)) == File.binread(File.join(BelugaCoreArtifact::CRATE, test_path))
        BelugaCoreOwnerClockedMutationOracle.verify_source_fence!(copy, owner_source_before) if owner_full
        puts "BELUGA_CORE_MUTANT_RESTORED #{name} baseline-passed"
      end
    ensure
      BelugaCoreOwnerClockedMutationOracle.verify_source_fence!(BelugaCoreArtifact::CRATE, owner_source_before) if owner_full
      raise "Original production source changed: #{name}" if (updater || queue || rtt || tier_demand || media_command_gate || screen_suspension || phone_catalog || owner_full || microphone_retry || update_admission || update_sparkle_admission || handoff_source || microphone_input_lease || microphone_output_format) &&
        File.binread(File.join(BelugaCoreArtifact::CRATE, path)) != production
    end
  end
end
puts "BelugaCore mutation oracles PASS: #{mutants.size} assertion-failing mutants"
puts "BELUGA_CORE_MUTATIONS_PASS cases=#{mutants.size}"
end
