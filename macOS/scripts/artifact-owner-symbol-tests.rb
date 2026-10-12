# frozen_string_literal: true
# Offline input doubles only; exercise the real helper, never launch native tools.
require 'stringio'
require_relative '../../shared/Rust/BelugaCore/scripts/artifact_support'

module BelugaCoreOwnerSymbolArtifactTests
  OWNER_SYMBOL_ARTIFACT = BelugaCoreArtifact
  OWNER_SYMBOL_OFFICIAL = '_beluga_core_network_adaptation_owner_zero_clock_event'
  OWNER_SYMBOL_CLOCKED = '_beluga_core_network_adaptation_owner_clocked_event'
  OWNER_SYMBOL_PREPARE = '_beluga_core_network_adaptation_owner_prepare_event'
  OWNER_SYMBOL_INACTIVE = '_beluga_core_network_adaptation_owner_adopt_inactive'
  OWNER_SYMBOL_BEGIN_ACTIVE = '_beluga_core_network_adaptation_owner_begin_active'
  OWNER_SYMBOL_FINISH_SUCCESS = '_beluga_core_network_adaptation_owner_finish_success'
  OWNER_SYMBOL_FINISH_SUCCESS_VALIDATED = '_beluga_core_network_adaptation_owner_finish_success_validated'
  OWNER_SYMBOL_FINISH_FAILURE = '_beluga_core_network_adaptation_owner_finish_failure'
  OWNER_SYMBOL_FINAL_ADOPT = '_beluga_core_network_adaptation_owner_final_adopt'
  OWNER_SYMBOL_MIC_READINESS = '_beluga_core_microphone_forwarding_readiness_decide'
  OWNER_SYMBOL_MIC_WATERMARK = '_beluga_core_microphone_forwarding_watermark_step'
  OWNER_SYMBOL_MIC_FRESHNESS = '_beluga_core_microphone_forwarding_freshness_decide'
  OWNER_SYMBOL_MIC_READINESS_VALID = '_beluga_core_microphone_forwarding_readiness_result_is_valid'
  OWNER_SYMBOL_MIC_WATERMARK_VALID = '_beluga_core_microphone_forwarding_watermark_result_is_valid'
  OWNER_SYMBOL_MIC_FRESHNESS_VALID = '_beluga_core_microphone_forwarding_freshness_result_is_valid'
  OWNER_SYMBOL_MIC_RETRY = '_beluga_core_microphone_forwarding_retry_step'
  OWNER_SYMBOL_MIC_RETRY_VALID = '_beluga_core_microphone_forwarding_retry_result_is_valid'
  OWNER_SYMBOL_UPDATE_ADMISSION = '_beluga_core_update_admission_decide'
  OWNER_SYMBOL_UPDATE_ADMISSION_VALID = '_beluga_core_update_admission_result_is_valid'
  OWNER_SYMBOL_SPARKLE_ADMISSION = '_beluga_core_update_sparkle_admission_decide'
  OWNER_SYMBOL_SPARKLE_ADMISSION_VALID = '_beluga_core_update_sparkle_admission_result_is_valid'
  OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION = '_beluga_core_update_unarmed_completion_decide'
  OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION_VALID = '_beluga_core_update_unarmed_completion_result_is_valid'
  OWNER_SYMBOL_UPDATE_ABORT = '_beluga_core_update_abort_decide'
  OWNER_SYMBOL_UPDATE_ABORT_VALID = '_beluga_core_update_abort_result_is_valid'
  OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE = '_beluga_core_handoff_source_prepare'
  OWNER_SYMBOL_HANDOFF_SOURCE_MATCH = '_beluga_core_handoff_source_matches'
  OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE_VALID = '_beluga_core_handoff_source_prepare_result_is_valid'
  OWNER_SYMBOL_HANDOFF_SOURCE_MATCH_VALID = '_beluga_core_handoff_source_matches_result_is_valid'
  OWNER_SYMBOL_MIC_INPUT_LEASE = '_beluga_core_microphone_input_lease_decide'
  OWNER_SYMBOL_MIC_INPUT_LEASE_VALID = '_beluga_core_microphone_input_lease_result_is_valid'
  OWNER_SYMBOL_MIC_OUTPUT_FORMAT = '_beluga_core_microphone_output_format_decide'
  OWNER_SYMBOL_MIC_OUTPUT_FORMAT_VALID = '_beluga_core_microphone_output_format_result_is_valid'
  OWNER_SYMBOL_OFFICIAL_NAMES = [OWNER_SYMBOL_OFFICIAL, OWNER_SYMBOL_CLOCKED, OWNER_SYMBOL_PREPARE, OWNER_SYMBOL_INACTIVE, OWNER_SYMBOL_BEGIN_ACTIVE, OWNER_SYMBOL_FINISH_SUCCESS, OWNER_SYMBOL_FINISH_SUCCESS_VALIDATED, OWNER_SYMBOL_FINISH_FAILURE, OWNER_SYMBOL_FINAL_ADOPT,
    OWNER_SYMBOL_MIC_READINESS, OWNER_SYMBOL_MIC_WATERMARK, OWNER_SYMBOL_MIC_FRESHNESS,
    OWNER_SYMBOL_MIC_READINESS_VALID, OWNER_SYMBOL_MIC_WATERMARK_VALID, OWNER_SYMBOL_MIC_FRESHNESS_VALID,
    OWNER_SYMBOL_MIC_RETRY, OWNER_SYMBOL_MIC_RETRY_VALID,
    OWNER_SYMBOL_UPDATE_ADMISSION, OWNER_SYMBOL_UPDATE_ADMISSION_VALID,
    OWNER_SYMBOL_SPARKLE_ADMISSION, OWNER_SYMBOL_SPARKLE_ADMISSION_VALID,
    OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION, OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION_VALID,
    OWNER_SYMBOL_UPDATE_ABORT, OWNER_SYMBOL_UPDATE_ABORT_VALID,
    OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE, OWNER_SYMBOL_HANDOFF_SOURCE_MATCH,
    OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE_VALID, OWNER_SYMBOL_HANDOFF_SOURCE_MATCH_VALID,
    OWNER_SYMBOL_MIC_INPUT_LEASE, OWNER_SYMBOL_MIC_INPUT_LEASE_VALID,
    OWNER_SYMBOL_MIC_OUTPUT_FORMAT, OWNER_SYMBOL_MIC_OUTPUT_FORMAT_VALID].freeze
  OWNER_SYMBOL_PRIVATE = %w[
    _beluga_private_state_roundtrip _beluga_private_state_validate
    _beluga_private_owner_bind _beluga_private_owner_event _beluga_private_clock_assay
    _beluga_private_owner_clock_event _beluga_private_owner_prepare_event
    _beluga_private_owner_adopt_inactive
    _beluga_private_owner_begin_active
    _beluga_private_owner_success _beluga_private_owner_finish_failure
    _beluga_private_owner_final_adopt
  ].freeze
  OwnerSymbolCommandStatus = Struct.new(:ok, :exitstatus) do
    def success?
      ok
    end
  end
  OwnerSymbolFileStat = Struct.new(:size)

  def test_owner_symbol_surface_accepts_exact_names_and_preserves_nm_argv_environment
    assert_equal 33, OWNER_SYMBOL_OFFICIAL_NAMES.length
    environment = { 'DEVELOPER_DIR' => OWNER_SYMBOL_ARTIFACT::DEVELOPER, 'LC_ALL' => 'C', 'FIXTURE' => 'unchanged' }
    near = OWNER_SYMBOL_OFFICIAL_NAMES.flat_map { |name| [
      name + '_suffix', name.delete_prefix('_'), name.upcase, '/fixture/' + name + '.rlib(member.o):'
    ] } + ['_ZN31beluga_private_owner_event17h0123456789abcdefE',
           '_ZN37beluga_private_owner_clock_event17h0123456789abcdefE',
           '_ZN39beluga_private_owner_prepare_event17h0123456789abcdefE'] +
      OWNER_SYMBOL_PRIVATE.flat_map { |name| [name + '_suffix', '_' + name, name.delete_prefix('_'), name.upcase] }
    outputs = { 'arm64' => OWNER_SYMBOL_OFFICIAL_NAMES.map { |name| "\t#{name} \n" }.join + near.join("\n") + "\n",
                'x86_64' => near.reverse.join("\n") + "\n" + OWNER_SYMBOL_OFFICIAL_NAMES.reverse.join("\n") + "\n" }
    before = Marshal.dump(environment)
    owner_symbol_nm_double(outputs, environment) do |calls|
      OWNER_SYMBOL_ARTIFACT.verify_owner_event_symbol_surface!('/fixture/archive', %w[arm64 x86_64], env: environment)
      assert_equal owner_symbol_expected_nm_calls('/fixture/archive', %w[arm64 x86_64], environment), calls
      calls.each { |call| assert_same environment, call.fetch(:env) }
    end
    assert_equal before, Marshal.dump(environment)
  end

  def test_owner_symbol_surface_rejects_missing_or_duplicate_official_definition
    [[OWNER_SYMBOL_OFFICIAL, 'zero-clock'], [OWNER_SYMBOL_CLOCKED, 'clocked'],
     [OWNER_SYMBOL_PREPARE, 'prepare'], [OWNER_SYMBOL_INACTIVE, 'inactive'],
     [OWNER_SYMBOL_BEGIN_ACTIVE, 'begin-active'], [OWNER_SYMBOL_FINISH_SUCCESS, 'finish-success'],
     [OWNER_SYMBOL_FINISH_SUCCESS_VALIDATED, 'finish-success-validated'],
     [OWNER_SYMBOL_FINISH_FAILURE, 'finish-failure'], [OWNER_SYMBOL_FINAL_ADOPT, 'final-adopt'],
     [OWNER_SYMBOL_MIC_READINESS, 'mic-readiness'], [OWNER_SYMBOL_MIC_WATERMARK, 'mic-watermark'],
     [OWNER_SYMBOL_MIC_FRESHNESS, 'mic-freshness'],
     [OWNER_SYMBOL_MIC_READINESS_VALID, 'mic-readiness-valid'], [OWNER_SYMBOL_MIC_WATERMARK_VALID, 'mic-watermark-valid'],
     [OWNER_SYMBOL_MIC_FRESHNESS_VALID, 'mic-freshness-valid'],
     [OWNER_SYMBOL_MIC_RETRY, 'mic-retry'], [OWNER_SYMBOL_MIC_RETRY_VALID, 'mic-retry-valid'],
     [OWNER_SYMBOL_UPDATE_ADMISSION, 'update-admission'], [OWNER_SYMBOL_UPDATE_ADMISSION_VALID, 'update-admission-valid'],
     [OWNER_SYMBOL_SPARKLE_ADMISSION, 'update-sparkle-admission'], [OWNER_SYMBOL_SPARKLE_ADMISSION_VALID, 'update-sparkle-admission-valid'],
     [OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION, 'update-unarmed-completion'], [OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION_VALID, 'update-unarmed-completion-valid'],
     [OWNER_SYMBOL_UPDATE_ABORT, 'update-abort'], [OWNER_SYMBOL_UPDATE_ABORT_VALID, 'update-abort-valid'],
     [OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE, 'handoff-source-prepare'], [OWNER_SYMBOL_HANDOFF_SOURCE_MATCH, 'handoff-source-match'],
     [OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE_VALID, 'handoff-source-prepare-valid'], [OWNER_SYMBOL_HANDOFF_SOURCE_MATCH_VALID, 'handoff-source-match-valid'],
     [OWNER_SYMBOL_MIC_INPUT_LEASE, 'mic-input-lease'], [OWNER_SYMBOL_MIC_INPUT_LEASE_VALID, 'mic-input-lease-valid'],
     [OWNER_SYMBOL_MIC_OUTPUT_FORMAT, 'mic-output-format'], [OWNER_SYMBOL_MIC_OUTPUT_FORMAT_VALID, 'mic-output-format-valid']].each do |name, label|
      other = (OWNER_SYMBOL_OFFICIAL_NAMES - [name]).join("\n")
      %w[arm64 x86_64].each do |architecture|
        ['', name + "_suffix\n", "#{name}\n#{name}\n"].each do |invalid|
          environment = { 'DEVELOPER_DIR' => OWNER_SYMBOL_ARTIFACT::DEVELOPER, 'LC_ALL' => 'C' }
          owner_symbol_nm_double({ architecture => "#{other}\n" + invalid }, environment) do |calls|
            error = assert_raises(RuntimeError) do
              OWNER_SYMBOL_ARTIFACT.verify_owner_event_symbol_surface!('/fixture/archive', [architecture], env: environment)
            end
            assert_equal "#{architecture}: official Owner #{label} symbol must be defined exactly once", error.message
            assert_equal owner_symbol_expected_nm_calls('/fixture/archive', [architecture], environment), calls
          end
        end
      end
    end
  end

  def test_owner_symbol_surface_rejects_each_of_the_seven_exact_private_definitions
    # Historical method name retained; all twelve exact private aliases are rejected.
    assert_equal 12, OWNER_SYMBOL_PRIVATE.length
    OWNER_SYMBOL_PRIVATE.each do |name|
      environment = { 'DEVELOPER_DIR' => OWNER_SYMBOL_ARTIFACT::DEVELOPER, 'LC_ALL' => 'C' }
      owner_symbol_nm_double({ 'arm64' => OWNER_SYMBOL_OFFICIAL_NAMES.join("\n") + "\n#{name}\n" }, environment) do |calls|
        error = assert_raises(RuntimeError) do
          OWNER_SYMBOL_ARTIFACT.verify_owner_event_symbol_surface!('/fixture/archive', ['arm64'], env: environment)
        end
        assert_equal "arm64: unapproved private C export: #{name}", error.message
        assert_equal owner_symbol_expected_nm_calls('/fixture/archive', ['arm64'], environment), calls
      end
    end
  end

  def test_owner_symbol_surface_never_pools_arm64_and_x86_64_definitions
    valid = OWNER_SYMBOL_OFFICIAL_NAMES.join("\n") + "\n"
    cases = [
      [{ 'arm64' => valid, 'x86_64' => '' }, %w[arm64 x86_64], 'x86_64: official Owner zero-clock'],
      [{ 'arm64' => '', 'x86_64' => valid }, ['arm64'], 'arm64: official Owner zero-clock'],
      [{ 'arm64' => "#{OWNER_SYMBOL_OFFICIAL}\n", 'x86_64' => "#{OWNER_SYMBOL_CLOCKED}\n" },
       ['arm64'], 'arm64: official Owner clocked'],
      [{ 'arm64' => valid, 'x86_64' => "#{OWNER_SYMBOL_CLOCKED}\n" },
       %w[arm64 x86_64], 'x86_64: official Owner zero-clock'],
      [{ 'arm64' => valid, 'x86_64' => "#{OWNER_SYMBOL_OFFICIAL}\n" },
       %w[arm64 x86_64], 'x86_64: official Owner clocked'],
      [{ 'arm64' => valid, 'x86_64' => valid + "#{OWNER_SYMBOL_CLOCKED}\n" },
       %w[arm64 x86_64], 'x86_64: official Owner clocked'],
      [{ 'arm64' => valid, 'x86_64' => "#{OWNER_SYMBOL_OFFICIAL}\n#{OWNER_SYMBOL_CLOCKED}\n" },
       %w[arm64 x86_64], 'x86_64: official Owner prepare'],
      [{ 'arm64' => "#{OWNER_SYMBOL_OFFICIAL}\n#{OWNER_SYMBOL_CLOCKED}\n", 'x86_64' => valid },
       ['arm64'], 'arm64: official Owner prepare'],
      [{ 'arm64' => valid, 'x86_64' => valid + "#{OWNER_SYMBOL_PREPARE}\n" },
       %w[arm64 x86_64], 'x86_64: official Owner prepare'],
      [{ 'arm64' => valid, 'x86_64' => (OWNER_SYMBOL_OFFICIAL_NAMES - [OWNER_SYMBOL_INACTIVE]).join("\n") + "\n" },
       %w[arm64 x86_64], 'x86_64: official Owner inactive'],
      [{ 'arm64' => (OWNER_SYMBOL_OFFICIAL_NAMES - [OWNER_SYMBOL_INACTIVE]).join("\n") + "\n", 'x86_64' => valid },
       ['arm64'], 'arm64: official Owner inactive'],
      [{ 'arm64' => valid, 'x86_64' => valid + "#{OWNER_SYMBOL_INACTIVE}\n" },
       %w[arm64 x86_64], 'x86_64: official Owner inactive'],
      [{ 'arm64' => valid, 'x86_64' => (OWNER_SYMBOL_OFFICIAL_NAMES - [OWNER_SYMBOL_BEGIN_ACTIVE]).join("\n") + "\n" },
       %w[arm64 x86_64], 'x86_64: official Owner begin-active'],
      [{ 'arm64' => (OWNER_SYMBOL_OFFICIAL_NAMES - [OWNER_SYMBOL_BEGIN_ACTIVE]).join("\n") + "\n", 'x86_64' => valid },
       ['arm64'], 'arm64: official Owner begin-active'],
      [{ 'arm64' => valid, 'x86_64' => valid + "#{OWNER_SYMBOL_BEGIN_ACTIVE}\n" },
       %w[arm64 x86_64], 'x86_64: official Owner begin-active'],
      [{ 'arm64' => valid, 'x86_64' => valid + "#{OWNER_SYMBOL_PRIVATE[-2]}\n" },
       %w[arm64 x86_64], 'x86_64: unapproved'],
      [{ 'arm64' => valid, 'x86_64' => valid + "#{OWNER_SYMBOL_PRIVATE.last}\n" },
       %w[arm64 x86_64], 'x86_64: unapproved']
    ]
    [[OWNER_SYMBOL_FINISH_SUCCESS, 'finish-success'], [OWNER_SYMBOL_FINISH_SUCCESS_VALIDATED, 'finish-success-validated'],
     [OWNER_SYMBOL_FINISH_FAILURE, 'finish-failure'],
     [OWNER_SYMBOL_FINAL_ADOPT, 'final-adopt'], [OWNER_SYMBOL_MIC_READINESS, 'mic-readiness'],
     [OWNER_SYMBOL_MIC_WATERMARK, 'mic-watermark'], [OWNER_SYMBOL_MIC_FRESHNESS, 'mic-freshness'],
     [OWNER_SYMBOL_MIC_READINESS_VALID, 'mic-readiness-valid'], [OWNER_SYMBOL_MIC_WATERMARK_VALID, 'mic-watermark-valid'],
     [OWNER_SYMBOL_MIC_FRESHNESS_VALID, 'mic-freshness-valid'],
     [OWNER_SYMBOL_MIC_RETRY, 'mic-retry'], [OWNER_SYMBOL_MIC_RETRY_VALID, 'mic-retry-valid'],
     [OWNER_SYMBOL_UPDATE_ADMISSION, 'update-admission'], [OWNER_SYMBOL_UPDATE_ADMISSION_VALID, 'update-admission-valid'],
     [OWNER_SYMBOL_SPARKLE_ADMISSION, 'update-sparkle-admission'], [OWNER_SYMBOL_SPARKLE_ADMISSION_VALID, 'update-sparkle-admission-valid'],
     [OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION, 'update-unarmed-completion'], [OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION_VALID, 'update-unarmed-completion-valid'],
     [OWNER_SYMBOL_UPDATE_ABORT, 'update-abort'], [OWNER_SYMBOL_UPDATE_ABORT_VALID, 'update-abort-valid'],
     [OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE, 'handoff-source-prepare'], [OWNER_SYMBOL_HANDOFF_SOURCE_MATCH, 'handoff-source-match'],
     [OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE_VALID, 'handoff-source-prepare-valid'], [OWNER_SYMBOL_HANDOFF_SOURCE_MATCH_VALID, 'handoff-source-match-valid'],
     [OWNER_SYMBOL_MIC_INPUT_LEASE, 'mic-input-lease'], [OWNER_SYMBOL_MIC_INPUT_LEASE_VALID, 'mic-input-lease-valid'],
     [OWNER_SYMBOL_MIC_OUTPUT_FORMAT, 'mic-output-format'], [OWNER_SYMBOL_MIC_OUTPUT_FORMAT_VALID, 'mic-output-format-valid']].each do |name, label|
      cases.concat([
        [{ 'arm64' => valid, 'x86_64' => (OWNER_SYMBOL_OFFICIAL_NAMES - [name]).join("\n") + "\n" },
         %w[arm64 x86_64], "x86_64: official Owner #{label}"],
        [{ 'arm64' => (OWNER_SYMBOL_OFFICIAL_NAMES - [name]).join("\n") + "\n", 'x86_64' => valid },
         ['arm64'], "arm64: official Owner #{label}"],
        [{ 'arm64' => valid, 'x86_64' => valid + "#{name}\n" },
         %w[arm64 x86_64], "x86_64: official Owner #{label}"]
      ])
    end
    cases.each do |outputs, reached, diagnostic|
      environment = { 'DEVELOPER_DIR' => OWNER_SYMBOL_ARTIFACT::DEVELOPER, 'LC_ALL' => 'C' }
      owner_symbol_nm_double(outputs, environment) do |calls|
        error = assert_raises(RuntimeError) do
          OWNER_SYMBOL_ARTIFACT.verify_owner_event_symbol_surface!('/fixture/archive', %w[arm64 x86_64], env: environment)
        end
        assert_includes error.message, diagnostic
        assert_equal owner_symbol_expected_nm_calls('/fixture/archive', reached, environment), calls
      end
    end
  end

  def test_owner_symbol_surface_propagates_real_capture_failure_without_retry_or_fallback
    environment = { 'DEVELOPER_DIR' => OWNER_SYMBOL_ARTIFACT::DEVELOPER, 'LC_ALL' => 'C' }
    owner_symbol_nm_double({ 'arm64' => OWNER_SYMBOL_OFFICIAL_NAMES.join("\n") + "\n" }, environment, failure: 'fixture nm denied') do |calls|
      error = assert_raises(RuntimeError) do
        OWNER_SYMBOL_ARTIFACT.verify_owner_event_symbol_surface!('/fixture/archive', %w[arm64 x86_64], env: environment)
      end
      assert_includes error.message, 'Command failed:'
      assert_includes error.message, 'fixture nm denied'
      assert_equal owner_symbol_expected_nm_calls('/fixture/archive', ['arm64'], environment), calls
    end
  end

  def test_owner_symbol_artifact_smoke_false_still_checks_all_four_advertised_architectures
    fixture = owner_symbol_artifact_fixture
    capture_io do
      owner_symbol_artifact_doubles(fixture) do
        OWNER_SYMBOL_ARTIFACT.verify!(fixture.fetch(:artifact), smoke: false)
      end
    end
    expected = owner_symbol_all_archive_nm_calls(fixture)
    assert_equal expected, fixture.fetch(:calls).select { |call| call.fetch(:argv)[1] == 'nm' }
    assert_equal [OWNER_SYMBOL_ARTIFACT::CRATE, fixture.fetch(:artifact)], fixture.fetch(:walks_seen)
    assert_equal owner_symbol_archives(fixture).keys, fixture.fetch(:archives_seen)
    assert_equal [File.join(OWNER_SYMBOL_ARTIFACT::CRATE, 'target')], fixture.fetch(:mkdir_seen)
    assert_equal [['verify-', File.join(OWNER_SYMBOL_ARTIFACT::CRATE, 'target')]], fixture.fetch(:scratch_seen)
    assert_equal fixture.fetch(:executables), fixture.fetch(:executables_seen)
    assert_equal 17, fixture.fetch(:calls).length # four plutil, three lipo, six pinned-tool/SDK calls, four nm
    assert_equal 0, fixture.fetch(:native_runs)
  end

  def test_owner_symbol_artifact_smoke_false_rejects_missing_and_private_last_architecture
    valid = OWNER_SYMBOL_OFFICIAL_NAMES.join("\n") + "\n"
    cases = [
      ['', 'official Owner zero-clock symbol must be defined exactly once'],
      ["#{OWNER_SYMBOL_OFFICIAL}\n", 'official Owner clocked symbol must be defined exactly once'],
      ["#{OWNER_SYMBOL_CLOCKED}\n", 'official Owner zero-clock symbol must be defined exactly once'],
      [valid + "#{OWNER_SYMBOL_CLOCKED}\n", 'official Owner clocked symbol must be defined exactly once'],
      ["#{OWNER_SYMBOL_OFFICIAL}\n#{OWNER_SYMBOL_CLOCKED}\n", 'official Owner prepare symbol must be defined exactly once'],
      [valid + "#{OWNER_SYMBOL_PREPARE}\n", 'official Owner prepare symbol must be defined exactly once'],
      [(OWNER_SYMBOL_OFFICIAL_NAMES - [OWNER_SYMBOL_INACTIVE]).join("\n") + "\n", 'official Owner inactive symbol must be defined exactly once'],
      [valid + "#{OWNER_SYMBOL_INACTIVE}\n", 'official Owner inactive symbol must be defined exactly once'],
      [(OWNER_SYMBOL_OFFICIAL_NAMES - [OWNER_SYMBOL_BEGIN_ACTIVE]).join("\n") + "\n", 'official Owner begin-active symbol must be defined exactly once'],
      [valid + "#{OWNER_SYMBOL_BEGIN_ACTIVE}\n", 'official Owner begin-active symbol must be defined exactly once']
    ] + [[OWNER_SYMBOL_FINISH_SUCCESS, 'finish-success'], [OWNER_SYMBOL_FINISH_SUCCESS_VALIDATED, 'finish-success-validated'],
         [OWNER_SYMBOL_FINISH_FAILURE, 'finish-failure'],
         [OWNER_SYMBOL_FINAL_ADOPT, 'final-adopt'],
         [OWNER_SYMBOL_MIC_READINESS, 'mic-readiness'], [OWNER_SYMBOL_MIC_WATERMARK, 'mic-watermark'],
         [OWNER_SYMBOL_MIC_FRESHNESS, 'mic-freshness'],
         [OWNER_SYMBOL_MIC_READINESS_VALID, 'mic-readiness-valid'], [OWNER_SYMBOL_MIC_WATERMARK_VALID, 'mic-watermark-valid'],
         [OWNER_SYMBOL_MIC_FRESHNESS_VALID, 'mic-freshness-valid'],
         [OWNER_SYMBOL_MIC_RETRY, 'mic-retry'], [OWNER_SYMBOL_MIC_RETRY_VALID, 'mic-retry-valid'],
     [OWNER_SYMBOL_UPDATE_ADMISSION, 'update-admission'], [OWNER_SYMBOL_UPDATE_ADMISSION_VALID, 'update-admission-valid'],
     [OWNER_SYMBOL_SPARKLE_ADMISSION, 'update-sparkle-admission'], [OWNER_SYMBOL_SPARKLE_ADMISSION_VALID, 'update-sparkle-admission-valid'],
     [OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION, 'update-unarmed-completion'], [OWNER_SYMBOL_UPDATE_UNARMED_COMPLETION_VALID, 'update-unarmed-completion-valid'],
     [OWNER_SYMBOL_UPDATE_ABORT, 'update-abort'], [OWNER_SYMBOL_UPDATE_ABORT_VALID, 'update-abort-valid'],
     [OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE, 'handoff-source-prepare'], [OWNER_SYMBOL_HANDOFF_SOURCE_MATCH, 'handoff-source-match'],
     [OWNER_SYMBOL_HANDOFF_SOURCE_PREPARE_VALID, 'handoff-source-prepare-valid'], [OWNER_SYMBOL_HANDOFF_SOURCE_MATCH_VALID, 'handoff-source-match-valid'],
     [OWNER_SYMBOL_MIC_INPUT_LEASE, 'mic-input-lease'], [OWNER_SYMBOL_MIC_INPUT_LEASE_VALID, 'mic-input-lease-valid'],
     [OWNER_SYMBOL_MIC_OUTPUT_FORMAT, 'mic-output-format'], [OWNER_SYMBOL_MIC_OUTPUT_FORMAT_VALID, 'mic-output-format-valid']].flat_map { |name, label| [
      [(OWNER_SYMBOL_OFFICIAL_NAMES - [name]).join("\n") + "\n", "official Owner #{label} symbol must be defined exactly once"],
      [valid + "#{name}\n", "official Owner #{label} symbol must be defined exactly once"]
    ] } + OWNER_SYMBOL_PRIVATE.map { |name| [valid + "#{name}\n", "unapproved private C export: #{name}"] }
    cases.each do |output, diagnostic|
      fixture = owner_symbol_artifact_fixture
      simulator = File.join(fixture.fetch(:artifact), 'ios-arm64_x86_64-simulator', 'BelugaCore.framework/BelugaCore')
      fixture.fetch(:symbols)[[simulator, 'x86_64']] = output
      capture_io do
        owner_symbol_artifact_doubles(fixture) do
          error = assert_raises(RuntimeError) { OWNER_SYMBOL_ARTIFACT.verify!(fixture.fetch(:artifact), smoke: false) }
          assert_equal "x86_64: #{diagnostic}", error.message
        end
      end
      assert_equal owner_symbol_all_archive_nm_calls(fixture),
                   fixture.fetch(:calls).select { |call| call.fetch(:argv)[1] == 'nm' }
      assert_equal 0, fixture.fetch(:native_runs)
    end
  end

  def test_owner_symbol_artifact_inputs_keep_source_tool_copy_and_archive_guards_real
    mutations = {
      source_inventory: ['Source inventory differs', ->(f) { f.fetch(:walks)[OWNER_SYMBOL_ARTIFACT::CRATE].shift }],
      source_hash: ['Source manifest bytes or source hash differs', ->(f) {
        f.fetch(:files)[File.join(OWNER_SYMBOL_ARTIFACT::CRATE, 'Cargo.toml')] += 'changed'
      }],
      tool_absence: ['Pinned tool unavailable', ->(f) { f.fetch(:executables).delete(OWNER_SYMBOL_ARTIFACT::RUSTC) }],
      tool_version: ['Pinned rustc release differs', ->(f) {
        f.fetch(:responses)[[OWNER_SYMBOL_ARTIFACT::RUSTC, '--version', '--verbose']] =
          "rustc fixture\nrelease: 0.0.0\nhost: aarch64-apple-darwin\n"
      }],
      copied_header: ['macos-arm64/beluga_core.h copy differs', ->(f) {
        f.fetch(:files)[File.join(f.fetch(:artifact), 'macos-arm64/BelugaCore.framework/Headers/beluga_core.h')] += 'changed'
        owner_symbol_reseal_artifact_input(f)
      }],
      archive_magic: ['Framework main binary is not a static archive', ->(f) {
        f.fetch(:files)[owner_symbol_archives(f).keys.first] = 'not-an-archive'
        owner_symbol_reseal_artifact_input(f)
      }]
    }
    mutations.each do |name, (diagnostic, mutate)|
      fixture = owner_symbol_artifact_fixture
      mutate.call(fixture)
      capture_io do
        owner_symbol_artifact_doubles(fixture) do
          error = assert_raises(RuntimeError, name.to_s) { OWNER_SYMBOL_ARTIFACT.verify!(fixture.fetch(:artifact), smoke: false) }
          assert_includes error.message, diagnostic
        end
      end
      assert_empty fixture.fetch(:calls).select { |call| call.fetch(:argv)[1] == 'nm' }, name.to_s
      assert_equal 0, fixture.fetch(:native_runs)
    end
  end

  def test_owner_native_archive_census_accepts_manual_thin_fat_and_bounded_index_padding
    %w[arm64 x86_64].each do |architecture|
      (0..7).each do |padding|
        strings = OWNER_SYMBOL_OFFICIAL + "\0" + "\0" * ((1 - padding) % 8)
        bytes = owner_symbol_native_archive(architecture, index_strings: strings, index_padding: "\0" * padding)
        owner_symbol_archive_input_double(bytes) do |calls|
          OWNER_SYMBOL_ARTIFACT.verify_static_archive!('/fixture/archive', [architecture])
          assert_equal [['/fixture/archive', 'rb']], calls
        end
      end
    end
    owner_symbol_archive_input_double(owner_symbol_fat_archive) do |calls|
      OWNER_SYMBOL_ARTIFACT.verify_static_archive!('/fixture/archive', %w[arm64 x86_64])
      assert_equal [['/fixture/archive', 'rb']], calls
    end
  end

  def test_owner_native_archive_census_rejects_raw_bitcode_unknown_nested_and_wrong_native_kind
    native = owner_symbol_native_object('arm64')
    cases = [
      ['raw bitcode', owner_symbol_native_archive('arm64', object_data: "BC\xc0\xde".b + "\0" * 28),
       'Archive member is not the exact architecture native Mach-O MH_OBJECT'],
      ['unknown body', owner_symbol_native_archive('arm64', object_data: 'unknown!' * 4),
       'Archive member is not the exact architecture native Mach-O MH_OBJECT'],
      ['nested archive', owner_symbol_native_archive('arm64', object_data: "!<arch>\n" + "\0" * 24),
       'Archive member is not the exact architecture native Mach-O MH_OBJECT'],
      ['unknown member', owner_symbol_native_archive('arm64', object_name: 'README.txt', object_data: native),
       'Non-native/unknown archive member'],
      ['truncated object', owner_symbol_native_archive('arm64', object_data: native.byteslice(0, 31)),
       'Non-native/unknown archive member'],
      ['other CPU', owner_symbol_native_archive('arm64', object_data: owner_symbol_native_object('x86_64')),
       'Archive member is not the exact architecture native Mach-O MH_OBJECT'],
      ['other CPU subtype', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 8, 1)),
       'Archive member is not the exact architecture native Mach-O MH_OBJECT'],
      ['non-object type', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 12, 2)),
       'Archive member is not the exact architecture native Mach-O MH_OBJECT'],
      ['nonzero reserved', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 28, 1)),
       'Archive member is not the exact architecture native Mach-O MH_OBJECT']
    ]
    cases.each { |name, bytes, diagnostic| owner_symbol_assert_archive_refusal(name, bytes, ['arm64'], diagnostic) }
  end

  def test_owner_native_archive_census_rejects_malformed_member_and_load_command_ranges
    archive = owner_symbol_native_archive('arm64')
    native = owner_symbol_native_object('arm64')
    cases = [
      ['member header truncated', "!<arch>\nshort", 'Archive member header truncated'],
      ['member terminator', owner_symbol_byte_edit(archive, 8 + 58, "!\n"), 'Archive member header terminator differs'],
      ['ordinary ar name', owner_symbol_byte_edit(archive, 8, 'fixture.o/'.ljust(16)),
       'Archive member must use the pinned BSD extended-name format'],
      ['nonnumeric size', owner_symbol_byte_edit(archive, 8 + 48, 'no'.ljust(10)),
       'Archive member must use the pinned BSD extended-name format'],
      ['member range', owner_symbol_byte_edit(archive, 8 + 48, '9999999999'), 'Archive member/name range invalid'],
      ['invalid member name', owner_symbol_native_archive('arm64', object_name: 'bad/path.o'), 'Archive member name invalid'],
      ['unaligned name payload', owner_symbol_byte_edit(archive, 8, '#1/11'.ljust(16)),
       'BSD archive name padding/native payload alignment differs'],
      ['eight or more name-padding bytes', "!<arch>\n" + owner_symbol_ar_member('__.SYMDEF', [0, 0].pack('V2'), name_size: 20),
       'BSD archive name padding/native payload alignment differs'],
      ['zero commands', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 16, 0)),
       'Mach-O load-command range invalid'],
      ['huge command bytes', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 20, 0xffff)),
       'Mach-O load-command range invalid'],
      ['missing second command', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 16, 2)),
       'Mach-O load command truncated'],
      ['unaligned command size', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 36, 23)),
       'Mach-O load-command size invalid'],
      ['short symtab command', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 36, 16)),
       'Mach-O native symbol command size differs'],
      ['no symtab command', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 32, 99)),
       'Mach-O native symbol inventory incomplete'],
      ['symbol range', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 44, 0xffff)),
       'Mach-O native symbol/string range invalid'],
      ['string overlap', owner_symbol_native_archive('arm64', object_data: owner_symbol_word_edit(native, 48, 56)),
       'Mach-O native symbol/string range invalid'],
      ['truncated string table', owner_symbol_native_archive('arm64', object_data: native.byteslice(0, native.bytesize - 1)),
       'Mach-O native symbol/string range invalid']
    ]
    cases.each { |name, bytes, diagnostic| owner_symbol_assert_archive_refusal(name, bytes, ['arm64'], diagnostic) }
  end

  def test_owner_native_archive_census_rejects_missing_duplicate_and_unbound_bsd_index
    native = owner_symbol_native_object('arm64')
    valid = owner_symbol_native_archive('arm64')
    strings = OWNER_SYMBOL_OFFICIAL + "\0"
    cases = [
      ['missing index', "!<arch>\n" + owner_symbol_ar_member('fixture.o', native),
       'Archive native member/index census incomplete'],
      ['missing object', "!<arch>\n" + owner_symbol_ar_member('__.SYMDEF', [0, 0].pack('V2')),
       'Archive native member/index census incomplete'],
      ['duplicate index', valid + owner_symbol_ar_member('__.SYMDEF', [0, 0].pack('V2')),
       'Archive index must be the single first pinned member'],
      ['late index', "!<arch>\n" + owner_symbol_ar_member('fixture.o', native) + owner_symbol_ar_member('__.SYMDEF', [0, 0].pack('V2')),
       'Archive index must be the single first pinned member'],
      ['partial ranlib record', owner_symbol_native_archive('arm64', index_data: [7].pack('V') + "\0" * 15),
       'Archive index entry range invalid'],
      ['ranlib range', owner_symbol_native_archive('arm64', index_data: [16, 0].pack('V2')),
       'Archive index entry range invalid'],
      ['non-native offset', owner_symbol_native_archive('arm64', index_data: [8, 0, 0, strings.bytesize].pack('V4') + strings),
       'Archive index binding is not a native member'],
      ['middle of symbol name', owner_symbol_native_archive('arm64', index_name_offset: 1),
       'Archive index binding is not a native member'],
      ['empty indexed name', owner_symbol_native_archive('arm64', index_strings: "\0"),
       'Archive index binding is not a native member'],
      ['unterminated name', owner_symbol_native_archive('arm64', index_strings: 'abc'),
       'Archive index binding is not a native member'],
      ['string range', owner_symbol_native_archive('arm64', index_data: [8, 0, 0, 99].pack('V4') + "a\0"),
       'Archive index string/padding range invalid'],
      ['nonzero index padding', owner_symbol_native_archive('arm64', index_padding: "\1"),
       'Archive index string/padding range invalid'],
      ['eight bytes index padding', owner_symbol_native_archive('arm64', index_padding: "\0" * 8),
       'Archive index string/padding range invalid']
    ]
    cases.each { |name, bytes, diagnostic| owner_symbol_assert_archive_refusal(name, bytes, ['arm64'], diagnostic) }
  end

  def test_owner_symbol_artifact_smoke_false_rejects_non_native_members_before_nm_or_pinned_tools
    fixture = owner_symbol_artifact_fixture
    first = owner_symbol_archives(fixture).keys.first
    fixture.fetch(:files)[first] = owner_symbol_native_archive('arm64', object_data: "BC\xc0\xde".b + "\0" * 28)
    owner_symbol_reseal_artifact_input(fixture)
    capture_io do
      owner_symbol_artifact_doubles(fixture) do
        error = assert_raises(RuntimeError) { OWNER_SYMBOL_ARTIFACT.verify!(fixture.fetch(:artifact), smoke: false) }
        assert_equal 'Archive member is not the exact architecture native Mach-O MH_OBJECT', error.message
      end
    end
    assert_equal [first], fixture.fetch(:archives_seen)
    assert_empty fixture.fetch(:executables_seen)
    assert_empty fixture.fetch(:mkdir_seen)
    assert_empty fixture.fetch(:calls).select { |call| call.fetch(:argv)[1] == 'nm' }
    assert_equal 0, fixture.fetch(:native_runs)
  end

  def test_owner_native_archive_census_rejects_fat_subtype_alignment_overlap_and_wrong_inner_cpu
    fat = owner_symbol_fat_archive
    arm_offset = 48 + owner_symbol_native_archive('x86_64').bytesize
    cases = [
      ['fat descriptors truncated', fat.byteslice(0, 47), 'Fat archive descriptor truncated'],
      ['fat count', owner_symbol_byte_edit(fat, 4, [1].pack('N')),
       'Simulator main binary is not the reviewed two-architecture fat archive'],
      ['duplicate CPU', owner_symbol_byte_edit(fat, 28, [0x01000007].pack('N')), 'Fat archive CPU types differ'],
      ['overlap', owner_symbol_byte_edit(fat, 36, [48].pack('N')), 'Fat archive slices overlap'],
      ['x86 subtype', owner_symbol_byte_edit(fat, 12, [0].pack('N')), 'Fat archive subtype/alignment differs'],
      ['alignment exponent', owner_symbol_byte_edit(fat, 24, [32].pack('N')), 'Fat archive subtype/alignment differs'],
      ['unaligned second offset', owner_symbol_byte_edit(fat, 36, [arm_offset + 1].pack('N')),
       'Fat archive subtype/alignment differs'],
      ['short second slice', owner_symbol_byte_edit(fat, 40, [7].pack('N')), 'Fat archive range invalid'],
      ['huge second slice', owner_symbol_byte_edit(fat, 40, [0xffff_ffff].pack('N')), 'Fat archive range invalid'],
      ['unknown second slice', owner_symbol_byte_edit(fat, arm_offset, 'unknown!'), 'Simulator slice is not a static archive'],
      ['wrong second native CPU', owner_symbol_byte_edit(fat, arm_offset + 224 + 4, [0x01000007].pack('V')),
       'Archive member is not the exact architecture native Mach-O MH_OBJECT']
    ]
    cases.each { |name, bytes, diagnostic| owner_symbol_assert_archive_refusal(name, bytes, %w[arm64 x86_64], diagnostic) }
  end

  private

  # Handwritten BSD archive and native object inputs. No production constructor,
  # parser, symbol command, or manifest verifier supplies expected values.
  def owner_symbol_native_object(architecture)
    cpu = { 'arm64' => 0x0100000c, 'x86_64' => 0x01000007 }.fetch(architecture)
    subtype = { 'arm64' => 0, 'x86_64' => 3 }.fetch(architecture)
    strings = "\0#{OWNER_SYMBOL_OFFICIAL}\0".b
    [0xfeedfacf, cpu, subtype, 1, 1, 24, 0, 0].pack('V8') +
      [2, 24, 56, 1, 72, strings.bytesize].pack('V6') +
      [1, 0x0f, 1, 0, 0].pack('VCCvQ<') + strings
  end

  def owner_symbol_ar_member(name, data, name_size: nil)
    name_size ||= ((name.bytesize + 3) / 4) * 4
    name_bytes = name.b + "\0" * (name_size - name.bytesize)
    length = name_bytes.bytesize + data.bytesize
    header = "#1/#{name_bytes.bytesize}".ljust(16) + '0'.ljust(12) + '0'.ljust(6) +
      '0'.ljust(6) + '100644'.ljust(8) + length.to_s.ljust(10) + "`\n"
    header.b + name_bytes + data + (length.odd? ? "\n" : '')
  end

  def owner_symbol_native_archive(architecture, object_data: nil, object_name: 'fixture.o',
                                  index_data: nil, index_name_offset: 0,
                                  index_strings: OWNER_SYMBOL_OFFICIAL + "\0", index_padding: nil)
    object_data ||= owner_symbol_native_object(architecture)
    raw_index = index_data || [8, index_name_offset, 0, index_strings.bytesize].pack('V4') + index_strings
    padding = index_padding || "\0" * ((8 - raw_index.bytesize % 8) % 8)
    index_placeholder = raw_index + padding
    object_offset = 8 + owner_symbol_ar_member('__.SYMDEF', index_placeholder).bytesize
    actual_index = (index_data || [8, index_name_offset, object_offset, index_strings.bytesize].pack('V4') + index_strings) + padding
    "!<arch>\n" + owner_symbol_ar_member('__.SYMDEF', actual_index) + owner_symbol_ar_member(object_name, object_data)
  end

  def owner_symbol_fat_archive
    x86 = owner_symbol_native_archive('x86_64')
    arm = owner_symbol_native_archive('arm64')
    "\xca\xfe\xba\xbe".b + [2].pack('N') +
      [0x01000007, 3, 48, x86.bytesize, 3,
       0x0100000c, 0, 48 + x86.bytesize, arm.bytesize, 3].pack('N10') + x86 + arm
  end

  def owner_symbol_word_edit(bytes, offset, word)
    owner_symbol_byte_edit(bytes, offset, [word].pack('V'))
  end

  def owner_symbol_byte_edit(bytes, offset, replacement)
    edited = bytes.dup
    edited[offset, replacement.bytesize] = replacement
    edited
  end

  def owner_symbol_archive_input_double(bytes)
    before = bytes.dup
    calls = []
    open = lambda do |path, mode, &block|
      assert_equal ['/fixture/archive', 'rb'], [path, mode]
      calls << [path, mode]
      io = StringIO.new(bytes)
      io.define_singleton_method(:stat) { OwnerSymbolFileStat.new(bytes.bytesize) }
      block.call(io)
    ensure
      io.close if io
    end
    Open3.stub(:capture3, ->(*_args, **_options) { flunk 'Native capture forbidden in archive byte fixtures' }) do
      Open3.stub(:popen2e, ->(*_args, **_options) { flunk 'Native run forbidden in archive byte fixtures' }) do
        File.stub(:open, open) { yield calls }
      end
    end
    assert_equal before, bytes, 'Archive input bytes changed'
  end

  def owner_symbol_assert_archive_refusal(name, bytes, architectures, diagnostic)
    owner_symbol_archive_input_double(bytes) do |calls|
      error = assert_raises(RuntimeError, name) do
        OWNER_SYMBOL_ARTIFACT.verify_static_archive!('/fixture/archive', architectures)
      end
      assert_equal diagnostic, error.message, name
      assert_equal [['/fixture/archive', 'rb']], calls, name
    end
  end

  def owner_symbol_expected_nm_calls(library, architectures, environment)
    architectures.map { |architecture| {
      argv: ['/usr/bin/xcrun', 'nm', '--no-llvm-bc', '-arch', architecture, '-g', '-U', '-j', library],
      env: environment, chdir: OWNER_SYMBOL_ARTIFACT::CRATE
    } }
  end

  def owner_symbol_nm_double(outputs, environment, failure: nil)
    calls = []
    capture = lambda do |actual_environment, *argv, chdir:|
      architecture = argv.fetch(4)
      assert_equal owner_symbol_expected_nm_calls('/fixture/archive', [architecture], environment).first,
                   { argv: argv, env: actual_environment, chdir: chdir }
      assert_same environment, actual_environment
      calls << { argv: argv, env: actual_environment, chdir: chdir }
      output = outputs.fetch(architecture)
      [output, failure.to_s, OwnerSymbolCommandStatus.new(failure.nil?, failure ? 17 : 0)]
    end
    Open3.stub(:capture3, capture) do
      Open3.stub(:popen2e, ->(*_args, **_options) { flunk 'Unexpected real native run' }) { yield calls }
    end
  end

  def owner_symbol_archives(fixture)
    artifact = fixture.fetch(:artifact)
    {
      File.join(artifact, 'macos-arm64/BelugaCore.framework/BelugaCore') => ['arm64'],
      File.join(artifact, 'ios-arm64/BelugaCore.framework/BelugaCore') => ['arm64'],
      File.join(artifact, 'ios-arm64_x86_64-simulator/BelugaCore.framework/BelugaCore') => %w[arm64 x86_64]
    }
  end

  def owner_symbol_all_archive_nm_calls(fixture)
    owner_symbol_archives(fixture).flat_map do |library, architectures|
      owner_symbol_expected_nm_calls(library, architectures, fixture.fetch(:environment))
    end
  end

  def owner_symbol_input_manifest(root, names, files)
    names.sort.map { |name| "#{Digest::SHA256.hexdigest(files.fetch(File.join(root, name)))}  #{name}\n" }.join
  end

  def owner_symbol_reseal_artifact_input(fixture)
    root = fixture.fetch(:artifact)
    fixture.fetch(:files)[File.join(root, 'ARTIFACT_MANIFEST.sha256')] =
      owner_symbol_input_manifest(root, OWNER_SYMBOL_ARTIFACT::ARTIFACT_FILES, fixture.fetch(:files))
  end

  def owner_symbol_artifact_fixture
    a = OWNER_SYMBOL_ARTIFACT
    artifact = '/fixture/BelugaCore.xcframework'
    files = a::SOURCE_FILES.to_h { |name| [File.join(a::CRATE, name), "fixture source #{name}\n"] }
    files[File.join(a::CRATE, 'SOURCE_MANIFEST.sha256')] = owner_symbol_input_manifest(a::CRATE, a::SOURCE_FILES, files)
    framework_info = {
      'CFBundleExecutable' => 'BelugaCore', 'CFBundleIdentifier' => 'com.elamin.beluga.core',
      'CFBundleInfoDictionaryVersion' => '6.0', 'CFBundleName' => 'BelugaCore',
      'CFBundlePackageType' => 'FMWK', 'CFBundleShortVersionString' => '0.1.0', 'CFBundleVersion' => '1'
    }
    %w[macos-arm64 ios-arm64 ios-arm64_x86_64-simulator].each do |slice|
      platform = { 'macos-arm64' => 'MacOSX', 'ios-arm64' => 'iPhoneOS', 'ios-arm64_x86_64-simulator' => 'iPhoneSimulator' }.fetch(slice)
      info = framework_info.merge('CFBundleSupportedPlatforms' => [platform],
        (slice == 'macos-arm64' ? 'LSMinimumSystemVersion' : 'MinimumOSVersion') => (slice == 'macos-arm64' ? '13.0' : '16.0'))
      files[File.join(artifact, slice, 'BelugaCore.framework/Info.plist')] = JSON.generate(info)
      files[File.join(artifact, slice, 'BelugaCore.framework/Headers/beluga_core.h')] = files.fetch(File.join(a::CRATE, 'include/beluga_core.h'))
      files[File.join(artifact, slice, 'BelugaCore.framework/Modules/module.modulemap')] = files.fetch(File.join(a::CRATE, 'include/module.modulemap'))
    end
    libraries = [
      { 'LibraryIdentifier' => 'macos-arm64', 'SupportedArchitectures' => ['arm64'], 'SupportedPlatform' => 'macos' },
      { 'LibraryIdentifier' => 'ios-arm64', 'SupportedArchitectures' => ['arm64'], 'SupportedPlatform' => 'ios' },
      { 'LibraryIdentifier' => 'ios-arm64_x86_64-simulator', 'SupportedArchitectures' => %w[arm64 x86_64], 'SupportedPlatform' => 'ios', 'SupportedPlatformVariant' => 'simulator' }
    ].map { |entry| entry.merge('BinaryPath' => 'BelugaCore.framework/BelugaCore', 'LibraryPath' => 'BelugaCore.framework') }
    files[File.join(artifact, 'Info.plist')] = JSON.generate('AvailableLibraries' => libraries,
      'CFBundlePackageType' => 'XFWK', 'XCFrameworkFormatVersion' => '1.0')
    %w[SOURCE_MANIFEST.sha256 THIRD_PARTY_NOTICES.html].each { |name| files[File.join(artifact, name)] = files.fetch(File.join(a::CRATE, name)) }
    rust_version = "rustc 1.97.1 fixture\nrelease: 1.97.1\nhost: aarch64-apple-darwin\n"
    xcode_version = "Xcode 26.6\nBuild version 17F113\n"
    target_names = %w[aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios]
    files[File.join(artifact, 'BUILD_METADATA.txt')] =
      "rust-toolchain=1.97.1\npackaging-profile=static-framework-v1\n" +
      target_names.map { |target| "supported-target=#{target}\n" }.join +
      "supported-architecture=arm64\nsimulator-architectures=arm64,x86_64\nabi-version=1\n" +
      rust_version + xcode_version + "macos-sdk=26.6\niphoneos-sdk=26.6\niphonesimulator-sdk=26.6\n"
    environment = {
      'RUSTUP_HOME' => a::RUSTUP, 'CARGO_HOME' => a::CARGO_HOME_PATH,
      'RUSTUP_TOOLCHAIN' => '1.97.1', 'CARGO_TARGET_DIR' => File.join(a::CRATE, 'target/cargo'),
      'RUSTC' => a::RUSTC, 'DEVELOPER_DIR' => a::DEVELOPER, 'LC_ALL' => 'C'
    }
    fixture = { artifact: artifact, files: files, environment: environment, calls: [], walks_seen: [],
      archives_seen: [], mkdir_seen: [], scratch_seen: [], executables_seen: [], native_runs: 0 }
    fixture[:walks] = { a::CRATE => a::SOURCE_FILES.map { |name| File.join(a::CRATE, name) } + [File.join(a::CRATE, 'SOURCE_MANIFEST.sha256')],
                       artifact => a::ARTIFACT_FILES.map { |name| File.join(artifact, name) } + [File.join(artifact, 'ARTIFACT_MANIFEST.sha256')] }
    fixture[:executables] = [a::CARGO, a::RUSTC, "#{a::DEVELOPER}/usr/bin/xcodebuild",
      "#{a::DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang",
      "#{a::DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"]
    fixture[:directories] = [a::CRATE, artifact, File.join(a::CRATE, 'target')] +
      target_names.map { |target| File.join(a::TOOLCHAIN, 'lib/rustlib', target, 'lib') }
    fixture[:responses] = {
      [a::RUSTC, '--version', '--verbose'] => rust_version,
      [a::RUSTC, '--print', 'sysroot'] => "#{a::TOOLCHAIN}\n",
      ["#{a::DEVELOPER}/usr/bin/xcodebuild", '-version'] => xcode_version
    }
    %w[macosx iphoneos iphonesimulator].each { |sdk| fixture[:responses][['/usr/bin/xcrun', '--sdk', sdk, '--show-sdk-version']] = "26.6\n" }
    owner_symbol_archives(fixture).each do |library, architectures|
      if architectures.length == 1
        files[library] = owner_symbol_native_archive(architectures.first)
      else
        files[library] = owner_symbol_fat_archive
      end
      fixture[:responses][['/usr/bin/lipo', '-archs', library]] = architectures.join(' ') + "\n"
    end
    fixture[:symbols] = owner_symbol_archives(fixture).flat_map { |library, architectures|
      architectures.map { |arch| [[library, arch], OWNER_SYMBOL_OFFICIAL_NAMES.join("\n") + "\n"] }
    }.to_h
    owner_symbol_reseal_artifact_input(fixture)
    fixture
  end

  # Serialized offline suite: restore every overridden method even after refusal.
  # The real source/manifests/tool/shape/symbol methods are never replaced.
  def owner_symbol_artifact_doubles(fixture)
    a = OWNER_SYMBOL_ARTIFACT
    files = fixture.fetch(:files)
    capture = lambda do |environment, *argv, chdir:|
      assert_equal a::CRATE, chdir
      fixture.fetch(:calls) << { argv: argv, env: environment.dup, chdir: chdir }
      response = if argv[0,2] == ['/usr/bin/xcrun', 'nm']
        assert_equal ['/usr/bin/xcrun', 'nm', '--no-llvm-bc', '-arch', argv.fetch(4), '-g', '-U', '-j', argv.fetch(8)], argv
        assert_equal fixture.fetch(:environment), environment
        fixture.fetch(:symbols).fetch([argv.fetch(8), argv.fetch(4)])
      elsif argv[0,5] == ['/usr/bin/plutil', '-convert', 'json', '-o', '-']
        assert_equal({}, environment)
        files.fetch(argv.fetch(5))
      else
        expected = argv.first == '/usr/bin/lipo' ? {} : fixture.fetch(:environment)
        assert_equal expected, environment
        fixture.fetch(:responses).fetch(argv)
      end
      [response, '', OwnerSymbolCommandStatus.new(true, 0)]
    end
    open = lambda do |path, mode, &block|
      assert_equal 'rb', mode
      assert owner_symbol_archives(fixture).key?(path), path
      fixture.fetch(:archives_seen) << path
      bytes = files.fetch(path)
      io = StringIO.new(bytes)
      io.define_singleton_method(:stat) { OwnerSymbolFileStat.new(bytes.bytesize) }
      block.call(io)
    ensure
      io.close if io
    end
    known = lambda { |path| files.key?(path) || fixture.fetch(:directories).include?(path) }
    overrides = [
      [Open3, :capture3, capture],
      [Open3, :popen2e, lambda { |*_args, **_options| fixture[:native_runs] += 1; flunk 'Unexpected native tool execution' }],
      [File, :binread, ->(path) { files.fetch(path) }],
      [File, :directory?, ->(path) { assert known.call(path), path; fixture.fetch(:directories).include?(path) }],
      [File, :file?, ->(path) { assert known.call(path), path; files.key?(path) }],
      [File, :symlink?, ->(path) { assert known.call(path), path; false }],
      [File, :executable?, lambda { |path| fixture.fetch(:executables_seen) << path; fixture.fetch(:executables).include?(path) }],
      [File, :open, open],
      [Digest::SHA256, :file, ->(path) { Digest::SHA256.new.update(files.fetch(path)) }],
      [Find, :find, lambda { |root, &block| fixture.fetch(:walks_seen) << root; block.call(root); fixture.fetch(:walks).fetch(root).each(&block) }],
      [FileUtils, :mkdir_p, lambda { |path| assert_equal File.join(a::CRATE, 'target'), path; fixture.fetch(:mkdir_seen) << path; [path] }],
      [Dir, :mktmpdir, lambda { |prefix, parent, &block|
        assert_equal ['verify-', File.join(a::CRATE, 'target')], [prefix, parent]
        fixture.fetch(:scratch_seen) << [prefix, parent]
        block.call('/fixture/private-verify-scratch')
      }]
    ]
    installed = []
    overrides.each do |receiver, method, implementation|
      original = receiver.method(method)
      # Preserve the fixture closure's test-instance receiver. Installing the
      # Proc as a method directly would rebind self to File/Open3/etc.
      receiver.define_singleton_method(method) do |*arguments, **options, &block|
        if options.empty?
          implementation.call(*arguments, &block)
        else
          implementation.call(*arguments, **options, &block)
        end
      end
      installed << [receiver, method, original]
    end
    yield
  ensure
    installed&.reverse_each { |receiver, method, original| receiver.define_singleton_method(method, original) }
  end
end
