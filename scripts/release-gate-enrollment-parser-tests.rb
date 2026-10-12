# Source-only parser/fixture proposal; no compiler, SDK, Simulator, device,
# installed host, CoreAudio, credential or network action is used by these cases.
# Enroll by requiring this file in test-validate-microphone-regressions.rb and
# including this module in MicrophoneRegressionGateTests after the class body.
module MicrophoneReleaseGateEnrollmentParserTests
  Gate = MicrophoneRegressionGate

  ABORT_EXPECTED_RUST = %w[
    wire_layout_offsets_and_literal_constants_are_fixed
    all_64_valid_carriers_match_the_literal_original_first_if_else_if
    first_if_mark_abort_wins_even_when_same_no_update_error_is_true
    preserve_else_if_is_not_strengthened_by_unrelated_failure_facts
    unsupported_abi_and_every_unknown_flag_refuse_without_valid_action
    every_result_field_and_coherent_cross_request_action_require_full_correlation
    actual_c_exports_match_the_literal_original_and_refuse_unverified_carriers
  ].freeze
  ABORT_EXPECTED_SWIFT = %w[
    CaptureServerTests.BelugaRustUpdateAbortTests/testExactRequestAndResultLayoutsThroughActualC
    CaptureServerTests.BelugaRustUpdateAbortTests/testAllSixFactBitsAndOriginalFirstIfPriorityThroughActualClassify
    CaptureServerTests.BelugaRustUpdateAbortTests/testUnknownABIAndEveryUnknownFlagRefuse
    CaptureServerTests.BelugaRustUpdateAbortTests/testWholeResultFieldsAndCoherentWrongSupportedActionsRefuse
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testMatchedAbortPreservesNativeNSErrorIdentityAndObservation
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testDuplicateAcknowledgedAbortPoisonsWhileStillDeliveringOriginalEvent
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerAbortProducerABIControlHasAttributedLeaseWitness
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerAbortVerifierTwoControlHasAttributedLeaseWitness
    CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerAbortCoherentActionControlHasAttributedLeaseWitness
  ].freeze

  HANDOFF_SOURCE_EXPECTED_RUST = %w[
    every_native_flag_combination_preserves_missing_and_identity_refusals
    unknown_bits_wrong_abi_and_reserved_fields_are_malformed_not_business_refusals
    preparation_scalar_edges_and_nonfinite_values_match_frozen_swift
    option_absence_is_a_valid_refusal_and_does_not_invent_payload_authority
    exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct
    page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain
    changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift
    signed_zero_raw_bits_and_original_unissuable_match_inputs_are_not_normalized
    copied_results_cannot_forge_allow_refuse_abi_status_or_reserved_fields
    copied_c_layouts_pin_every_word_and_no_pointer_or_native_object
    actual_c_exports_and_validators_preserve_votes_and_malformed_refusal
  ].freeze
  HANDOFF_SOURCE_EXPECTED_SWIFT = %w[
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testImportedLayoutsAndEveryNumericPrepareAxisAgainstFrozenNativeReducer
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testOptionalPresenceAndNativeCapabilityAdmissionRemainExact
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testEveryCurrentNumericMatchAxisAndNilAgainstFrozenNativeReducer
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testNativeMatchStringFactsAreExactNotUUIDNormalizationOrHashAuthority
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testMatchToleranceBoundariesAndNoConstructorRevalidation
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testAdmittedAnchorNumericAxesRemainUnrewrittenAtMatchesBoundary
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testRawMatchPredicateHasNoExtraAnchorCapturePolicyOrFusedArithmetic
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testMalformedABIReservedAndUnknownFlagsFailClosedButMissingFactsAreOrdinaryRefusal
    CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests/testForeignResultsAndEveryCopiedResultFieldUseActualRustValidators
  ].freeze
  HANDOFF_SOURCE_EXPECTED_MARKERS = [
    'BelugaCore C handoff source ABI PASS: exact layouts, timeline/phone boundaries, whole correlation and refusal',
    'BelugaCore Swift handoff source ABI PASS: exact layouts, timeline/phone boundaries, whole correlation and refusal',
  ].freeze

  INPUT_LEASE_EXPECTED_RUST = %w[
    input_lease_literal_layout_and_field_offsets
    input_lease_acquisition_budget_preserves_literal_one_and_three_caps
    input_lease_acquisition_native_outcomes_have_three_literal_actions
    input_lease_release_continuation_requires_retryable_and_strict_budget
    input_lease_release_outcome_preserves_native_fallback_and_external_result
    input_lease_closed_wire_rejects_all_unused_and_negative_domains
    input_lease_verifier_rejects_each_field_and_coherent_cross_operation_results
    input_lease_actual_c_exports_correlate_accepted_and_refused_results
  ].freeze
  INPUT_LEASE_EXPECTED_SWIFT = %w[
    CaptureServerTests.BelugaRustMicrophoneInputLeaseTests/testInputLeaseLiteralLayoutsAndAllFourCopiedOperations
    CaptureServerTests.BelugaRustMicrophoneInputLeaseTests/testInputLeaseNativeIntegerBoundaryAndNoSuccessfulSwiftFallback
    CaptureServerTests.BelugaRustMicrophoneInputLeaseTests/testInputLeaseWholeResultRejectsEveryFieldAndCoherentWrongAction
    CaptureServerTests.BelugaRustMicrophoneInputLeaseTests/testInputLeaseMalformedFactsRemainRefusedEvenWithCanonicalInvalidResult
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseAdmissionPreservesClampedOneAndLiteralThreeBudgets
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseNativeOutcomeKeepsProofLazyAndTerminalCleanupExact
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseReleaseVoteKeepsOneExactCleanupEpisodeAndExternalFence
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseRetainedCleanupRedrivesOnSameHealthyIdentityWithoutReadmission
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseProtectionRetainsNestedUncertaintyAndExactPendingCleanup
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseContextRetainsNestedNewerPeerWhenOwnerDoesNotChange
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseContextRetainsNestedMonitorWhenOwnerDoesNotChange
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseContextRetainsNestedDeviceSnapshotWhenOwnerDoesNotChange
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodePreservesReentrantReplacementForEveryActualDisposition
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodeDoesNotOverwriteReentrantNewerHealthyPeer
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodeDoesNotOverwriteReentrantMonitorEpoch
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodeFencesSameGenerationAuthorizationChange
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testNativeReleaseEpisodeStopsBeforeGenerationlessShutdownAfterNestedCleanup
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseActualCRefusalAfterAcquiredKeepsExactCleanupOwnership
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseActualCRefusalAtPostKeyLoopBudgetKeepsExactCleanupOwnership
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testRustInputLeaseActualCRefusalAfterFirstRetryableReleaseKeepsExactCleanupOwnership
  ].freeze
  INPUT_LEASE_EXPECTED_MARKERS = [
    'BelugaCore C input lease ABI PASS: four copied operations, literal layouts, full-width counts and whole refusal',
    'BelugaCore Swift input lease ABI PASS: four copied operations, literal layouts, full-width counts and whole refusal',
  ].freeze

  INPUT_LEASE_EXPECTED_MUTANTS = {
    'MIC-INPUT-ACQUIRE-BUDGET' => 'input_lease_acquisition_budget_preserves_literal_one_and_three_caps',
    'MIC-INPUT-ACQUIRED' => 'input_lease_acquisition_native_outcomes_have_three_literal_actions',
    'MIC-INPUT-RELEASE-BUDGET' => 'input_lease_release_continuation_requires_retryable_and_strict_budget',
    'MIC-INPUT-FALLBACK' => 'input_lease_release_outcome_preserves_native_fallback_and_external_result',
    'MIC-INPUT-CLOSED-WIRE' => 'input_lease_closed_wire_rejects_all_unused_and_negative_domains',
    'MIC-INPUT-WHOLE-RESULT' => 'input_lease_verifier_rejects_each_field_and_coherent_cross_operation_results',
    'MIC-INPUT-C-PRODUCER' => 'input_lease_actual_c_exports_correlate_accepted_and_refused_results',
    'MIC-INPUT-C-VERIFIER' => 'input_lease_actual_c_exports_correlate_accepted_and_refused_results',
  }.freeze

  OUTPUT_FORMAT_EXPECTED_RUST = %w[
    output_format_literal_contract_preserves_signed_and_full_width_fields
    output_format_acceptance_copies_all_twelve_observation_fields
    output_format_each_known_rejection_is_a_valid_projection
    output_format_every_simultaneous_error_pair_preserves_first_guard
    output_format_four_signed_statuses_preserve_negative_and_extreme_values
    output_format_integer_fields_are_exact_not_masks_ranges_or_truncated_values
    output_format_rates_use_numeric_equality_but_rejections_keep_original_bits
    output_format_malformed_wire_is_not_an_ordinary_policy_rejection
    output_format_authoritative_verifier_rejects_corruption_of_every_result_field
    output_format_verifier_rejects_coherent_wrong_success_rejection_and_precedence
    output_format_raw_nan_result_equality_is_reflexive_and_payload_exact
    output_format_actual_c_exports_correlate_success_rejection_and_refusal
  ].freeze
  OUTPUT_FORMAT_EXPECTED_SWIFT = %w[
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatLiteralLayoutsAndEveryFieldOffset
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatExactSuccessAndSDKLiteralParity
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatAllSixteenKnownRejectionsMatchOriginalSwift
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatEverySimultaneousErrorPairKeepsOriginalFirstGuard
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatAllFourSignedStatusExtremesPreserveOriginalDiagnostics
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatAllUInt32DomainsStayExactAndFullWidth
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatRateEdgeCasesAndNaNPayloadsMatchOriginalBits
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatCopiesAllNativeReadValuesWithoutNormalization
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatWholeResultRejectsAllTwentyFieldCorruptions
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatWholeResultRejectsCoherentWrongDecision
    CaptureServerTests.BelugaRustMicrophoneOutputFormatTests/testOutputFormatMalformedWireThrowsWithoutSwiftFallback
  ].freeze
  OUTPUT_FORMAT_EXPECTED_MARKERS = [
    'BelugaCore C output format ABI PASS: literal layouts, sixteen ordered guards, exact observations and whole refusal',
    'BelugaCore Swift output format ABI PASS: literal layouts, sixteen ordered guards, exact observations and whole refusal',
  ].freeze
  OUTPUT_FORMAT_EXPECTED_MUTANTS = {
    'MIC-OUTPUT-FORMAT-CLOSED-WIRE' => 'output_format_malformed_wire_is_not_an_ordinary_policy_rejection',
    'MIC-OUTPUT-FORMAT-FIRST-GUARD' => 'output_format_every_simultaneous_error_pair_preserves_first_guard',
    'MIC-OUTPUT-FORMAT-RATE-EXACT' => 'output_format_rates_use_numeric_equality_but_rejections_keep_original_bits',
    'MIC-OUTPUT-FORMAT-SIGNED-STATUS' => 'output_format_four_signed_statuses_preserve_negative_and_extreme_values',
    'MIC-OUTPUT-FORMAT-FULL-U32' => 'output_format_integer_fields_are_exact_not_masks_ranges_or_truncated_values',
    'MIC-OUTPUT-FORMAT-WHOLE-RESULT' => 'output_format_authoritative_verifier_rejects_corruption_of_every_result_field',
    'MIC-OUTPUT-FORMAT-C-PRODUCER' => 'output_format_actual_c_exports_correlate_success_rejection_and_refusal',
    'MIC-OUTPUT-FORMAT-C-VERIFIER' => 'output_format_actual_c_exports_correlate_success_rejection_and_refusal',
  }.freeze

  def enrollment_cases
    result = Gate::BELUGA_CORE_CARGO_SUITES.to_h { |suite| [suite, []] }
    Gate::BELUGA_CORE_QUALIFIED_PINNED.each do |id|
      suite, method = id.split('/', 2)
      result.fetch(suite) << method
    end
    result.transform_values { |ids| ids.sort }
  end

  def enrollment_header(suite)
    return "   Doc-tests beluga_core\n" if suite == 'doc'
    path = suite == 'lib' ? 'unittests src/lib.rs' : 'tests/' + suite + '.rs'
    binary = suite == 'lib' ? 'beluga_core' : suite
    "     Running #{path} (fixture/debug/deps/#{binary}-abcdef012345)\n"
  end

  def enrollment_discovery(cases = enrollment_cases)
    "    Finished `test` profile [unoptimized + debuginfo] target(s) in 0.01s\n" +
      cases.map do |suite, ids|
        enrollment_header(suite) + ids.map { |id| id + ": test\n" }.join +
          "#{ids.length} tests, 0 benchmarks\n"
      end.join
  end

  def enrollment_results(cases = enrollment_cases)
    "    Finished `test` profile [unoptimized + debuginfo] target(s) in 0.01s\n" +
      cases.map do |suite, ids|
        enrollment_header(suite) + "running #{ids.length} tests\n" +
          ids.map { |id| "test #{id} ... ok\n" }.join +
          "test result: ok. #{ids.length} passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s\n"
      end.join
  end

  def enrollment_qualified(cases = enrollment_cases)
    cases.flat_map { |suite, ids| ids.map { |id| suite + '/' + id } }.sort
  end

  def enrollment_rejects
    assert_raises(RuntimeError) { yield }
  end

  def enrollment_mutation_log(oracle, test, passed:, filtered: nil)
    owner = oracle.name.include?('Owner')
    filtered ||= owner ? 269 : (oracle == BelugaCoreMicrophoneOutputFormatMutationOracle ? 11 :
      (oracle == BelugaCoreHandoffSourceMutationOracle ? 10 : (oracle == BelugaCoreMicrophoneRetryMutationOracle ? 9 : 7)))
    path = if owner
      oracle == BelugaCoreOwnerPostAwaitMutationOracle ? oracle::TEST_PATHS.fetch(test) : oracle::TEST_PATH
    else
      oracle::TEST_PATH
    end
    suite = owner ? 'lib' : oracle::SUITE
    prefix = "    Finished `test` profile [unoptimized + debuginfo] target(s) in 0.01s\n" +
      enrollment_header(suite) + "running 1 test\ntest #{test} ... #{passed ? 'ok' : 'FAILED'}\n"
    footer = "test result: #{passed ? 'ok' : 'FAILED'}. #{passed ? 1 : 0} passed; #{passed ? 0 : 1} failed; 0 ignored; 0 measured; #{filtered} filtered out; finished in 0.00s\n"
    return prefix + footer if passed
    prefix + "\nfailures:\n---- #{test} stdout ----\n" +
      "thread '#{test}' (123) panicked at #{path}:1:1:\n" +
      "assertion `left == right` failed: reviewed inert fixture\n  left: 0\n right: 1\n" +
      "\nfailures:\n    #{test}\n\n" + footer +
      "error: test failed, to rerun pass `#{owner ? '--lib' : '--test ' + suite}`\n"
  end

  def test_release_enrollment_all_sources_are_exact_112_without_changing_68_prefix
    assert_equal 122, Gate::BELUGA_CORE_SOURCE_FILES.length
    assert_equal 122, Gate::BELUGA_CORE_SOURCE_FILES.uniq.length
    expected = %w[
      src/update_admission.rs tests/update_admission.rs
      src/update_sparkle_admission.rs tests/update_sparkle_admission.rs
      src/microphone_forwarding_evidence.rs tests/microphone_forwarding_evidence.rs
      src/microphone_forwarding_retry.rs tests/microphone_forwarding_retry.rs
      src/update_unarmed_completion.rs tests/update_unarmed_completion.rs
      src/update_abort.rs tests/update_abort.rs
      src/handoff_source_position.rs tests/handoff_source_position.rs
      src/microphone_input_lease.rs tests/microphone_input_lease.rs
      src/microphone_output_format.rs tests/microphone_output_format.rs
    ]
    expected.each { |relative| assert_includes Gate::BELUGA_CORE_SOURCE_FILES, relative }
    assert_equal 545, Gate::BELUGA_CORE_REVIEWED_CASE_SUITES.values.flatten.length
    assert_equal Gate::BELUGA_CORE_PINNED, Gate::BELUGA_CORE_REVIEWED_CASE_SUITES.values.flatten
  end

  def test_release_enrollment_cross_suite_equal_names_are_distinct_discovery_and_results
    expected = enrollment_qualified
    ids = %w[
      update_admission/wire_sizes_offsets_and_literal_constants_are_fixed
      update_sparkle_admission/wire_sizes_offsets_and_literal_constants_are_fixed
    ]
    ids.each { |id| assert_includes expected, id }
    assert_equal expected, Gate.beluga_core_inventory(enrollment_discovery)
    assert_equal expected, Gate.validate_beluga_core_rust(enrollment_results, expected)
  end

  def test_release_enrollment_same_suite_duplicate_discovery_is_never_accepted
    cases = enrollment_cases
    cases.fetch('update_admission') << cases.fetch('update_admission').first
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
  end

  def test_release_enrollment_same_suite_duplicate_results_are_never_accepted
    cases = enrollment_cases
    cases.fetch('update_admission') << cases.fetch('update_admission').first
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), enrollment_qualified) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results, enrollment_qualified + [enrollment_qualified.first]) }
  end

  def test_release_enrollment_unframed_unknown_and_mismatched_suite_records_are_refused
    discovery = enrollment_discovery
    results = enrollment_results
    method = Gate::BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('update_admission').first
    [method + ": test\n" + discovery, discovery + method + ": test\n",
     discovery.sub('tests/update_admission.rs', 'tests/foreign_fixture.rs'),
     discovery.sub('update_admission-abcdef012345', 'update_sparkle_admission-abcdef012345'),
     discovery.sub(enrollment_header('update_admission'), ''),
     discovery + enrollment_header('update_admission') + "0 tests, 0 benchmarks\n"].each do |text|
      enrollment_rejects { Gate.beluga_core_inventory(text) }
    end
    ["test #{method} ... ok\n" + results, results + "test #{method} ... ok\n",
     results.sub('tests/update_admission.rs', 'tests/foreign_fixture.rs'),
     results.sub(enrollment_header('update_admission'), '')].each do |text|
      enrollment_rejects { Gate.validate_beluga_core_rust(text, enrollment_qualified) }
    end
  end

  def test_release_enrollment_cross_suite_swap_cannot_borrow_critical_coverage
    cases = enrollment_cases
    left = cases.fetch('update_admission').find { |id| id.start_with?('all_512_') }
    right = cases.fetch('update_sparkle_admission').find { |id| id.start_with?('all_twelve_') }
    cases.fetch('update_admission').delete(left); cases.fetch('update_admission') << right
    cases.fetch('update_sparkle_admission').delete(right); cases.fetch('update_sparkle_admission') << left
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), enrollment_qualified) }
  end

  def test_release_enrollment_every_new_exact_rust_case_is_required_in_its_actual_suite
    assert_equal [10, 10, 8, 8, 8, 7], %w[microphone_forwarding_evidence microphone_forwarding_retry update_admission update_sparkle_admission update_unarmed_completion update_abort].map { |suite|
      Gate::BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch(suite).length
    }
    Gate::BELUGA_CORE_QUALIFIED_PINNED.drop(545).each do |id|
      cases = enrollment_cases
      suite, method = id.split('/', 2)
      cases.fetch(suite).delete(method)
      enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
    end
  end

  def test_release_enrollment_each_suite_count_footer_and_non_skipping_boundary_is_exact
    discovery = enrollment_discovery
    results = enrollment_results
    [discovery.sub("8 tests, 0 benchmarks", "9 tests, 0 benchmarks"),
     discovery.sub("8 tests, 0 benchmarks", "8 tests, 1 benchmarks"),
     discovery.sub("0 tests, 0 benchmarks\n", ""),
     discovery + "0 tests, 0 benchmarks\n"].each do |text|
      enrollment_rejects { Gate.beluga_core_inventory(text) }
    end
    [results.sub("running 8 tests", "running 9 tests"),
     results.sub("8 passed; 0 failed", "7 passed; 0 failed"),
     results.sub("0 ignored", "1 ignored"),
     results.sub("0 filtered out", "1 filtered out"),
     results.sub(" ... ok", " ... ignored"),
     results.sub(" ... ok", " ... FAILED"),
     results.sub("test result: ok. 0 passed", "test result: FAILED. 0 passed"),
     results + "running 0 tests\n"].each do |text|
      enrollment_rejects { Gate.validate_beluga_core_rust(text, enrollment_qualified) }
    end
  end

  def test_release_enrollment_compiled_boundary_utf8_and_complete_suite_census_are_required
    [:discovery, :results].each do |mode|
      text = mode == :discovery ? enrollment_discovery : enrollment_results
      compiled = text.lines.first
      body = text.delete_prefix(compiled)
      first_suite = body.lines.first
      [text.delete_prefix(compiled), compiled + text,
       body + compiled,
       body.sub(first_suite, first_suite + compiled),
       text.sub('Finished', 'Skipped Finished'), text.b + "\xFF".b,
       text.sub(enrollment_header('doc'), '   Doc-tests foreign_crate' + "\n")].each do |bad|
        enrollment_rejects { Gate.beluga_core_rust_frames(bad, mode) }
      end
    end
    assert_equal 40, Gate::BELUGA_CORE_CARGO_SUITES.length
  end

  def test_release_enrollment_added_controls_map_exactly_and_do_not_change_474_prefix
    assert_equal 587, Gate::BELUGA_CORE_MUTANT_TESTS.length
    assert_equal 587, Gate::BELUGA_CORE_MUTANTS.uniq.length
    assert_equal [6, 4, 4, 8, 18, 7, 17, 17, 16, 8, 8], Gate::BELUGA_CORE_ADDED_MUTATION_ORACLES.map { |mapping, _| mapping.length }
    assert_equal Gate::BELUGA_CORE_MUTANT_TESTS.to_a.drop(474), Gate::BELUGA_CORE_ADDED_MUTANT_TESTS.to_a
    Gate::BELUGA_CORE_ADDED_MUTATION_ORACLES.each do |mapping, oracle|
      assert_equal mapping.to_a, oracle::CONTROLS.map { |control| [control.first, control.last] }
      assert_equal mapping.keys, oracle::NAMES
      assert_equal mapping.values.uniq, oracle::TESTS
    end
  end

  def test_release_enrollment_all_81_named_rejections_and_exact_restorations_retain_strict_decoders
    Gate::BELUGA_CORE_ADDED_MUTATION_ORACLES.each do |mapping, oracle|
      mapping.each_value do |test|
        [false, true].each do |passed|
          log = enrollment_mutation_log(oracle, test, passed: passed)
          assert_nil oracle.validate!(log, test, passed: passed,
            exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false)
          [log.sub('Finished', 'could not compile Finished'),
           log.sub("running 1 test", "running 0 tests"),
           log.sub(test, test + '_foreign'),
           log.sub('0 ignored', '1 ignored'),
           log + "test #{test} ... ok\n"].each do |bad|
            enrollment_rejects { oracle.validate!(bad, test, passed: passed,
              exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false) }
          end
        end
      end
    end
  end

  def test_release_enrollment_whole_mutation_frames_require_every_added_restoration
    log = core_mutations_log
    assert_nil Gate.validate_beluga_core_mutations(log)
    Gate::BELUGA_CORE_ADDED_MUTATION_ORACLES.each do |mapping, _|
      name = mapping.keys.first
      marker = "BELUGA_CORE_MUTANT_RESTORED #{name} baseline-passed\n"
      enrollment_rejects { Gate.validate_beluga_core_mutations(log.sub(marker, '')) }
      enrollment_rejects { Gate.validate_beluga_core_mutations(log.sub(marker, marker + marker)) }
    end
  end

  def test_release_enrollment_owner269_is_exact_and_old259_or_arbitrary_count_is_not_accepted
    Gate::BELUGA_CORE_ADDED_MUTATION_ORACLES.first(5).each do |mapping, oracle|
      test = mapping.values.first
      [false, true].each do |passed|
        assert_nil oracle.validate!(enrollment_mutation_log(oracle, test, passed: passed),
          test, passed: passed, exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false)
        [0, 259, 268, 270].each do |filtered|
          enrollment_rejects { oracle.validate!(enrollment_mutation_log(oracle, test,
            passed: passed, filtered: filtered), test, passed: passed,
            exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false) }
        end
      end
    end
  end

  def test_release_enrollment_24_added_runtime_markers_keep_exact_full_order_and_old_prefix
    assert_equal 88, Gate::BELUGA_CORE_RUNTIME_MARKERS.length
    assert_equal 88, Gate::BELUGA_CORE_RUNTIME_MARKER_ORDER.length
    assert_equal 88, Gate::BELUGA_CORE_RUNTIME_MARKER_ORDER.uniq.length
    log = core_link_log
    assert_nil Gate.validate_beluga_core_link(log)
    Gate::BELUGA_CORE_RUNTIME_MARKERS.drop(54).each do |marker|
      enrollment_rejects { Gate.validate_beluga_core_link(log.sub(marker + "\n", '')) }
      enrollment_rejects { Gate.validate_beluga_core_link(log.sub(marker + "\n", (marker + "\n") * 2)) }
    end
    first, last = Gate::BELUGA_CORE_RUNTIME_MARKER_ORDER.values_at(27, 39)
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(first, '__swap__').sub(last, first).sub('__swap__', last)) }
  end

  def test_release_enrollment_new_native_classes_and_source_cases_are_not_silently_filtered
    assert_equal [8, 10, 4, 4, 7, 62, 4, 9, 4].sort,
      Gate::UPDATER_MICROPHONE_NATIVE_PINNED.values.map(&:length).sort
    expected = Gate.updater_microphone_native_required_map
    assert_equal [9, 10, 4, 4, 7, 62, 4, 9, 4].sort, expected.values.map(&:length).sort
    assert_equal expected.transform_values(&:sort), Gate.updater_microphone_native_inventory(@root, @mac_methods.join("\n"))
    expected.each do |suite, methods|
      assert_includes Gate::MAC_CLASSES, suite
      methods.each do |id|
        enrollment_rejects { Gate.updater_microphone_native_inventory(@root, (@mac_methods - [id]).join("\n")) }
      end
    end
    enrollment_rejects { Gate.updater_microphone_native_inventory(@root, (@mac_methods + [expected.values.first.first]).join("\n")) }
  end

  def test_release_enrollment_four_producer_modules_and_all_23_named_cases_are_mandatory
    expected = Gate.mac_producer_inventory(@root)
    names = %w[
      artifact-owner-symbol-tests.rb microphone-retry-mutation-tests.rb
      update-admission-mutation-tests.rb update-sparkle-admission-mutation-tests.rb
    ]
    names.each do |name|
      path = File.join(@root, 'macOS/scripts', name)
      prior = File.binread(path)
      File.unlink(path)
      assert_raises(Errno::ENOENT) { Gate.mac_producer_inventory(@root) }
      write(path, prior)
    end
    Gate::MAC_PRODUCER_PINNED.drop(39).each do |id|
      assert_includes expected, id
      removed = expected - [id]
      source = File.join(@root, 'macOS/scripts/verify-beluga-mac-client-tests.rb')
      prior = File.binread(source)
      write(source, removed.map { |method| "def #{method}\nend\n" }.join)
      enrollment_rejects { Gate.mac_producer_inventory(@root) }
      write(source, prior)
    end
  end

  def test_release_enrollment_combined_owner269_source_has_all_eight_exact_mutation_pins
    relative = 'shared/Rust/BelugaCore/scripts/mutation-tests.rb'
    expected = '9cafeff860bd35c6090323679ee0b9ca0ec9a2cba2c65c82d2bb2eda986ac6cd'
    groups = [
      Gate::PACKET_SEND_QUEUE_SOURCE_SHA256, Gate::RTT_EVIDENCE_SOURCE_SHA256,
      Gate::TIER_DEMAND_SOURCE_SHA256, Gate::MEDIA_COMMAND_GATE_SOURCE_SHA256,
      Gate::SCREEN_SUSPENSION_SOURCE_SHA256, Gate::PHONE_CATALOG_SOURCE_SHA256,
      Gate::RUNTIME_CATALOG_SOURCE_SHA256, Gate::SCREEN_LIVENESS_SOURCE_SHA256
    ]
    assert_equal 8, groups.length
    groups.each { |pins| assert_equal expected, pins.fetch(relative) }
    path = File.join(@root, relative)
    assert_equal expected, Gate.sha(path)
    prior = File.binread(path)
    write(path, prior + "\n# inert exact-byte corruption\n")
    refute_equal expected, Gate.sha(path)
    write(path, prior)
    assert_equal expected, Gate.sha(path)
  end


  # New epoch fixtures are additive: predecessor methods retain their names.
  def test_unarmed_release_enrollment_exact_literal_cases_and_frozen_predecessor_prefixes
    expected_rust = %w[
      wire_layout_offsets_and_closed_literal_values_are_fixed
      all_1572864_valid_carriers_match_the_literal_original_branch_priority
      each_native_reason_path_and_its_blocking_presence_facts_are_exact
      original_found_item_and_candidate_attempt_omissions_are_not_strengthened
      unsupported_abi_failure_kind_and_every_unknown_flag_fail_closed
      every_copied_result_field_requires_whole_request_correlation
      coherent_cross_request_reasons_cannot_mint_a_different_completion
      copied_inputs_and_results_have_no_retained_owner_or_effect_state
    ]
    expected_swift = %w[
      CaptureServerTests.BelugaRustUnarmedCompletionTests/testExactLayoutsAndAllSixLiteralReasonsThroughActualCAndPacking
      CaptureServerTests.BelugaRustUnarmedCompletionTests/testEveryBitPackingAndOriginalCandidateAndFoundItemOmissions
      CaptureServerTests.BelugaRustUnarmedCompletionTests/testUnsupportedABISeparateFailureKindAndEveryUnknownFlagRefuse
      CaptureServerTests.BelugaRustUnarmedCompletionTests/testWholeResultAndCoherentCrossRequestReasonsCannotManufactureCompletion
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleEarlierEligibilityFailuresSkipSDKGetterAndAuthority
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleIdleGetterPrecedesInitialAuthorityAndDenialSkipsLaterQueries
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshAcknowledgedAndAbortedFailure
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshCancellationAfterPresentation
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshDeclineAndExactNativePayload
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleInitialAuthorityReentrySelectsFreshNoUpdateIdentity
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleNestedObservationClearsOuterProofBeforeRetirement
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleSDKGetterReentryCreatesFreshNoUpdateBeforeAuthority
      CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests/testFinishedCycleSuccessfulPairHasExactSDKAuthorityAndRetirementOrder
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerUnarmedProducerABIControlHasAttributedLeaseWitness
      CaptureServerTests.BelugaUpdateSparkleSessionTests/testActualPrivateBrokerUnarmedVerifierTwoControlHasAttributedLeaseWitness
    ]
    assert_equal expected_rust, Gate::BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('update_unarmed_completion')
    assert_equal expected_swift, Gate::MAC_PINNED.first(502).drop(487)
    assert_equal ['CaptureServerTests.BelugaRustUnarmedCompletionTests',
                  'CaptureServerTests.BelugaUpdateSparkleFinishedCycleTests'], Gate::MAC_CLASSES.first(63).drop(61)
    assert_equal %w[src/update_unarmed_completion.rs tests/update_unarmed_completion.rs], Gate::BELUGA_CORE_SOURCE_FILES.first(114).drop(112)
    assert_equal expected_rust.map { |id| 'update_unarmed_completion/' + id }, Gate::BELUGA_CORE_QUALIFIED_PINNED.first(625).drop(617)
    old_native = Gate::UPDATER_MICROPHONE_NATIVE_PINNED.reject { |klass, _| klass == 'CaptureServerTests.BelugaRustUpdateAbortTests' }.transform_values { |ids|
      ids.first(ids.first.start_with?('CaptureServerTests.BelugaUpdateSparkleSessionTests/') ? 57 : ids.length)
    }
    assert_equal [114, 625, 36, 63, 502, 103],
      [Gate::BELUGA_CORE_SOURCE_FILES.first(114).length, Gate::BELUGA_CORE_QUALIFIED_PINNED.first(625).length,
       Gate::BELUGA_CORE_CARGO_SUITES.reject { |suite| %w[update_abort handoff_source_position microphone_input_lease microphone_output_format].include?(suite) }.length, Gate::MAC_CLASSES.first(63).length,
       Gate::MAC_PINNED.first(502).length, old_native.values.flatten.length]
    frozen = [
      [Gate::BELUGA_CORE_SOURCE_FILES.first(112), 'a8a2fb8744bf917bac8283a80254f54aba1b348b13a5ed5fa02441710cb88e3d'],
      [Gate::MAC_CLASSES.first(61), 'd53b9bc0a9bc62912109a51d19e2f2005089acff0b6b7c07ff7661ba4aee4b2e'],
      [Gate::MAC_PINNED.first(487), 'b234476fdefa9a99f6d7d39a845ee33309b25d9ba8d5e7ed6c3f0d4d58c2dd3b'],
      [Gate::BELUGA_CORE_PINNED, '9a140d7960d37457e3b383b8231fdbd27de8e339b653e8d6090b141ff5afb61e'],
      [Gate::BELUGA_CORE_QUALIFIED_PINNED.first(617), 'dc7ee619ee8a6b3f864ba24f2e1298499b1f6b02989e9453d93b42dc6f5fd0a4']
    ]
    frozen.each { |ids, sha| assert_equal sha, Digest::SHA256.hexdigest(JSON.generate(ids) + "\n") }
  end

  def test_unarmed_release_enrollment_each_new_rust_case_and_compiled_cohort_refuses_omission_duplicate_or_foreign
    expected = enrollment_qualified
    suite = 'update_unarmed_completion'
    Gate::BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch(suite).each do |method|
      [lambda { |cases| cases.fetch(suite).delete(method) },
       lambda { |cases| cases.fetch(suite) << method },
       lambda { |cases| cases.fetch(suite).map! { |id| id == method ? id + '_foreign' : id } },
       lambda { |cases| cases.fetch(suite).delete(method); cases.fetch('update_admission') << method }].each do |mutate|
        cases = enrollment_cases
        mutate.call(cases)
        enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
        enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
      end
    end
    cases = enrollment_cases
    cases.delete(suite)
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery.sub('tests/update_unarmed_completion.rs', 'tests/foreign_unarmed.rs')) }
  end

  def test_unarmed_release_enrollment_each_new_rust_source_and_closed_source_manifest_is_required
    paths = %w[src/update_unarmed_completion.rs tests/update_unarmed_completion.rs]
    paths.each do |relative|
      path = File.join(core_crate, relative)
      prior = File.binread(path)
      begin
        File.unlink(path)
        enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
      ensure
        write(path, prior)
      end
    end
    manifest = File.join(core_crate, 'SOURCE_MANIFEST.sha256')
    prior = File.binread(manifest)
    record = prior.lines.find { |line| line.end_with?('  src/update_unarmed_completion.rs' + "\n") }
    refute_nil record
    begin
      write(manifest, prior + record)
      enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
    ensure
      write(manifest, prior)
    end
    foreign = File.join(core_crate, 'tests/unarmed_foreign_fixture.rs')
    begin
      write(foreign, 'foreign source fixture')
      enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
    ensure
      File.unlink(foreign) if File.exist?(foreign)
    end
    assert_nil Gate.validate_beluga_core_artifacts(@root)
  end

  def test_unarmed_release_enrollment_markers_keep_two_language_lanes_and_refuse_missing_duplicate_foreign_or_misorder
    new_markers = [
      'BelugaCore C unarmed completion ABI PASS: copied layouts, six reasons, whole correlation and refusal',
      'BelugaCore Swift unarmed completion ABI PASS: copied layouts, six reasons, whole correlation and refusal'
    ]
    assert_equal new_markers, Gate::BELUGA_CORE_RUNTIME_MARKERS.first(80).drop(78)
    old = Gate::BELUGA_CORE_RUNTIME_MARKERS.first(78)
    assert_equal 'c22b49abf5f186b7dbfa1192b6fcc33d0f8751da80c15d5b3a3154f456e79f15',
      Digest::SHA256.hexdigest(JSON.generate(old) + "\n")
    unarmed_order = Gate::BELUGA_CORE_RUNTIME_MARKER_ORDER.select { |line| Gate::BELUGA_CORE_RUNTIME_MARKERS.first(80).include?(line) }
    old_order = unarmed_order.reject { |line| new_markers.include?(line) }
    assert_equal '22ec08828bb84234119033dcdb123cf3270d0eb1e80519fe12c79b9e72b4e406',
      Digest::SHA256.hexdigest(JSON.generate(old_order) + "\n")
    assert_equal new_markers.first, unarmed_order.fetch(39)
    assert_equal new_markers.last, unarmed_order.fetch(79)
    assert unarmed_order.first(40).all? { |line| line.start_with?('BelugaCore C ') }
    assert unarmed_order.drop(40).all? { |line| line.start_with?('BelugaCore Swift ') }
    log = core_link_log
    new_markers.each do |marker|
      enrollment_rejects { Gate.validate_beluga_core_link(log.sub(marker + "\n", '')) }
      enrollment_rejects { Gate.validate_beluga_core_link(log.sub(marker + "\n", (marker + "\n") * 2)) }
      enrollment_rejects { Gate.validate_beluga_core_link(log.sub(marker, marker + '_foreign')) }
    end
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(new_markers.first, '__unarmed_swap__').sub(new_markers.last, new_markers.first).sub('__unarmed_swap__', new_markers.last)) }
    first_swift = unarmed_order.fetch(40)
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(new_markers.first + "\n", '').sub(first_swift + "\n", first_swift + "\n" + new_markers.first + "\n")) }
    assert_nil Gate.validate_beluga_core_link(log)
  end

  def test_unarmed_release_enrollment_each_new_swift_case_refuses_missing_duplicate_foreign_or_wrong_class
    new_cases = Gate::MAC_PINNED.first(502).drop(487)
    assert_equal 15, new_cases.length
    original = @mac_methods.join("\n")
    new_cases.each do |id|
      [(@mac_methods - [id]), (@mac_methods + [id]),
       @mac_methods.map { |other| other == id ? id + '_foreign' : other },
       @mac_methods.map { |other| other == id ? id.sub('CaptureServerTests.', 'ForeignTests.') : other }].each do |ids|
        enrollment_rejects { Gate.mac_inventory(ids.join("\n")) }
        enrollment_rejects { Gate.updater_microphone_native_inventory(@root, ids.join("\n")) }
      end
    end
    assert_equal Gate.updater_microphone_native_required_map.transform_values(&:sort),
      Gate.updater_microphone_native_inventory(@root, original)
  end

  def test_unarmed_release_enrollment_every_exact_source_companion_and_same_file_probe_bytes_are_required
    expected = {
      'shared/Rust/BelugaCore/src/update_unarmed_completion.rs' => 'ef616de13b1312a0869f8ca34a953618c5dd9ef9daf0d974562b1c177fa57d79',
      'shared/Rust/BelugaCore/tests/update_unarmed_completion.rs' => 'acead2c85360be7548eb4963384e7c0bfb864ec1c5367e75a59aefd3b545cd2e',
      'macOS/Sources/BelugaUpdateCore/BelugaRustUnarmedCompletion.swift' => 'c43229b13a5fccc5ab1c9a200931a1f68be61003bd9d8664694b96fdc335e352',
      'macOS/Sources/BelugaUpdateDriver/BelugaUpdateSparkleSession.swift' => 'b80412aeed0d4736107ccdb108ea737ef19c647ed3bac83c087a3ba909de0536',
      'macOS/Tests/CaptureServerTests/BelugaRustUnarmedCompletionTests.swift' => '257315325ead8080a3eb39836af14f60906f00f22f446176eb8c17b22b673501',
      'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleFinishedCycleTests.swift' => '20eef056379b91d6f45fac78346e78c8f80ca0a9bd4334b9fb802017dfe136dc',
      'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleSessionTests.swift' => 'e85b590d21b525d95515de65c67bd3095ce01c660c0c8526e3f0ef4868fe9d73',
    }
    assert_equal expected, Gate::UNARMED_COMPLETION_SOURCE_SHA256
    expected.each do |relative, sha|
      path = File.join(@root, relative)
      prior = File.binread(path)
      assert_equal sha, Gate.sha(path)
      begin
        File.unlink(path)
        assert_raises(Errno::ENOENT) { Gate.updater_microphone_native_source_inventory(@root) }
        write(path, prior + "\n// inert source-byte drift\n")
        enrollment_rejects { Gate.updater_microphone_native_source_inventory(@root) }
      ensure
        write(path, prior)
      end
    end
    session = File.join(@root, 'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleSessionTests.swift')
    prior = File.binread(session)
    probe = 'testActualPrivateBrokerUnarmedProducerABIControlHasAttributedLeaseWitness'
    refute_equal prior, prior.sub(probe, probe + 'Foreign')
    begin
      write(session, prior.sub(probe, probe + 'Foreign'))
      enrollment_rejects { Gate.updater_microphone_native_source_inventory(@root) }
    ensure
      write(session, prior)
    end
    assert_equal Gate.updater_microphone_native_required_map.transform_values(&:sort),
      Gate.updater_microphone_native_source_inventory(@root)
  end

  def test_unarmed_release_enrollment_only_reviewed_shared_epoch_and_session_pin_change
    expected = {
      'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
      'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
      'shared/Rust/BelugaCore/scripts/artifact_support.rb' => 'a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7',
      'shared/Rust/BelugaCore/tests/c_abi_smoke.c' => '6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37',
      'shared/Rust/BelugaCore/tests/swift_import_smoke.swift' => '733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1',
    }
    groups = [
      Gate::OUTPUT_DIMENSIONS_SOURCE_SHA256, Gate::PACKET_SEND_QUEUE_SOURCE_SHA256,
      Gate::RTT_EVIDENCE_SOURCE_SHA256, Gate::TIER_DEMAND_SOURCE_SHA256,
      Gate::MEDIA_COMMAND_GATE_SOURCE_SHA256, Gate::SCREEN_SUSPENSION_SOURCE_SHA256,
      Gate::PHONE_CATALOG_SOURCE_SHA256, Gate::RUNTIME_CATALOG_SOURCE_SHA256,
      Gate::ICE_RECOVERY_SOURCE_SHA256, Gate::SCREEN_LIVENESS_SOURCE_SHA256
    ]
    records = []
    groups.each_with_index do |pins, index|
      paths = [0, 8].include?(index) ? expected.keys.first(2) : expected.keys
      paths.each { |relative| assert_equal expected.fetch(relative), pins.fetch(relative); records << relative }
    end
    assert_equal 44, records.length
    assert_equal [10, 10, 8, 8, 8], expected.keys.map { |relative| records.count(relative) }
    session = 'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleSessionTests.swift'
    assert_equal 'e85b590d21b525d95515de65c67bd3095ce01c660c0c8526e3f0ef4868fe9d73',
      Gate::UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256.fetch(session)
    assert_equal 555, Gate::BELUGA_CORE_MUTANT_TESTS.to_a.first(555).length
    assert_equal 43, Gate::PHASES.length
    assert_equal 22, Gate::SIMULATOR_SKIPS.length
  end

  # Seven additive parser/source fixtures; none executes the SDK, C producer or host.
  def test_abort_release_enrollment_exact_literal_cases_and_preserved_predecessor_vectors
    assert_equal ABORT_EXPECTED_RUST, Gate::BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('update_abort')
    assert_equal ABORT_EXPECTED_SWIFT, Gate::MAC_PINNED.first(511).drop(502)
    assert_equal ['CaptureServerTests.BelugaRustUpdateAbortTests'], Gate::MAC_CLASSES.first(64).drop(63)
    assert_equal %w[src/update_abort.rs tests/update_abort.rs], Gate::BELUGA_CORE_SOURCE_FILES.first(116).drop(114)
    assert_equal ABORT_EXPECTED_RUST.map { |id| 'update_abort/' + id }, Gate::BELUGA_CORE_QUALIFIED_PINNED.first(632).drop(625)
    assert_equal [122, 663, 40, 68, 565, 112, 62, 4],
      [Gate::BELUGA_CORE_SOURCE_FILES.length, Gate::BELUGA_CORE_QUALIFIED_PINNED.length,
       Gate::BELUGA_CORE_CARGO_SUITES.length, Gate::MAC_CLASSES.length,
       Gate::MAC_PINNED.length, Gate::UPDATER_MICROPHONE_NATIVE_PINNED.values.flatten.length,
       Gate::UPDATER_MICROPHONE_NATIVE_PINNED.fetch('CaptureServerTests.BelugaUpdateSparkleSessionTests').length,
       Gate::UPDATER_MICROPHONE_NATIVE_PINNED.fetch('CaptureServerTests.BelugaRustUpdateAbortTests').length]
    frozen = [
      [Gate::BELUGA_CORE_SOURCE_FILES.first(114), 'eff71090e521afd5f853589c3c8a21a10c8281d2842ae3a1d10dab5cdc3d1f7f'],
      [Gate::MAC_CLASSES.first(63), '32db6e7c65ec041a10bd3a9645052a39e222be59d8fc1b8377f1a13b70fc1026'],
      [Gate::MAC_PINNED.first(502), 'bce14665402abfd4c55666e0b40699ff214ab23c50c056ef384a3bbc66b7fbe2'],
      [Gate::BELUGA_CORE_QUALIFIED_PINNED.first(625), '651ec00dc289a43b8cbb04a57c32f5db830975983d4d088661fec6a48e972f97'],
      [Gate::BELUGA_CORE_RUNTIME_MARKERS.first(80), '0a6b58de5f84c4529e8f4544a36c4f9cf35d852b436b44ce5859e14730db46fb']
    ]
    frozen.each { |ids, sha| assert_equal sha, Digest::SHA256.hexdigest(JSON.generate(ids) + "\n") }
    assert_equal [545, 555, 43, 22], [Gate::BELUGA_CORE_PINNED.length,
      Gate::BELUGA_CORE_MUTANT_TESTS.to_a.first(555).length, Gate::PHASES.length, Gate::SIMULATOR_SKIPS.length]
  end

  def test_abort_release_enrollment_each_rust_case_and_new_suite_refuse_missing_duplicate_failed_ignored_or_foreign
    expected = enrollment_qualified
    suite = 'update_abort'
    ABORT_EXPECTED_RUST.each do |method|
      [lambda { |cases| cases.fetch(suite).delete(method) },
       lambda { |cases| cases.fetch(suite) << method },
       lambda { |cases| cases.fetch(suite).map! { |id| id == method ? id + '_foreign' : id } },
       lambda { |cases| cases.fetch(suite).delete(method); cases.fetch('update_admission') << method }].each do |mutate|
        cases = enrollment_cases
        mutate.call(cases)
        enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
        enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
      end
      %w[FAILED ignored].each do |status|
        enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results.sub("test #{method} ... ok", "test #{method} ... #{status}"), expected) }
      end
    end
    cases = enrollment_cases
    cases.delete(suite)
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery.sub('update_abort-abcdef012345', 'update_admission-abcdef012345')) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results.sub(enrollment_header(suite), ''), expected) }
    assert_equal expected, Gate.beluga_core_inventory(enrollment_discovery)
    assert_equal expected, Gate.validate_beluga_core_rust(enrollment_results, expected)
  end

  def test_abort_release_enrollment_source_pair_and_closed_manifest_cannot_be_omitted_or_rehashed
    %w[src/update_abort.rs tests/update_abort.rs].each do |relative|
      path = File.join(core_crate, relative)
      prior = File.binread(path)
      begin
        File.unlink(path)
        enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
      ensure
        write(path, prior)
      end
    end
    manifest = File.join(core_crate, 'SOURCE_MANIFEST.sha256')
    prior = File.binread(manifest)
    record = prior.lines.find { |line| line.end_with?('  src/update_abort.rs' + "\n") }
    refute_nil record
    begin
      write(manifest, prior + record)
      enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
    ensure
      write(manifest, prior)
    end
    foreign = File.join(core_crate, 'tests/abort_foreign_fixture.rs')
    begin
      write(foreign, 'foreign source fixture')
      refresh_core_source_manifest(publish: false)
      enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
    ensure
      File.unlink(foreign) if File.exist?(foreign)
      write(manifest, prior)
    end
    assert_nil Gate.validate_beluga_core_artifacts(@root)
  end

  def test_abort_release_enrollment_two_markers_preserve_entire_old_language_order_and_refuse_forgery
    markers = [
      'BelugaCore C abort classifier ABI PASS: copied layouts, 64 carriers, whole correlation and refusal',
      'BelugaCore Swift abort classifier ABI PASS: copied layouts, 64 carriers, whole correlation and refusal'
    ]
    assert_equal markers, Gate::BELUGA_CORE_RUNTIME_MARKERS.first(82).drop(80)
    order = Gate::BELUGA_CORE_RUNTIME_MARKER_ORDER.select { |line| Gate::BELUGA_CORE_RUNTIME_MARKERS.first(82).include?(line) }
    assert_equal 'de16854ffd8b1e5ccae75fec2dc2ed914c93be88ba55c26fb62978001f7b5e7b',
      Digest::SHA256.hexdigest(JSON.generate(order.reject { |line| markers.include?(line) }) + "\n")
    assert_equal [82, 82], [order.length, order.uniq.length]
    assert_equal markers.first, order.fetch(40)
    assert_equal markers.last, order.fetch(81)
    assert order.first(41).all? { |line| line.start_with?('BelugaCore C ') }
    assert order.drop(41).all? { |line| line.start_with?('BelugaCore Swift ') }
    log = core_link_log
    markers.each do |marker|
      [log.sub(marker + "\n", ''), log.sub(marker + "\n", (marker + "\n") * 2),
       log.sub(marker, marker + '_foreign')].each { |bad| enrollment_rejects { Gate.validate_beluga_core_link(bad) } }
    end
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(markers.first, '__abort_swap__').sub(markers.last, markers.first).sub('__abort_swap__', markers.last)) }
    first_swift = order.fetch(41)
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(markers.first + "\n", '').sub(first_swift + "\n", first_swift + "\n" + markers.first + "\n")) }
    assert_nil Gate.validate_beluga_core_link(log)
  end

  def test_abort_release_enrollment_each_swift_case_cannot_be_omitted_duplicated_failed_skipped_or_borrowed
    ABORT_EXPECTED_SWIFT.each do |id|
      [(@mac_methods - [id]), (@mac_methods + [id]),
       @mac_methods.map { |other| other == id ? id + '_foreign' : other },
       @mac_methods.map { |other| other == id ? id.sub('CaptureServerTests.', 'ForeignTests.') : other }].each do |ids|
        enrollment_rejects { Gate.mac_inventory(ids.join("\n")) }
        enrollment_rejects { Gate.updater_microphone_native_inventory(@root, ids.join("\n")) }
      end
      klass, name = id.split('/')
      %w[failed skipped].each do |status|
        bad = mac_log.sub("Test Case '-[#{klass} #{name}]' passed", "Test Case '-[#{klass} #{name}]' #{status}")
        enrollment_rejects { Gate.validate_mac_log(bad, @mac_methods) }
      end
      enrollment_rejects { Gate.validate_mac_log(mac_log(@mac_methods - [id]), @mac_methods) }
      enrollment_rejects { Gate.validate_mac_log(mac_log(@mac_methods + [id]), @mac_methods) }
    end
    assert_equal @mac_methods, Gate.validate_mac_log(mac_log, @mac_methods)
    assert_equal Gate.updater_microphone_native_required_map.transform_values(&:sort),
      Gate.updater_microphone_native_inventory(@root, @mac_methods.join("\n"))
  end

  def test_abort_release_enrollment_exact_companions_and_authored_native_order_are_required
    expected = {
      'shared/Rust/BelugaCore/src/update_abort.rs' => 'b8d3ff35dba36ecf41ea77d5b8821f4a8052e22b25010a3cbeec8a994d71820b',
      'shared/Rust/BelugaCore/tests/update_abort.rs' => 'f4229d63e85394c0330c770fb12ca498f80c4fb3354f4c50608df6378dfff145',
      'macOS/Sources/BelugaUpdateCore/BelugaRustUpdateAbort.swift' => '145463a875106b9cf526270ad811fa3210fcfd77c7620b062dd57c690bf168e2',
      'macOS/Sources/BelugaUpdateDriver/BelugaUpdateSparkleSession.swift' => 'b80412aeed0d4736107ccdb108ea737ef19c647ed3bac83c087a3ba909de0536',
      'macOS/Tests/CaptureServerTests/BelugaRustUpdateAbortTests.swift' => '0f859f032d41e3f1eacc3e2f79b5b131a3da8923598fd546f3fcb6916c0da0f2',
      'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleSessionTests.swift' => 'e85b590d21b525d95515de65c67bd3095ce01c660c0c8526e3f0ef4868fe9d73',
    }
    assert_equal expected, Gate::ABORT_CLASSIFIER_SOURCE_SHA256
    expected.each do |relative, sha|
      path = File.join(@root, relative)
      prior = File.binread(path)
      assert_equal sha, Gate.sha(path)
      begin
        File.unlink(path)
        assert_raises(Errno::ENOENT) { Gate.updater_microphone_native_source_inventory(@root) }
        write(path, prior + "\n// inert abort source-byte drift\n")
        enrollment_rejects { Gate.updater_microphone_native_source_inventory(@root) }
      ensure
        write(path, prior)
      end
    end
    wrapper_class = 'CaptureServerTests.BelugaRustUpdateAbortTests'
    assert_equal ABORT_EXPECTED_SWIFT.first(4), Gate::UPDATER_MICROPHONE_NATIVE_PINNED.fetch(wrapper_class)
    assert_equal ABORT_EXPECTED_SWIFT.drop(4), Gate::UPDATER_MICROPHONE_NATIVE_PINNED.fetch('CaptureServerTests.BelugaUpdateSparkleSessionTests').drop(57)
    relative = Gate::UPDATER_MICROPHONE_NATIVE_FILES.fetch(wrapper_class)
    path = File.join(@root, relative)
    prior = File.binread(path)
    first, second = ABORT_EXPECTED_SWIFT.first(2).map { |id| id.split('/').last }
    changed = prior.sub(first, '__abort_order_swap__').sub(second, first).sub('__abort_order_swap__', second)
    refute_equal prior, changed
    names = [:ABORT_CLASSIFIER_SOURCE_SHA256, :UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256]
    old_pins = names.map { |name| [name, Gate.const_get(name)] }.to_h
    begin
      write(path, changed)
      names.each do |name|
        Gate.send(:remove_const, name)
        Gate.const_set(name, old_pins.fetch(name).merge(relative => Digest::SHA256.hexdigest(changed)).freeze)
      end
      # Even a fixture-only reseal cannot change authored case order.
      enrollment_rejects { Gate.updater_microphone_native_source_inventory(@root) }
    ensure
      names.each { |name| Gate.send(:remove_const, name); Gate.const_set(name, old_pins.fetch(name)) }
      write(path, prior)
    end
    assert_equal Gate.updater_microphone_native_required_map.transform_values(&:sort), Gate.updater_microphone_native_source_inventory(@root)
  end

  def test_abort_release_enrollment_only_reviewed_shared_epoch_and_adapter_prefix_change
    expected = {
      'shared/Rust/BelugaCore/src/lib.rs' => '5a4db763fdef546ccdf9de324256f8b49c4ad9932e664432a93830ec46d55e2d',
      'shared/Rust/BelugaCore/include/beluga_core.h' => '2ea355f72241c8c62d0eb53b5d342784172637a305ffa3570b290814782d2dcd',
      'shared/Rust/BelugaCore/scripts/artifact_support.rb' => 'a39308cec492ff541f33bddbb3e6332400f33aabf37498e350db97684c524cb7',
      'shared/Rust/BelugaCore/tests/c_abi_smoke.c' => '6c2e4b992f8ff15edcacdb4343e8e42a8867a10201710f904dcd1f9cf38dea37',
      'shared/Rust/BelugaCore/tests/swift_import_smoke.swift' => '733731db3cfd6bd7a3114b9edfc474e5df32d5a18acc053a6cf61b808fc887b1',
    }
    groups = [Gate::OUTPUT_DIMENSIONS_SOURCE_SHA256, Gate::PACKET_SEND_QUEUE_SOURCE_SHA256,
      Gate::RTT_EVIDENCE_SOURCE_SHA256, Gate::TIER_DEMAND_SOURCE_SHA256,
      Gate::MEDIA_COMMAND_GATE_SOURCE_SHA256, Gate::SCREEN_SUSPENSION_SOURCE_SHA256,
      Gate::PHONE_CATALOG_SOURCE_SHA256, Gate::RUNTIME_CATALOG_SOURCE_SHA256,
      Gate::ICE_RECOVERY_SOURCE_SHA256, Gate::SCREEN_LIVENESS_SOURCE_SHA256]
    records = []
    groups.each_with_index do |pins, index|
      paths = [0, 8].include?(index) ? expected.keys.first(2) : expected.keys
      paths.each { |relative| assert_equal expected.fetch(relative), pins.fetch(relative); records << relative }
    end
    assert_equal 44, records.length
    assert_equal [10, 10, 8, 8, 8], expected.keys.map { |relative| records.count(relative) }
    session = File.binread(File.join(@root, 'macOS/Tests/CaptureServerTests/BelugaUpdateSparkleSessionTests.swift'))
    assert_equal 116488, session.bytesize
    assert_equal 'e2614a57ea6f2171551e598a621dee85825148d9b3c37f518c2a87d11ea43845',
      Digest::SHA256.hexdigest(session.byteslice(0, 100520))
    assert_equal 'e85b590d21b525d95515de65c67bd3095ce01c660c0c8526e3f0ef4868fe9d73', Digest::SHA256.hexdigest(session)
    assert_equal 555, Gate::BELUGA_CORE_MUTANT_TESTS.to_a.first(555).length
    assert_equal 43, Gate::PHASES.length
    assert_equal 22, Gate::SIMULATOR_SKIPS.length
  end

  def test_handoff_source_release_enrollment_exact_append_only_vectors_and_closed_source_pair
    assert_equal HANDOFF_SOURCE_EXPECTED_RUST, Gate::BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('handoff_source_position')
    assert_equal HANDOFF_SOURCE_EXPECTED_SWIFT, Gate::MAC_PINNED.first(520).drop(511)
    assert_equal ['CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests'], Gate::MAC_CLASSES.first(65).drop(64)
    assert_equal %w[src/handoff_source_position.rs tests/handoff_source_position.rs], Gate::BELUGA_CORE_SOURCE_FILES.first(118).drop(116)
    assert_equal HANDOFF_SOURCE_EXPECTED_RUST.map { |id| 'handoff_source_position/' + id }, Gate::BELUGA_CORE_QUALIFIED_PINNED.first(643).drop(632)
    assert_equal [122, 663, 40, 68, 565, 88],
      [Gate::BELUGA_CORE_SOURCE_FILES.length, Gate::BELUGA_CORE_QUALIFIED_PINNED.length,
       Gate::BELUGA_CORE_CARGO_SUITES.length, Gate::MAC_CLASSES.length,
       Gate::MAC_PINNED.length, Gate::BELUGA_CORE_RUNTIME_MARKERS.length]
    assert_equal 545, Gate::BELUGA_CORE_PINNED.length
    assert_equal 587, Gate::BELUGA_CORE_MUTANT_TESTS.length
    %w[src/handoff_source_position.rs tests/handoff_source_position.rs].each do |relative|
      path = File.join(core_crate, relative)
      prior = File.binread(path)
      begin
        File.unlink(path)
        enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
      ensure
        write(path, prior)
      end
    end
    manifest = File.join(core_crate, 'SOURCE_MANIFEST.sha256')
    prior = File.binread(manifest)
    record = prior.lines.find { |line| line.end_with?('  src/handoff_source_position.rs' + "\n") }
    refute_nil record
    begin
      write(manifest, prior + record)
      enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
    ensure
      write(manifest, prior)
    end
    assert_nil Gate.validate_beluga_core_artifacts(@root)
  end

  def test_handoff_source_release_enrollment_each_rust_case_requires_exact_suite_and_non_skipping_result
    expected = enrollment_qualified
    suite = 'handoff_source_position'
    HANDOFF_SOURCE_EXPECTED_RUST.each do |method|
      [lambda { |cases| cases.fetch(suite).delete(method) },
       lambda { |cases| cases.fetch(suite) << method },
       lambda { |cases| cases.fetch(suite).map! { |id| id == method ? id + '_foreign' : id } },
       lambda { |cases| cases.fetch(suite).delete(method); cases.fetch('policy') << method }].each do |mutate|
        cases = enrollment_cases
        mutate.call(cases)
        enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
        enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
      end
      %w[FAILED ignored].each do |status|
        enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results.sub("test #{method} ... ok", "test #{method} ... #{status}"), expected) }
      end
    end
    cases = enrollment_cases
    cases.delete(suite)
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery.sub('handoff_source_position-abcdef012345', 'policy-abcdef012345')) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results.sub(enrollment_header(suite), ''), expected) }
    assert_equal expected, Gate.beluga_core_inventory(enrollment_discovery)
    assert_equal expected, Gate.validate_beluga_core_rust(enrollment_results, expected)
  end

  def test_handoff_source_release_enrollment_each_native_case_requires_exact_class_and_non_skipping_result
    HANDOFF_SOURCE_EXPECTED_SWIFT.each do |id|
      [(@mac_methods - [id]), (@mac_methods + [id]),
       @mac_methods.map { |other| other == id ? id + '_foreign' : other },
       @mac_methods.map { |other| other == id ? id.sub('CaptureServerTests.', 'ForeignTests.') : other }].each do |ids|
        enrollment_rejects { Gate.mac_inventory(ids.join("\n")) }
      end
      klass, name = id.split('/')
      %w[failed skipped].each do |status|
        bad = mac_log.sub("Test Case '-[#{klass} #{name}]' passed", "Test Case '-[#{klass} #{name}]' #{status}")
        enrollment_rejects { Gate.validate_mac_log(bad, @mac_methods) }
      end
      enrollment_rejects { Gate.validate_mac_log(mac_log(@mac_methods - [id]), @mac_methods) }
      enrollment_rejects { Gate.validate_mac_log(mac_log(@mac_methods + [id]), @mac_methods) }
    end
    klass = 'CaptureServerTests.BelugaRustMacChromeHandoffSourcePolicyTests'
    enrollment_rejects { Gate.mac_inventory(@mac_methods.reject { |id| id.start_with?(klass + '/') }.join("\n")) }
    assert_equal @mac_methods, Gate.mac_inventory(@mac_methods.join("\n"))
    assert_equal @mac_methods, Gate.validate_mac_log(mac_log, @mac_methods)
  end

  def test_handoff_source_release_enrollment_markers_require_full_language_order_and_exact_literals
    markers = HANDOFF_SOURCE_EXPECTED_MARKERS
    assert_equal markers, Gate::BELUGA_CORE_RUNTIME_MARKERS.first(84).drop(82)
    order = Gate::BELUGA_CORE_RUNTIME_MARKER_ORDER
    assert_equal [88, 88], [order.length, order.uniq.length]
    assert_equal markers.first, order.fetch(41)
    assert_equal markers.last, order.fetch(85)
    assert order.first(44).all? { |line| line.start_with?('BelugaCore C ') }
    assert order.drop(44).all? { |line| line.start_with?('BelugaCore Swift ') }
    log = core_link_log
    markers.each do |marker|
      [log.sub(marker + "\n", ''), log.sub(marker + "\n", (marker + "\n") * 2),
       log.sub(marker, marker + '_foreign')].each { |bad| enrollment_rejects { Gate.validate_beluga_core_link(bad) } }
    end
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(markers.first, '__handoff_source_swap__').sub(markers.last, markers.first).sub('__handoff_source_swap__', markers.last)) }
    first_swift = order.fetch(44)
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(markers.first + "\n", '').sub(first_swift + "\n", first_swift + "\n" + markers.first + "\n")) }
    assert_nil Gate.validate_beluga_core_link(log)
  end

  def test_input_lease_release_enrollment_exact_append_only_vectors_and_closed_source_pair
    assert_equal INPUT_LEASE_EXPECTED_RUST, Gate::BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('microphone_input_lease')
    assert_equal INPUT_LEASE_EXPECTED_SWIFT, Gate::MICROPHONE_INPUT_LEASE_NATIVE_ADDITIONS
    assert_equal INPUT_LEASE_EXPECTED_SWIFT, Gate::MAC_PINNED.drop(520).first(20)
    assert_equal ['CaptureServerTests.BelugaRustMicrophoneInputLeaseTests'], Gate::MAC_CLASSES.drop(65).first(1)
    assert_equal %w[src/microphone_input_lease.rs tests/microphone_input_lease.rs], Gate::BELUGA_CORE_SOURCE_FILES.drop(118).first(2)
    assert_equal INPUT_LEASE_EXPECTED_RUST.map { |id| 'microphone_input_lease/' + id }, Gate::BELUGA_CORE_QUALIFIED_PINNED.drop(643).first(8)
    assert_equal [122, 663, 40, 68, 565, 88],
      [Gate::BELUGA_CORE_SOURCE_FILES.length, Gate::BELUGA_CORE_QUALIFIED_PINNED.length,
       Gate::BELUGA_CORE_CARGO_SUITES.length, Gate::MAC_CLASSES.length,
       Gate::MAC_PINNED.length, Gate::BELUGA_CORE_RUNTIME_MARKERS.length]
    assert_equal 545, Gate::BELUGA_CORE_PINNED.length
    assert_equal [4, 47, 44], Gate::MICROPHONE_INPUT_LEASE_NATIVE_COUNTS.values
    %w[src/microphone_input_lease.rs tests/microphone_input_lease.rs].each do |relative|
      path = File.join(core_crate, relative)
      prior = File.binread(path)
      begin
        File.unlink(path)
        enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
      ensure
        write(path, prior)
      end
    end
    manifest = File.join(core_crate, 'SOURCE_MANIFEST.sha256')
    prior = File.binread(manifest)
    record = prior.lines.find { |line| line.end_with?('  src/microphone_input_lease.rs' + "\n") }
    refute_nil record
    begin
      write(manifest, prior + record)
      enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
    ensure
      write(manifest, prior)
    end
    assert_nil Gate.validate_beluga_core_artifacts(@root)
  end

  def with_input_lease_fixture_source_pin(relative, changed)
    path = File.join(@root, relative)
    prior = File.binread(path)
    pins = Gate::MICROPHONE_INPUT_LEASE_SOURCE_SHA256
    begin
      write(path, changed)
      Gate.send(:remove_const, :MICROPHONE_INPUT_LEASE_SOURCE_SHA256)
      Gate.const_set(:MICROPHONE_INPUT_LEASE_SOURCE_SHA256, pins.merge(relative => Digest::SHA256.hexdigest(changed)).freeze)
      yield
    ensure
      Gate.send(:remove_const, :MICROPHONE_INPUT_LEASE_SOURCE_SHA256)
      Gate.const_set(:MICROPHONE_INPUT_LEASE_SOURCE_SHA256, pins)
      write(path, prior)
    end
  end

  def test_input_lease_release_enrollment_source_pins_and_exact_authored_declarations_cannot_be_borrowed
    assert_equal 6, Gate::MICROPHONE_INPUT_LEASE_SOURCE_SHA256.length
    Gate::MICROPHONE_INPUT_LEASE_SOURCE_SHA256.each do |relative, expected|
      path = File.join(@root, relative)
      prior = File.binread(path)
      assert_equal expected, Digest::SHA256.hexdigest(prior)
      begin
        write(path, prior + "\n")
        enrollment_rejects { Gate.microphone_input_lease_native_source_inventory(@root) }
        File.unlink(path)
        enrollment_rejects { Gate.microphone_input_lease_native_source_inventory(@root) }
        File.symlink(File.join(@root, 'fixture-absent-target'), path)
        enrollment_rejects { Gate.microphone_input_lease_native_source_inventory(@root) }
      ensure
        File.unlink(path) if File.symlink?(path)
        write(path, prior)
      end
    end
    relative = 'shared/Rust/BelugaCore/tests/microphone_input_lease.rs'
    original = File.binread(File.join(@root, relative))
    first, second = INPUT_LEASE_EXPECTED_RUST.first(2)
    [original.sub("#[test]\nfn #{first}(", "fn #{first}("),
     original.sub("fn #{first}(", "fn #{first}_foreign("),
     original + "\n#[test]\nfn #{first}() {}\n",
     original.sub("fn #{first}(", "fn malformed["),
     original.sub("fn #{first}(", 'fn temporary_fixture(').sub("fn #{second}(", "fn #{first}(").sub('fn temporary_fixture(', "fn #{second}(")].each do |changed|
      refute_equal original, changed
      # Only an isolated parser test overrides the full-file pin; the CLI has no override.
      with_input_lease_fixture_source_pin(relative, changed) do
        enrollment_rejects { Gate.validate_microphone_input_lease_sources(@root) }
      end
    end
    Gate::MICROPHONE_INPUT_LEASE_NATIVE_FILES.each do |suite, relative|
      original = File.binread(File.join(@root, relative))
      ids = INPUT_LEASE_EXPECTED_SWIFT.select { |id| id.start_with?(suite + '/') }.map { |id| id.split('/').last }
      next if ids.empty? # The old driver47 body is bound by its unchanged whole-file source pin.
      first, second = ids.first(2)
      [original.sub("func #{first}(", "func #{first}_foreign("),
       original.sub("func #{first}(", 'func malformed['),
       original + "\n    func #{first}() {}\n",
       original.sub("func #{first}(", 'func temporary_fixture(').sub("func #{second}(", "func #{first}(").sub('func temporary_fixture(', "func #{second}(")].each do |changed|
        refute_equal original, changed
        with_input_lease_fixture_source_pin(relative, changed) do
          enrollment_rejects { Gate.microphone_input_lease_native_source_inventory(@root) }
        end
      end
    end
    assert_equal [4, 47, 44], Gate.microphone_input_lease_native_source_inventory(@root).values.map(&:length)
  end

  def test_input_lease_release_enrollment_each_rust_case_requires_exact_suite_and_non_skipping_result
    expected = enrollment_qualified
    suite = 'microphone_input_lease'
    INPUT_LEASE_EXPECTED_RUST.each do |method|
      [lambda { |cases| cases.fetch(suite).delete(method) },
       lambda { |cases| cases.fetch(suite) << method },
       lambda { |cases| cases.fetch(suite).map! { |id| id == method ? id + '_foreign' : id } },
       lambda { |cases| cases.fetch(suite).delete(method); cases.fetch('policy') << method }].each do |mutate|
        cases = enrollment_cases
        mutate.call(cases)
        enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
        enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
      end
      %w[FAILED ignored].each do |status|
        enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results.sub("test #{method} ... ok", "test #{method} ... #{status}"), expected) }
      end
    end
    cases = enrollment_cases
    cases.delete(suite)
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery.sub('microphone_input_lease-abcdef012345', 'policy-abcdef012345')) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results.sub(enrollment_header(suite), ''), expected) }
    assert_equal expected, Gate.beluga_core_inventory(enrollment_discovery)
    assert_equal expected, Gate.validate_beluga_core_rust(enrollment_results, expected)
  end

  def test_input_lease_release_enrollment_each_native_case_requires_exact_source_class_and_non_skipping_result
    expected = Gate.microphone_input_lease_native_source_inventory(@root)
    assert_equal expected, Gate.microphone_input_lease_native_inventory(@root, @mac_methods.join("\n"))
    expected.values.flatten.each do |id|
      [(@mac_methods - [id]), (@mac_methods + [id]),
       @mac_methods.map { |other| other == id ? id + '_foreign' : other },
       @mac_methods.map { |other| other == id ? id.sub('CaptureServerTests.', 'ForeignTests.') : other }].each do |ids|
        enrollment_rejects { Gate.microphone_input_lease_native_inventory(@root, ids.join("\n")) }
      end
    end
    INPUT_LEASE_EXPECTED_SWIFT.each do |id|
      [(@mac_methods - [id]), (@mac_methods + [id])].each do |ids|
        enrollment_rejects { Gate.mac_inventory(ids.join("\n")) }
      end
      klass, name = id.split('/')
      %w[failed skipped].each do |status|
        bad = mac_log.sub("Test Case '-[#{klass} #{name}]' passed", "Test Case '-[#{klass} #{name}]' #{status}")
        enrollment_rejects { Gate.validate_mac_log(bad, @mac_methods) }
      end
      enrollment_rejects { Gate.validate_mac_log(mac_log(@mac_methods - [id]), @mac_methods) }
      enrollment_rejects { Gate.validate_mac_log(mac_log(@mac_methods + [id]), @mac_methods) }
    end
    expected.each_key do |klass|
      ['testUnreviewedFixture', 'malformed', 'testMalformed()'].each do |method|
        enrollment_rejects { Gate.microphone_input_lease_native_inventory(@root, (@mac_methods + [klass + '/' + method]).join("\n")) }
      end
    end
    assert_equal @mac_methods, Gate.validate_mac_log(mac_log, @mac_methods)
  end

  def test_input_lease_release_enrollment_markers_preserve_42_per_language_and_add_exact_43rd_pair
    markers = INPUT_LEASE_EXPECTED_MARKERS
    assert_equal markers, Gate::BELUGA_CORE_RUNTIME_MARKERS.drop(84).first(2)
    order = Gate::BELUGA_CORE_RUNTIME_MARKER_ORDER
    assert_equal [88, 88], [order.length, order.uniq.length]
    previous = Gate::BELUGA_CORE_RUNTIME_MARKERS.first(84)
    previous_order = previous.select { |marker| marker.start_with?('BelugaCore C ') } +
      previous.select { |marker| marker.start_with?('BelugaCore Swift ') }
    assert_equal [42, 42], [previous_order.count { |marker| marker.start_with?('BelugaCore C ') },
      previous_order.count { |marker| marker.start_with?('BelugaCore Swift ') }]
    assert_equal previous_order, order.reject { |marker| (markers + OUTPUT_FORMAT_EXPECTED_MARKERS).include?(marker) }
    assert_equal markers.first, order.fetch(42)
    assert_equal markers.last, order.fetch(86)
    assert order.first(44).all? { |marker| marker.start_with?('BelugaCore C ') }
    assert order.drop(44).all? { |marker| marker.start_with?('BelugaCore Swift ') }
    log = core_link_log
    markers.each do |marker|
      [log.sub(marker + "\n", ''), log.sub(marker + "\n", (marker + "\n") * 2),
       log.sub(marker, marker + '_foreign')].each { |bad| enrollment_rejects { Gate.validate_beluga_core_link(bad) } }
    end
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(markers.first, '__input_lease_swap__').sub(markers.last, markers.first).sub('__input_lease_swap__', markers.last)) }
    first_swift = order.fetch(44)
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(markers.first + "\n", '').sub(first_swift + "\n", first_swift + "\n" + markers.first + "\n")) }
    assert_nil Gate.validate_beluga_core_link(log)
  end

  def test_handoff_source_mutation_enrollment_preserves_555_prefix_and_exact_16_controls
    oracle = BelugaCoreHandoffSourceMutationOracle
    expected = {
      'prepare-rate-ceiling-widened' => 'preparation_scalar_edges_and_nonfinite_values_match_frozen_swift',
      'match-rate-equality-bypassed' => 'changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift',
      'mac-drift-widened' => 'exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct',
      'phone-drift-widened' => 'exact_mac_one_second_and_phone_two_second_limits_are_inclusive_and_distinct',
      'expiry-inclusive' => 'page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain',
      'page-clock-wrong-unit' => 'page_millisecond_clock_zero_and_exclusive_thirty_second_edges_keep_original_domain',
      'prepare-position-presence-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
      'match-duration-presence-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
      'continuity-identity-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
      'video-identity-ignored' => 'every_native_flag_combination_preserves_missing_and_identity_refusals',
      'prepare-NaN-duration-accepted' => 'preparation_scalar_edges_and_nonfinite_values_match_frozen_swift',
      'match-NaN-position-accepted' => 'changed_rate_duration_and_all_nonfinite_match_words_match_frozen_swift',
      'actual-c-prepare-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
      'actual-c-matches-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
      'actual-c-prepare-validator-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal',
      'actual-c-matches-validator-bypassed' => 'actual_c_exports_and_validators_preserve_votes_and_malformed_refusal'
    }.freeze
    assert_equal [571, 571, 16, 6], [Gate::BELUGA_CORE_MUTANT_TESTS.to_a.first(571).length, Gate::BELUGA_CORE_MUTANTS.first(571).uniq.length,
      oracle::CONTROLS.length, oracle::TESTS.length]
    assert_equal expected.to_a, Gate::BELUGA_CORE_MUTANT_TESTS.to_a.first(571).drop(555)
    assert_equal [expected, oracle], Gate::BELUGA_CORE_ADDED_MUTATION_ORACLES.first(9).last
    assert_equal expected.to_a, oracle::CONTROLS.map { |name, _, _, _, _, test| [name, test] }
    root = File.dirname(File.dirname(File.realpath(__FILE__)))
    source = File.binread(File.join(root, 'scripts/microphone-regression-gate.rb'))
    prefix = source.split("  BELUGA_CORE_MUTANT_TESTS = {\n", 2).last.split("    'prepare-rate-ceiling-widened'", 2).first
    assert_equal 'b6e344387bbc3180e3f2dbd624c56f7c39d999d1e2472f093e0f42e9effa400b', Digest::SHA256.hexdigest(prefix)
    oracle::CONTROLS.each do |name, path, suite, before, after, test|
      production = File.binread(File.join(root, 'shared/Rust/BelugaCore', path))
      assert_equal 1, production.scan(before).length, name
      refute_equal before, after
      assert_equal 'handoff_source_position', suite
      assert_includes HANDOFF_SOURCE_EXPECTED_RUST, test
    end
    producer = File.binread(File.join(root, 'shared/Rust/BelugaCore/scripts/mutation-tests.rb'))
    assert_includes producer, "handoff_source_only = ARGV == ['--handoff-source-only']"
    assert_includes producer, 'mutants.concat(BelugaCoreHandoffSourceMutationOracle::CONTROLS)'
    assert_includes producer, 'mutants = BelugaCoreHandoffSourceMutationOracle::CONTROLS if handoff_source_only'
  end

  def test_handoff_source_mutation_enrollment_all_six_singleton_decoders_reject_false_evidence
    oracle = BelugaCoreHandoffSourceMutationOracle
    oracle::TESTS.each do |test|
      [false, true].each do |passed|
        log = enrollment_mutation_log(oracle, test, passed: passed)
        assert_nil oracle.validate!(log, test, passed: passed,
          exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false)
        [log.sub('Finished', 'could not compile Finished'), log + log,
         log.sub("running 1 test", "running 0 tests"), log.sub(test, test + '_foreign'),
         log.sub('tests/handoff_source_position.rs', 'tests/foreign.rs'),
         log.sub('handoff_source_position-abcdef012345', 'foreign-abcdef012345'),
         log.sub('10 filtered out', '9 filtered out'), log.sub('0 ignored', '1 ignored'),
         log + "test #{test} ... ok\n", log + "skipped\n", log + "signal\n", log.b + "\xFF".b].each do |bad|
          enrollment_rejects { oracle.validate!(bad, test, passed: passed,
            exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false) }
        end
        [[passed ? 101 : 0, nil, false], [passed ? 0 : 101, 9, false],
         [passed ? 0 : 101, nil, true]].each do |exitstatus, termsig, timed_out|
          enrollment_rejects { oracle.validate!(log, test, passed: passed,
            exitstatus: exitstatus, termsig: termsig, timed_out: timed_out) }
        end
        unless passed
          [log.sub('assertion `left == right` failed', 'setup failed'),
           log.sub('tests/handoff_source_position.rs:1:1:', 'src/handoff_source_position.rs:1:1:'),
           log.sub("---- #{test} stdout ----", "---- foreign stdout ----"),
           log.sub('failures:', ''), log.sub('    ' + test, '    foreign'),
           log.sub('--test handoff_source_position', '--test foreign')].each do |bad|
            enrollment_rejects { oracle.validate!(bad, test, passed: false,
              exitstatus: 101, termsig: nil, timed_out: false) }
          end
        end
      end
    end
    enrollment_rejects { oracle.validate!(enrollment_mutation_log(oracle, oracle::TESTS.first, passed: false),
      'foreign', passed: false, exitstatus: 101, termsig: nil, timed_out: false) }
  end

  def test_handoff_source_mutation_enrollment_gate_requires_every_rejection_and_restoration
    full = core_mutations_log
    assert_nil Gate.validate_beluga_core_mutations(full)
    oracle = BelugaCoreHandoffSourceMutationOracle
    oracle::CONTROLS.each do |name, _, _, _, _, test|
      rejection = "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
      restoration = "BELUGA_CORE_MUTANT_RESTORED #{name} baseline-passed\n"
      [rejection, restoration].each do |marker|
        [full.sub(marker, ''), full.sub(marker, marker + marker)].each do |bad|
          enrollment_rejects { Gate.validate_beluga_core_mutations(bad) }
        end
      end
      failed = enrollment_mutation_log(oracle, test, passed: false)
      passed = enrollment_mutation_log(oracle, test, passed: true)
      [full.sub(failed, failed.sub('10 filtered out', '0 filtered out')),
       full.sub(passed, passed.sub(' ... ok', ' ... ignored'))].each do |bad|
        enrollment_rejects { Gate.validate_beluga_core_mutations(bad) }
      end
    end
    enrollment_rejects { Gate.validate_beluga_core_mutations(full.sub('cases=587', 'cases=555')) }
  end

  def test_input_lease_mutation_enrollment_preserves_571_prefix_and_exact_eight_literal_controls
    oracle = BelugaCoreMicrophoneInputLeaseMutationOracle
    expected = INPUT_LEASE_EXPECTED_MUTANTS
    assert_equal [587, 587, 8, 7], [Gate::BELUGA_CORE_MUTANT_TESTS.length, Gate::BELUGA_CORE_MUTANTS.uniq.length,
      oracle::CONTROLS.length, oracle::TESTS.length]
    assert_equal expected.to_a, Gate::BELUGA_CORE_MUTANT_TESTS.to_a.drop(571).first(8)
    assert_equal [expected, oracle], Gate::BELUGA_CORE_ADDED_MUTATION_ORACLES.fetch(9)
    assert_equal expected.to_a, oracle::CONTROLS.map { |name, _, _, _, _, test| [name, test] }
    root = File.dirname(File.dirname(File.realpath(__FILE__)))
    source = File.binread(File.join(root, 'scripts/microphone-regression-gate.rb'))
    prefix = source.split("  BELUGA_CORE_MUTANT_TESTS = {\n", 2).last.split("    'MIC-INPUT-ACQUIRE-BUDGET'", 2).first
    assert_equal '6d62610e74b177a99501ca6f80479f9dfa7a89ecf11f469042c89979fd316709', Digest::SHA256.hexdigest(prefix)
    oracle::CONTROLS.each do |name, path, suite, before, after, test|
      production = File.binread(File.join(root, 'shared/Rust/BelugaCore', path))
      assert_equal 1, production.scan(before).length, name
      refute_equal before, after
      assert_equal 'microphone_input_lease', suite
      assert_includes INPUT_LEASE_EXPECTED_RUST, test
    end
    producer = File.binread(File.join(root, 'shared/Rust/BelugaCore/scripts/mutation-tests.rb'))
    assert_includes producer, "microphone_input_lease_only = ARGV == ['--microphone-input-lease-only']"
    assert_includes producer, 'mutants.concat(BelugaCoreMicrophoneInputLeaseMutationOracle::CONTROLS)'
    assert_includes producer, 'mutants = BelugaCoreMicrophoneInputLeaseMutationOracle::CONTROLS if microphone_input_lease_only'
  end

  def test_input_lease_mutation_enrollment_all_seven_singleton_decoders_reject_false_evidence
    oracle = BelugaCoreMicrophoneInputLeaseMutationOracle
    oracle::TESTS.each do |test|
      [false, true].each do |passed|
        log = enrollment_mutation_log(oracle, test, passed: passed)
        assert_nil oracle.validate!(log, test, passed: passed,
          exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false)
        [log.sub('Finished', 'could not compile Finished'), log + log,
         log.sub("running 1 test", "running 0 tests"), log.sub(test, test + '_foreign'),
         log.sub('tests/microphone_input_lease.rs', 'tests/foreign.rs'),
         log.sub('microphone_input_lease-abcdef012345', 'foreign-abcdef012345'),
         log.sub('7 filtered out', '6 filtered out'), log.sub('0 ignored', '1 ignored'),
         log + "test #{test} ... ok\n", log + "skipped\n", log + "signal\n", log.b + "\xFF".b].each do |bad|
          enrollment_rejects { oracle.validate!(bad, test, passed: passed,
            exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false) }
        end
        [[passed ? 101 : 0, nil, false], [passed ? 0 : 101, 9, false],
         [passed ? 0 : 101, nil, true]].each do |exitstatus, termsig, timed_out|
          enrollment_rejects { oracle.validate!(log, test, passed: passed,
            exitstatus: exitstatus, termsig: termsig, timed_out: timed_out) }
        end
        unless passed
          [log.sub('assertion `left == right` failed', 'setup failed'),
           log.sub('tests/microphone_input_lease.rs:1:1:', 'src/microphone_input_lease.rs:1:1:'),
           log.sub("---- #{test} stdout ----", "---- foreign stdout ----"),
           log.sub('failures:', ''), log.sub('    ' + test, '    foreign'),
           log.sub('--test microphone_input_lease', '--test foreign')].each do |bad|
            enrollment_rejects { oracle.validate!(bad, test, passed: false,
              exitstatus: 101, termsig: nil, timed_out: false) }
          end
        end
      end
    end
    enrollment_rejects { oracle.validate!(enrollment_mutation_log(oracle, oracle::TESTS.first, passed: false),
      'foreign', passed: false, exitstatus: 101, termsig: nil, timed_out: false) }
  end

  def test_input_lease_mutation_enrollment_requires_every_singleton_rejection_and_fresh_restoration
    full = core_mutations_log
    assert_nil Gate.validate_beluga_core_mutations(full)
    oracle = BelugaCoreMicrophoneInputLeaseMutationOracle
    oracle::CONTROLS.each do |name, _, _, _, _, test|
      rejection = "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
      restoration = "BELUGA_CORE_MUTANT_RESTORED #{name} baseline-passed\n"
      [rejection, restoration].each do |marker|
        [full.sub(marker, ''), full.sub(marker, marker + marker)].each do |bad|
          enrollment_rejects { Gate.validate_beluga_core_mutations(bad) }
        end
      end
      failed = enrollment_mutation_log(oracle, test, passed: false)
      passed = enrollment_mutation_log(oracle, test, passed: true)
      [full.sub(failed, failed.sub('7 filtered out', '10 filtered out')),
       full.sub(passed, passed.sub(' ... ok', ' ... ignored'))].each do |bad|
        enrollment_rejects { Gate.validate_beluga_core_mutations(bad) }
      end
    end
    enrollment_rejects { Gate.validate_beluga_core_mutations(full.sub('cases=587', 'cases=571')) }
  end

  def test_output_format_release_enrollment_exact_append_only_vectors_and_closed_source_pair
    assert_equal OUTPUT_FORMAT_EXPECTED_RUST, Gate::BELUGA_CORE_ADDED_RUST_BY_SUITE.fetch('microphone_output_format')
    assert_equal OUTPUT_FORMAT_EXPECTED_SWIFT, Gate::MICROPHONE_OUTPUT_FORMAT_NATIVE_ADDITIONS
    assert_equal OUTPUT_FORMAT_EXPECTED_SWIFT, Gate::MAC_PINNED.drop(540).first(11)
    assert_equal ['CaptureServerTests.BelugaRustMicrophoneOutputFormatTests'], Gate::MAC_CLASSES.drop(66).first(1)
    assert_equal %w[src/microphone_output_format.rs tests/microphone_output_format.rs], Gate::BELUGA_CORE_SOURCE_FILES.drop(120)
    assert_equal OUTPUT_FORMAT_EXPECTED_RUST.map { |id| 'microphone_output_format/' + id }, Gate::BELUGA_CORE_QUALIFIED_PINNED.drop(651)
    assert_equal [122, 663, 40, 68, 565, 88],
      [Gate::BELUGA_CORE_SOURCE_FILES.length, Gate::BELUGA_CORE_QUALIFIED_PINNED.length,
       Gate::BELUGA_CORE_CARGO_SUITES.length, Gate::MAC_CLASSES.length,
       Gate::MAC_PINNED.length, Gate::BELUGA_CORE_RUNTIME_MARKERS.length]
    assert_equal [545, 579, 43, 22], [Gate::BELUGA_CORE_PINNED.length,
      Gate::BELUGA_CORE_MUTANT_TESTS.to_a.first(579).length, Gate::PHASES.length, Gate::SIMULATOR_SKIPS.length]
    %w[src/microphone_output_format.rs tests/microphone_output_format.rs].each do |relative|
      path = File.join(core_crate, relative)
      prior = File.binread(path)
      begin
        File.unlink(path)
        enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
      ensure
        write(path, prior)
      end
    end
    manifest = File.join(core_crate, 'SOURCE_MANIFEST.sha256')
    prior = File.binread(manifest)
    record = prior.lines.find { |line| line.end_with?('  src/microphone_output_format.rs' + "\n") }
    refute_nil record
    begin
      write(manifest, prior + record)
      enrollment_rejects { Gate.validate_beluga_core_artifacts(@root) }
    ensure
      write(manifest, prior)
    end
    assert_nil Gate.validate_beluga_core_artifacts(@root)
  end

  def with_output_format_fixture_source_pin(relative, changed)
    path = File.join(@root, relative)
    prior = File.binread(path)
    pins = Gate::MICROPHONE_OUTPUT_FORMAT_SOURCE_SHA256
    begin
      write(path, changed)
      Gate.send(:remove_const, :MICROPHONE_OUTPUT_FORMAT_SOURCE_SHA256)
      Gate.const_set(:MICROPHONE_OUTPUT_FORMAT_SOURCE_SHA256, pins.merge(relative => Digest::SHA256.hexdigest(changed)).freeze)
      yield
    ensure
      Gate.send(:remove_const, :MICROPHONE_OUTPUT_FORMAT_SOURCE_SHA256)
      Gate.const_set(:MICROPHONE_OUTPUT_FORMAT_SOURCE_SHA256, pins)
      write(path, prior)
    end
  end

  def test_output_format_release_enrollment_source_pins_and_exact_authored_declarations_cannot_be_borrowed
    assert_equal 6, Gate::MICROPHONE_OUTPUT_FORMAT_SOURCE_SHA256.length
    Gate::MICROPHONE_OUTPUT_FORMAT_SOURCE_SHA256.each do |relative, expected|
      path = File.join(@root, relative)
      prior = File.binread(path)
      assert_equal expected, Digest::SHA256.hexdigest(prior)
      begin
        write(path, prior + "\n")
        enrollment_rejects { Gate.microphone_output_format_native_source_inventory(@root) }
        File.unlink(path)
        enrollment_rejects { Gate.microphone_output_format_native_source_inventory(@root) }
        File.symlink(File.join(@root, 'fixture-absent-target'), path)
        enrollment_rejects { Gate.microphone_output_format_native_source_inventory(@root) }
      ensure
        File.unlink(path) if File.symlink?(path)
        write(path, prior)
      end
    end
    relative = 'shared/Rust/BelugaCore/tests/microphone_output_format.rs'
    original = File.binread(File.join(@root, relative))
    first, second = OUTPUT_FORMAT_EXPECTED_RUST.first(2)
    [original.sub("#[test]\nfn #{first}(", "fn #{first}("),
     original.sub("fn #{first}(", "fn #{first}_foreign("),
     original + "\n#[test]\nfn #{first}() {}\n",
     original.sub("fn #{first}(", 'fn malformed['),
     original.sub("fn #{first}(", 'fn temporary_fixture(').sub("fn #{second}(", "fn #{first}(").sub('fn temporary_fixture(', "fn #{second}(")].each do |changed|
      refute_equal original, changed
      # The override exists only in this isolated parser fixture, never the CLI.
      with_output_format_fixture_source_pin(relative, changed) do
        enrollment_rejects { Gate.validate_microphone_output_format_sources(@root) }
      end
    end
    relative = Gate::MICROPHONE_OUTPUT_FORMAT_NATIVE_FILES.values.first
    original = File.binread(File.join(@root, relative))
    first, second = OUTPUT_FORMAT_EXPECTED_SWIFT.first(2).map { |id| id.split('/').last }
    [original.sub("func #{first}(", "func #{first}_foreign("),
     original.sub("func #{first}(", 'func malformed['),
     original + "\n    func #{first}() {}\n",
     original.sub('final class BelugaRustMicrophoneOutputFormatTests:', 'final class ForeignFormatTests:'),
     original + "\nfinal class ForeignFormatTests: XCTestCase {}\n",
     original.sub("func #{first}(", 'func temporary_fixture(').sub("func #{second}(", "func #{first}(").sub('func temporary_fixture(', "func #{second}(")].each do |changed|
      refute_equal original, changed
      with_output_format_fixture_source_pin(relative, changed) do
        enrollment_rejects { Gate.microphone_output_format_native_source_inventory(@root) }
      end
    end
    assert_equal [11], Gate.microphone_output_format_native_source_inventory(@root).values.map(&:length)
    root = File.dirname(File.dirname(File.realpath(__FILE__)))
    gate_source = File.binread(File.join(root, 'scripts/microphone-regression-gate.rb'))
    assert_equal 1, gate_source.scan('MicrophoneRegressionGate.microphone_output_format_native_inventory(@root, mac_discovery)').length
    assert_equal 1, gate_source.scan("microphone_output_format_native_inventory(root, read_phase.call('mac-discovery'))").length
  end

  def test_output_format_release_enrollment_each_rust_case_requires_exact_suite_and_non_skipping_result
    expected = enrollment_qualified
    suite = 'microphone_output_format'
    OUTPUT_FORMAT_EXPECTED_RUST.each do |method|
      [lambda { |cases| cases.fetch(suite).delete(method) },
       lambda { |cases| cases.fetch(suite) << method },
       lambda { |cases| cases.fetch(suite).map! { |id| id == method ? id + '_foreign' : id } },
       lambda { |cases| cases.fetch(suite).delete(method); cases.fetch('policy') << method }].each do |mutate|
        cases = enrollment_cases
        mutate.call(cases)
        enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
        enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
      end
      %w[FAILED ignored].each do |status|
        enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results.sub("test #{method} ... ok", "test #{method} ... #{status}"), expected) }
      end
    end
    cases = enrollment_cases
    cases.delete(suite)
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery(cases)) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results(cases), expected) }
    enrollment_rejects { Gate.beluga_core_inventory(enrollment_discovery.sub('microphone_output_format-abcdef012345', 'policy-abcdef012345')) }
    enrollment_rejects { Gate.validate_beluga_core_rust(enrollment_results.sub(enrollment_header(suite), ''), expected) }
    assert_equal expected, Gate.beluga_core_inventory(enrollment_discovery)
    assert_equal expected, Gate.validate_beluga_core_rust(enrollment_results, expected)
  end

  def test_output_format_release_enrollment_each_native_case_requires_exact_source_class_and_non_skipping_result
    expected = Gate.microphone_output_format_native_source_inventory(@root)
    assert_equal expected, Gate.microphone_output_format_native_inventory(@root, @mac_methods.join("\n"))
    OUTPUT_FORMAT_EXPECTED_SWIFT.each do |id|
      [(@mac_methods - [id]), (@mac_methods + [id]),
       @mac_methods.map { |other| other == id ? id + '_foreign' : other },
       @mac_methods.map { |other| other == id ? id.sub('CaptureServerTests.', 'ForeignTests.') : other }].each do |ids|
        enrollment_rejects { Gate.microphone_output_format_native_inventory(@root, ids.join("\n")) }
        enrollment_rejects { Gate.mac_inventory(ids.join("\n")) }
      end
      klass, name = id.split('/')
      %w[failed skipped].each do |status|
        bad = mac_log.sub("Test Case '-[#{klass} #{name}]' passed", "Test Case '-[#{klass} #{name}]' #{status}")
        enrollment_rejects { Gate.validate_mac_log(bad, @mac_methods) }
      end
      enrollment_rejects { Gate.validate_mac_log(mac_log(@mac_methods - [id]), @mac_methods) }
      enrollment_rejects { Gate.validate_mac_log(mac_log(@mac_methods + [id]), @mac_methods) }
    end
    klass = Gate::MICROPHONE_OUTPUT_FORMAT_NATIVE_FILES.keys.first
    [@mac_methods + [klass + '/testUnreviewedFormatFixture'],
     @mac_methods.reject { |id| id.start_with?(klass + '/') }].each do |ids|
      enrollment_rejects { Gate.microphone_output_format_native_inventory(@root, ids.join("\n")) }
    end
    assert_equal @mac_methods, Gate.mac_inventory(@mac_methods.join("\n"))
    assert_equal @mac_methods, Gate.validate_mac_log(mac_log, @mac_methods)
  end

  def test_output_format_release_enrollment_markers_preserve_43_per_language_and_add_exact_44th_pair
    markers = OUTPUT_FORMAT_EXPECTED_MARKERS
    assert_equal markers, Gate::BELUGA_CORE_RUNTIME_MARKERS.drop(86)
    order = Gate::BELUGA_CORE_RUNTIME_MARKER_ORDER
    assert_equal [88, 88], [order.length, order.uniq.length]
    previous = Gate::BELUGA_CORE_RUNTIME_MARKERS.first(86)
    previous_order = previous.select { |marker| marker.start_with?('BelugaCore C ') } +
      previous.select { |marker| marker.start_with?('BelugaCore Swift ') }
    assert_equal [43, 43], [previous_order.count { |marker| marker.start_with?('BelugaCore C ') },
      previous_order.count { |marker| marker.start_with?('BelugaCore Swift ') }]
    assert_equal previous_order, order.reject { |marker| markers.include?(marker) }
    assert_equal markers.first, order.fetch(43)
    assert_equal markers.last, order.fetch(87)
    assert order.first(44).all? { |marker| marker.start_with?('BelugaCore C ') }
    assert order.drop(44).all? { |marker| marker.start_with?('BelugaCore Swift ') }
    log = core_link_log
    markers.each do |marker|
      [log.sub(marker + "\n", ''), log.sub(marker + "\n", (marker + "\n") * 2),
       log.sub(marker, marker + '_foreign')].each { |bad| enrollment_rejects { Gate.validate_beluga_core_link(bad) } }
    end
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(markers.first, '__output_format_swap__').sub(markers.last, markers.first).sub('__output_format_swap__', markers.last)) }
    first_swift = order.fetch(44)
    enrollment_rejects { Gate.validate_beluga_core_link(log.sub(markers.first + "\n", '').sub(first_swift + "\n", first_swift + "\n" + markers.first + "\n")) }
    assert_nil Gate.validate_beluga_core_link(log)
  end

  def test_output_format_mutation_enrollment_preserves_579_prefix_and_exact_eight_literal_controls
    oracle = BelugaCoreMicrophoneOutputFormatMutationOracle
    expected = OUTPUT_FORMAT_EXPECTED_MUTANTS
    assert_equal [587, 587, 8, 7], [Gate::BELUGA_CORE_MUTANT_TESTS.length, Gate::BELUGA_CORE_MUTANTS.uniq.length,
      oracle::CONTROLS.length, oracle::TESTS.length]
    assert_equal expected.to_a, Gate::BELUGA_CORE_MUTANT_TESTS.to_a.drop(579)
    assert_equal [expected, oracle], Gate::BELUGA_CORE_ADDED_MUTATION_ORACLES.last
    assert_equal expected.to_a, oracle::CONTROLS.map { |name, _, _, _, _, test| [name, test] }
    root = File.dirname(File.dirname(File.realpath(__FILE__)))
    source = File.binread(File.join(root, 'scripts/microphone-regression-gate.rb'))
    prefix = source.split("  BELUGA_CORE_MUTANT_TESTS = {\n", 2).last.split("    'MIC-OUTPUT-FORMAT-CLOSED-WIRE'", 2).first
    assert_equal '181aed6b0200ae3c43bbbb0895ed1dd4ac1d50488ca19ca84689e4d9422925b2', Digest::SHA256.hexdigest(prefix)
    oracle::CONTROLS.each do |name, path, suite, before, after, test|
      production = File.binread(File.join(root, 'shared/Rust/BelugaCore', path))
      assert_equal 1, production.scan(before).length, name
      refute_equal before, after
      assert_equal 'microphone_output_format', suite
      assert_includes OUTPUT_FORMAT_EXPECTED_RUST, test
    end
    producer = File.binread(File.join(root, 'shared/Rust/BelugaCore/scripts/mutation-tests.rb'))
    assert_includes producer, "microphone_output_format_only = ARGV == ['--microphone-output-format-only']"
    assert_includes producer, 'mutants.concat(BelugaCoreMicrophoneOutputFormatMutationOracle::CONTROLS)'
    assert_includes producer, 'mutants = BelugaCoreMicrophoneOutputFormatMutationOracle::CONTROLS if microphone_output_format_only'
  end

  def test_output_format_mutation_enrollment_all_seven_singleton_decoders_reject_false_evidence
    oracle = BelugaCoreMicrophoneOutputFormatMutationOracle
    oracle::TESTS.each do |test|
      [false, true].each do |passed|
        log = enrollment_mutation_log(oracle, test, passed: passed)
        assert_nil oracle.validate!(log, test, passed: passed,
          exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false)
        [log.sub('Finished', 'could not compile Finished'), log + log,
         log.sub('running 1 test', 'running 0 tests'), log.sub(test, test + '_foreign'),
         log.sub('tests/microphone_output_format.rs', 'tests/foreign.rs'),
         log.sub('microphone_output_format-abcdef012345', 'foreign-abcdef012345'),
         log.sub('11 filtered out', '10 filtered out'), log.sub('0 ignored', '1 ignored'),
         log + "test #{test} ... ok\n", log + "skipped\n", log + "signal\n", log.b + "\xFF".b].each do |bad|
          enrollment_rejects { oracle.validate!(bad, test, passed: passed,
            exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false) }
        end
        [[passed ? 101 : 0, nil, false], [passed ? 0 : 101, 9, false],
         [passed ? 0 : 101, nil, true]].each do |exitstatus, termsig, timed_out|
          enrollment_rejects { oracle.validate!(log, test, passed: passed,
            exitstatus: exitstatus, termsig: termsig, timed_out: timed_out) }
        end
        unless passed
          [log.sub('assertion `left == right` failed', 'setup failed'),
           log.sub('tests/microphone_output_format.rs:1:1:', 'src/microphone_output_format.rs:1:1:'),
           log.sub("---- #{test} stdout ----", '---- foreign stdout ----'),
           log.sub('failures:', ''), log.sub('    ' + test, '    foreign'),
           log.sub('--test microphone_output_format', '--test foreign')].each do |bad|
            enrollment_rejects { oracle.validate!(bad, test, passed: false,
              exitstatus: 101, termsig: nil, timed_out: false) }
          end
        end
      end
    end
    enrollment_rejects { oracle.validate!(enrollment_mutation_log(oracle, oracle::TESTS.first, passed: false),
      'foreign', passed: false, exitstatus: 101, termsig: nil, timed_out: false) }
  end

  def test_output_format_mutation_enrollment_requires_every_singleton_rejection_and_fresh_restoration
    full = core_mutations_log
    assert_nil Gate.validate_beluga_core_mutations(full)
    oracle = BelugaCoreMicrophoneOutputFormatMutationOracle
    oracle::CONTROLS.each do |name, _, _, _, _, test|
      rejection = "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
      restoration = "BELUGA_CORE_MUTANT_RESTORED #{name} baseline-passed\n"
      [rejection, restoration].each do |marker|
        [full.sub(marker, ''), full.sub(marker, marker + marker)].each do |bad|
          enrollment_rejects { Gate.validate_beluga_core_mutations(bad) }
        end
      end
      failed = enrollment_mutation_log(oracle, test, passed: false)
      passed = enrollment_mutation_log(oracle, test, passed: true)
      [full.sub(failed, failed.sub('11 filtered out', '10 filtered out')),
       full.sub(passed, passed.sub(' ... ok', ' ... ignored')),
       full.sub(passed, failed),
       full.sub(rejection + passed, passed + rejection)].each do |bad|
        enrollment_rejects { Gate.validate_beluga_core_mutations(bad) }
      end
    end
    enrollment_rejects { Gate.validate_beluga_core_mutations(full.sub('cases=587', 'cases=579')) }
  end

  def test_freshness_companion_enrollment_preserves_base8_and_complete_predecessor_rosters
    suite = 'CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests'
    relative = 'macOS/Tests/CaptureServerTests/FreshnessFaultBetweenPhasesTests.swift'
    id = suite + '/testFaultBetweenFreshnessPhasesRefusesBeforeProducer'
    base = Gate::UPDATER_MICROPHONE_NATIVE_PINNED
    assert_equal 112, base.values.flatten.length
    assert_equal '60f13a4bea6d5907b0853df763cff6970b9187a763d59031f377f568ddf73c6c',
      Digest::SHA256.hexdigest(JSON.generate(base) + "\n")
    assert_equal 8, base.fetch(suite).length
    assert_equal 'a64b39878b055f823d4fe7fefdc71559a371d46800db612b8903c20c64847191',
      Digest::SHA256.hexdigest(JSON.generate(base.fetch(suite)) + "\n")
    assert_equal({ suite => { path: relative, methods: [id] } },
      Gate::UPDATER_MICROPHONE_NATIVE_COMPANIONS)
    assert_equal 'c4632508c25a8304f240415e6b09975fe34c65effd1157dbc33ec23e43bbe17e',
      Gate::UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256.fetch(relative)
    assert_equal '35afc3bfca4c334263703f0563970ac8c745db8e5915e0ede476deb0d34871a2',
      Gate::UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256.fetch(Gate::UPDATER_MICROPHONE_NATIVE_FILES.fetch(suite))
    effective = Gate.updater_microphone_native_required_map
    assert_equal base.keys, effective.keys
    assert_equal 113, effective.values.flatten.length
    assert_equal base.fetch(suite) + [id], effective.fetch(suite)
    assert_equal '8631d6b1dfeeddc20de85f24376df8151d055061cba2f816205a21c3f49a3236',
      Digest::SHA256.hexdigest(JSON.generate(effective.fetch(suite)) + "\n")
    base.each { |name, methods| assert_equal methods, effective.fetch(name) unless name == suite }
    assert_equal [68, 565], [Gate::MAC_CLASSES.length, Gate::MAC_PINNED.length]
    assert_equal 'c0356fa029c17c1b21f92de3dcddce972b708165eaf46b58722c8683049abb85',
      Digest::SHA256.hexdigest(JSON.generate(Gate::MAC_CLASSES) + "\n")
    assert_equal 'a71e8812c4c031484761d9ea5b8c409e3d16ef3632cf6063ad5d89cb902eb402',
      Digest::SHA256.hexdigest(JSON.generate(Gate::MAC_PINNED) + "\n")
    assert_equal '4d1a71cddabc5adf57895982c8dbbd4b2c5e3c4bd99562b24c2863e62bc6261d',
      Digest::SHA256.hexdigest(JSON.generate(Gate::GATE_PINNED.first(230)) + "\n")
    added = %w[
      test_freshness_companion_enrollment_preserves_base8_and_complete_predecessor_rosters
      test_freshness_companion_source_requires_exact_extension_hash_and_single_method
      test_freshness_companion_requires_exact_discovery_filter_and_non_skipping_execution
    ]
    assert_equal 233, Gate::GATE_PINNED.length
    assert_equal added, Gate::GATE_PINNED.drop(230)
    reviewed_root = File.dirname(File.dirname(File.realpath(__FILE__)))
    declarations = Gate.gate_inventory(reviewed_root)
    assert_equal 290, declarations.length
    added.each { |method| assert_equal 1, declarations.count(method) }
    assert_equal effective.transform_values(&:sort), Gate.updater_microphone_native_source_inventory(@root)
  end

  def test_freshness_companion_source_requires_exact_extension_hash_and_single_method
    suite = 'CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests'
    companion = Gate::UPDATER_MICROPHONE_NATIVE_COMPANIONS.fetch(suite)
    relative = companion.fetch(:path)
    path = File.join(@root, relative)
    original = File.binread(path)
    assert_equal 'c4632508c25a8304f240415e6b09975fe34c65effd1157dbc33ec23e43bbe17e',
      Digest::SHA256.hexdigest(original)
    alias_path = File.join(@temporary, 'freshness-companion-alias')
    begin
      File.unlink(path)
      assert_raises(Errno::ENOENT) { Gate.updater_microphone_native_source_inventory(@root) }
      write(path, original + "\n// unreviewed companion byte drift\n")
      enrollment_rejects { Gate.updater_microphone_native_source_inventory(@root) }
      File.unlink(path)
      write(alias_path, original)
      File.symlink(alias_path, path)
      enrollment_rejects { Gate.updater_microphone_native_source_inventory(@root) }
      File.unlink(path)
      write(path, original)
      name = suite.split('.').last
      method = companion.fetch(:methods).fetch(0).split('/').last
      changes = [
        original.sub('extension ' + name + ' {', 'extension ForeignFreshnessCompanion {'),
        original.sub('func ' + method + '(', 'func ' + method + 'Renamed('),
        original.sub('    func ' + method + '(', '    func ' + method + "() {}\n    func " + method + '('),
        original + "\nextension #{name} {}\n",
        original + "\nfinal class ForeignFreshnessCompanion: XCTestCase {}\n"
      ]
      changes.each do |changed|
        refute_equal original, changed
        prior_pins = Gate::UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256
        begin
          write(path, changed)
          Gate.send(:remove_const, :UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256)
          Gate.const_set(:UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256,
            prior_pins.merge(relative => Digest::SHA256.hexdigest(changed)).freeze)
          # A fixture-only reseal must not admit the wrong role or authored method vector.
          enrollment_rejects { Gate.updater_microphone_native_source_inventory(@root) }
        ensure
          Gate.send(:remove_const, :UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256)
          Gate.const_set(:UPDATER_MICROPHONE_NATIVE_SOURCE_SHA256, prior_pins)
          write(path, original)
        end
      end
      assert_equal Gate.updater_microphone_native_required_map.transform_values(&:sort),
        Gate.updater_microphone_native_source_inventory(@root)
    ensure
      File.unlink(path) if File.symlink?(path)
      write(path, original)
      File.unlink(alias_path) if File.exist?(alias_path)
    end
  end

  def test_freshness_companion_requires_exact_discovery_filter_and_non_skipping_execution
    suite = 'CaptureServerTests.BelugaRustMicrophoneForwardingEvidenceTests'
    id = suite + '/testFaultBetweenFreshnessPhasesRefusesBeforeProducer'
    expected = Gate.updater_microphone_native_required_map.transform_values(&:sort)
    assert_equal 1, @mac_methods.count(id)
    assert_equal 9, expected.fetch(suite).length
    assert_equal expected, Gate.updater_microphone_native_inventory(@root, @mac_methods.join("\n"))
    missing = @mac_methods - [id]
    duplicate = @mac_methods + [id]
    renamed = @mac_methods.map { |method| method == id ? id + 'Renamed' : method }
    foreign = @mac_methods.map { |method| method == id ? id.sub(suite, 'CaptureServerTests.ForeignFreshnessCompanion') : method }
    [missing, duplicate, renamed, foreign].each do |methods|
      enrollment_rejects { Gate.updater_microphone_native_inventory(@root, methods.join("\n")) }
      enrollment_rejects { Gate.validate_mac_log(mac_log(methods), @mac_methods) }
      cases = methods.map { |method| klass, name = method.split('/'); %Q{<testcase classname="#{klass}" name="#{name}"/>} }
      enrollment_rejects { Gate.validate_xunit('<testsuite>' + cases.join + '</testsuite>', @mac_methods) }
    end
    full = mac_log
    method = id.split('/').last
    marker = "Test Case '-[#{suite} #{method}]' passed"
    %w[failed skipped].each do |state|
      changed = full.sub(marker, marker.sub(' passed', ' ' + state))
      refute_equal full, changed
      enrollment_rejects { Gate.validate_mac_log(changed, @mac_methods) }
    end
    cases = @mac_methods.map { |current| klass, name = current.split('/'); %Q{<testcase classname="#{klass}" name="#{name}"/>} }
    exact_case = %Q{<testcase classname="#{suite}" name="#{method}"/>}
    %w[failure error skipped].each do |state|
      changed = cases.join.sub(exact_case, exact_case.sub('/>', '><' + state + '/></testcase>'))
      refute_equal cases.join, changed
      enrollment_rejects { Gate.validate_xunit('<testsuite>' + changed + '</testsuite>', @mac_methods) }
    end
    assert_equal @mac_methods, Gate.validate_mac_log(full, @mac_methods)
    assert_equal @mac_methods, Gate.validate_xunit('<testsuite>' + cases.join + '</testsuite>', @mac_methods)
    value = receipt
    command = Gate.commands(@root, @evidence, value.fetch('invocation'), @tools,
      value.fetch('simulator'), @mac_methods, @handoff_methods).fetch('mac-tests')
    filter = Regexp.new(command.fetch(command.index('--filter') + 1))
    assert_match filter, id
    refute_match filter, id + 'Renamed'
    refute_match filter, id.sub(suite, 'CaptureServerTests.ForeignFreshnessCompanion')
  end
end
