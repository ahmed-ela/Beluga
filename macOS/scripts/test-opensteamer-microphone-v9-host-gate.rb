# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative 'opensteamer-microphone-v9-host-gate'
require_relative 'opensteamer-microphone-v9-transaction-contract'

Gate = BelugaMicrophoneV9HostGate
ProductRoot = '/Volumes/t7/beluga-quality-step.idpzQO/source/macOS/scripts'
# Only immutable source and private fixtures are consulted. No gate, helper,
# live process, route, launchd or CoreAudio command is executed by these tests.
Gate::PRODUCT_PINS.each do |name, sha|
  raise 'original product source pin changed' unless Digest::SHA256.file(ProductRoot + '/' + name).hexdigest == sha
end
require ProductRoot + '/opensteamer-host-v91-cutover-controller'
require ProductRoot + '/opensteamer-host-successor-contract'
Legacy = OpenSteamerV91Cutover
# Construct the real contract from its already-approved artifact records only;
# this performs no live host query and never invokes the product CLI.
Legacy::Pins.bind_contract!(OpenSteamerHostSuccessor::ReleaseContract.new(Gate::PROFILE, Gate::PROFILE_SHA))

class MicrophoneV9HostGateTests < Minitest::Test
  def request
    contract = OpensteamerMicrophoneV9TransactionContract
    value = Gate::REQUEST_KEYS.to_h { |key| [key, 'a' * 64] }.merge(contract::FIXED)
    value.merge!('namespace' => 'driver-microphone-v9-fixture', 'nonce' => 'b' * 64,
                 'host_nonce' => 'c' * 64, 'host_pid' => '12', 'host_lock_device' => '2', 'host_lock_inode' => '3',
                 'host_launchd_runs' => '1', 'host_display_identity_sha256' => 'd' * 64,
                 'guard_tooling_root' => '/private/fixture', 'artifact_root' => contract::ARTIFACT_ROOT,
                 'committed_host_pointer_path' => Gate::POINTER,
                 'committed_host_result_path' => Gate::HISTORY + '/attempt/result.txt',
                 'committed_host_readiness_path' => Gate::HISTORY + '/attempt/commit-safety-proof.txt',
                 'committed_host_journal_path' => Gate::HISTORY + '/attempt/journal.log')
    value
  end

  def text(value)
    Gate::REQUEST_KEYS.map { |key| "#{key}=#{value.fetch(key)}\n" }.join
  end

  def parsed(value)
    bytes = text(value); Gate.request!(bytes, Digest::SHA256.hexdigest(bytes))
  end

  def test_strict_actual_wire_request_and_mutations
    value = request
    assert_equal value, parsed(value)
    Gate::REQUEST_KEYS.each do |key|
      mutant = value.reject { |name, _| name == key }
      bytes = mutant.map { |name, item| "#{name}=#{item}\n" }.join
      assert_raises(Gate::Refused) { Gate.request!(bytes, Digest::SHA256.hexdigest(bytes)) }
    end
    bytes = text(value)
    [bytes + "unknown=1\n", bytes + "nonce=#{value['nonce']}\n", bytes.sub("\n", "\r\n"), bytes.delete_suffix("\n"),
     bytes.sub('driver-microphone-v9-fixture', 'driver-microphone-v9--fixture'), bytes.sub('caller_uid=501', 'caller_uid=0'),
     bytes.sub('host_pid=12', 'host_pid=01'), bytes.sub('host_pid=12', 'host_pid=2147483648'),
     bytes.sub('host_nonce=' + 'c' * 64, 'host_nonce=' + 'b' * 64), bytes.sub('namespace=', "namespace=é"),
     bytes.sub('input_uid=BlackHole2ch_UID', 'input_uid=other'), bytes.sub('schema=', 'schema=extra=')].each do |mutant|
      assert_raises(Gate::Refused) { Gate.request!(mutant, Digest::SHA256.hexdigest(mutant)) }
    end
    assert_raises(Gate::Refused) { Gate.request!(bytes, 'f' * 64) }
    (Gate::BYTE_PINS.keys + %w[host_profile_path host_profile_sha256 committed_host_pointer_path]).each do |key|
      mutant = value.merge(key => key.end_with?('_path') ? '/private/other' : 'f' * 64)
      assert_raises(Gate::Refused) { parsed(mutant) }
    end
  end

  def test_exact_routes_reject_mutants_but_allow_new_generation_device_ids
    %w[61 102 9001].each do |id|
      assert_equal id, Gate.route!(JSON.generate('id' => id, 'name' => 'BlackHole 2ch', 'type' => 'input', 'uid' => 'BlackHole2ch_UID'), 'input')['id']
    end
    base = { 'id' => '61', 'name' => 'BlackHole 2ch', 'type' => 'input', 'uid' => 'BlackHole2ch_UID' }
    [base.merge('uid' => 'writer'), base.merge('type' => 'output'), base.merge('id' => '0'), base.merge('id' => '01'),
     base.merge('id' => '4294967296'), base.merge('id' => 61), base.merge('name' => "unsafe\nname"),
     base.merge('extra' => true), base.reject { |key, _| key == 'uid' }].each do |mutant|
      assert_raises(Gate::Refused) { Gate.route!(JSON.generate(mutant), 'input') }
    end
    assert_raises(Gate::Refused) { Gate.route!(JSON.generate(base).sub('{', '{"id":"1",'), 'input') }
    routes = Gate::ROUTES.to_h { |type, uid| [type, { 'uid' => uid }] }
    assert_equal 'a886324e0a43c445000b7e61c66fc932b8ef8b455189d9a46c163395298f1ec8', Gate.routes_fingerprint(routes)
    refute_equal Gate.routes_fingerprint(routes), Digest::SHA256.hexdigest(Gate::ROUTES.values.join)
    refute_equal Gate.routes_fingerprint(routes), Digest::SHA256.hexdigest(Gate::ROUTES.values.join("\n"))
  end

  def baseline
    value = Gate::OUTPUT_KEYS.to_h { |key| [key, 'true'] }
    req = request
    value.merge!('schema' => Gate::SCHEMA, 'mode' => 'candidate-present', 'namespace' => req['namespace'], 'nonce' => req['nonce'],
                 'committed_host_terminal' => 'COMMITTED_CANDIDATE', 'session_log_device' => '2', 'session_log_inode' => '3',
                 'session_log_size' => '1000', 'session_log_reset_offset' => '100', 'session_log_sha256' => 'e' * 64, 'session_log_tail_sha256' => 'f' * 64,
                 'display_headless' => 'false', 'observed_at_unix_ms' => '1790812800000', 'manager_generation' => '0',
                 'input_uid' => Gate::ROUTES['input'], 'output_uid' => Gate::ROUTES['output'], 'system_output_uid' => Gate::ROUTES['system'],
                 'routes_identity_sha256' => Digest::SHA256.hexdigest(Gate::ROUTES.values.join("\0")))
    value.merge!(Gate::BYTE_PINS)
    %w[pid launchd_runs start_identity_sha256 nonce lock_device lock_inode display_identity_sha256].each { |key| value['host_' + key] = req['host_' + key] }
    value
  end

  def baseline_text(value)
    Gate::OUTPUT_KEYS.map { |key| "#{key}=#{value.fetch(key)}\n" }.join
  end

  def test_baseline_is_nonce_and_original_generation_bound
    value = baseline
    assert_equal value, Gate.baseline!(baseline_text(value), request)
    %w[schema mode namespace nonce host_pid host_launchd_runs host_start_identity_sha256 host_nonce host_lock_device host_lock_inode host_display_identity_sha256 readiness host_present session_quiescent committed_host_terminal session_log_sha256 session_log_tail_sha256].each do |key|
      mutant = value.merge(key => 'wrong')
      assert_raises(Gate::Refused) { Gate.baseline!(baseline_text(mutant), request) }
    end
    assert_raises(Gate::Refused) { Gate.baseline!(baseline_text(value.merge('session_log_reset_offset' => '1000')), request) }
    assert_raises(Gate::Refused) { Gate.baseline!(baseline_text(value.merge('session_log_size' => '0')), request) }
    %w[observed_at_unix_ms manager_generation input_uid output_uid system_output_uid routes_identity_sha256 display_headless host_executable_sha256 host_framework_sha256 host_info_plist_sha256 host_launch_plist_sha256].each do |key|
      assert_raises(Gate::Refused) { Gate.baseline!(baseline_text(value.merge(key => 'wrong')), request) }
    end
  end

  def test_absence_uses_only_the_exact_sentinel_shape
    value = baseline.merge('mode' => 'host-absent', 'host_present' => 'false', 'readiness' => 'false', 'display_headless' => 'true',
      'host_pid' => '0', 'host_launchd_runs' => '0', 'host_start_identity_sha256' => 'none', 'host_nonce' => 'none',
      'host_lock_device' => '0', 'host_lock_inode' => '0', 'host_display_identity_sha256' => 'none', 'manager_generation' => 'none')
    assert_equal value, Gate.output!(value, request)
    %w[host_present readiness display_headless host_pid host_launchd_runs host_start_identity_sha256 host_nonce host_lock_device host_lock_inode host_display_identity_sha256 manager_generation].each do |key|
      assert_raises(Gate::Refused) { Gate.output!(value.merge(key => 'wrong'), request) }
    end
  end

  def test_retained_ready_channel_preserves_original_fence_and_exact_new_generation
    original = baseline
    ready = original.merge('mode' => 'host-ready', 'host_pid' => '13', 'host_nonce' => 'f' * 64,
      'session_log_size' => '1500', 'session_log_reset_offset' => '1000')
    assert_equal ready, Gate.ready_baseline!(baseline_text(ready), request, original)
    %w[mode host_pid host_nonce host_launchd_runs host_display_identity_sha256 session_log_device session_log_inode].each do |key|
      mutant = ready.merge(key => original[key])
      # The mode and original PID/nonce are invalid; inode fields use another
      # concrete identity, since the proper retained inode equals the original.
      mutant[key] = '99' if %w[session_log_device session_log_inode host_launchd_runs].include?(key)
      mutant[key] = 'a' * 64 if key == 'host_display_identity_sha256'
      assert_raises(Gate::Refused) { Gate.ready_baseline!(baseline_text(mutant), request, original) }
    end
    assert_raises(Gate::Refused) { Gate.ready_baseline!(baseline_text(ready.merge('session_log_reset_offset' => '999')), request, original) }
    assert_raises(Gate::Refused) { Gate.ready_baseline!(baseline_text(ready.merge('session_log_size' => '999')), request, original) }
    assert_nil Gate.optional_fd!(100_000)
  end

  def journal
    Legacy::Pins.fetch(:V91_JOURNAL_HEADER) + "\n" + Legacy::RealHost::SUCCESS_STATES.map do |state|
      "2026-10-01T00:00:00Z STATE #{Legacy::Pins.state_out(state)}\n"
    end.join
  end

  def committed_records
    req = request
    common = "pid=#{req['host_pid']}\nnonce=#{req['host_nonce']}\ntarget=candidate\nselected=1080x1920@1080x1920 60.00Hz\ncandidate_executable_sha256=#{req['host_executable_sha256']}\npayload_manifest_sha256=#{req['host_payload_sha256']}\nhandoff_sha256=#{req['host_handoff_sha256']}\n"
    {
      Gate::POINTER => Gate::HISTORY + "/attempt\n",
      req['committed_host_result_path'] => "result=pending-terminal\nterminal_required=CANDIDATE_COMMIT_IRREVERSIBLE,COMMITTED_CANDIDATE\n" + common,
      req['committed_host_readiness_path'] => "result=success-pending-terminal\nterminal_required=COMMITTED_CANDIDATE\npoint_of_no_return=CANDIDATE_COMMIT_IRREVERSIBLE\n" + common +
        "route_monitor=RESULT notifications=0 teardown=clean input=BlackHole2ch_UID output=BuiltInSpeakerDevice system=BuiltInSpeakerDevice\n",
      req['committed_host_journal_path'] => journal
    }
  end

  def check_commit(records, req = request)
    reader = lambda { |path, _sha, **_options| [records.fetch(path), ['fixture-read-only']] }
    directory = Object.new
    Gate.stub(:identity, ['fixture-directory']) do
      Legacy::Util.stub(:directory!, directory) do
        Gate.stub(:read_file!, reader) { Gate.committed!(req, Legacy::RealHost.new) }
      end
    end
  end

  def test_commit_requires_actual_terminal_not_result_label
    records = committed_records
    assert_equal records[Gate::POINTER], check_commit(records).first
    journal_path = request['committed_host_journal_path']
    [journal.delete_suffix("2026-10-01T00:00:00Z STATE COMMITTED_CANDIDATE\n"), journal + "2026-10-01T00:00:00Z STATE COMMITTED_CANDIDATE_UNVERIFIED\n",
     journal.sub("STATE READY_VERIFIED", "STATE COMMITTED_CANDIDATE"), journal.sub("\n", "\r\n"), journal.delete_suffix("\n")].each do |mutant|
      assert_raises(StandardError) { check_commit(records.merge(journal_path => mutant)) }
    end
  end

  def test_committed_crosslinks_routes_and_all_record_fields_are_exact
    records = committed_records
    result_path = request['committed_host_result_path']; readiness_path = request['committed_host_readiness_path']
    [records[result_path] + "pid=12\n", records[result_path].sub('pid=12', 'pid=13'), records[result_path].sub('target=candidate', 'target=v91'),
     records[result_path].sub('result=pending-terminal', 'result=success'), records[result_path].sub('nonce=' + 'c' * 64, 'nonce=' + 'e' * 64)].each do |mutant|
      assert_raises(Gate::Refused) { check_commit(records.merge(result_path => mutant)) }
    end
    assert_raises(Gate::Refused) { check_commit(records.merge(readiness_path => records[readiness_path].sub('notifications=0', 'notifications=1'))) }
    assert_raises(Gate::Refused) { check_commit(records, request.merge('committed_host_result_path' => Gate::HISTORY + '/other/result.txt')) }
    assert_raises(Gate::Refused) { check_commit(records.merge(Gate::POINTER => Gate::HISTORY + "/attempt/child\n")) }
  end

  def test_real_product_session_fence_requires_fresh_post_baseline_boundary
    Dir.mktmpdir('microphone-v9-gate-log.') do |directory|
      path = directory + '/host.log'; old_nonce = 'c' * 64; new_nonce = 'e' * 64
      old = "Worldwide availability is waiting for the paired iPhone\nWorldwide paired-device availability is online pid=12 nonce=#{old_nonce}\n"
      File.write(path, old); File.chmod(0600, path)
      prior = Legacy::SessionFence.observe!(path, 12, old_nonce)
      File.write(path, old + "Worldwide paired-device availability is online pid=13 nonce=#{new_nonce}\n")
      assert_raises(Legacy::Failure) { Legacy::SessionFence.observe!(path, 13, new_nonce, prior: prior, fresh_generation: true) }
      fresh = old + "Worldwide availability is waiting for the paired iPhone\nWorldwide paired-device availability is online pid=13 nonce=#{new_nonce}\n"
      File.write(path, fresh)
      accepted = Legacy::SessionFence.observe!(path, 13, new_nonce, prior: prior, fresh_generation: true)
      assert accepted.last_reset_offset >= prior.size
      # After stopping the new host, retaining only the original generation is
      # not enough; the owned ready fence keeps both historical byte prefixes.
      assert_raises(Legacy::Failure) { Legacy::SessionFence.observe!(path, 12, old_nonce, prior: prior) }
      stable = Legacy::SessionFence.observe!(path, 13, new_nonce, prior: accepted)
      assert_equal accepted.last_reset_offset, stable.last_reset_offset
      assert_equal accepted.digest, stable.digest
      Legacy::SessionFence::UNSAFE_MARKERS.each do |marker|
        File.write(path, fresh + marker + "\n")
        assert_raises(Legacy::Failure) { Legacy::SessionFence.observe!(path, 13, new_nonce, prior: accepted) }
      end
      File.write(path, fresh.sub('paired iPhone', 'paired iPhonf'))
      assert_raises(Legacy::Failure) { Legacy::SessionFence.observe!(path, 13, new_nonce, prior: prior, fresh_generation: true) }
    end
  end

  def test_bounded_generation_tail_preserves_original_disconnect_and_absent_recovery_semantics
    Dir.mktmpdir('microphone-v9-tail.') do |directory|
      path = directory + '/host.log'; nonce = 'c' * 64; next_nonce = 'd' * 64
      # The original generation may go online before the last disconnect reset.
      # This remains genuine quiescence: only fresh ready generations require
      # their availability marker after their new reset.
      old = "historical-prefix\nWorldwide paired-device availability is online pid=12 nonce=#{nonce}\nWorldwide viewer disconnected\n"
      File.write(path, old); File.chmod(0600, path)
      original = Legacy::SessionFence.observe!(path, 12, nonce)
      expected = old.byteslice(original.last_reset_offset, original.size - original.last_reset_offset)
      assert_equal Digest::SHA256.hexdigest(expected), Gate.session_tail_sha256!(path, original)
      assert_equal original.digest, Legacy::SessionFence.observe!(path, 12, nonce, prior: original).digest
      File.write(path, old + "append beyond captured extent\n")
      assert_equal Digest::SHA256.hexdigest(expected), Gate.session_tail_sha256!(path, original)
      fresh = File.read(path) + "Worldwide peer returned to idle\nWorldwide paired-device availability is online pid=13 nonce=#{next_nonce}\n"
      File.write(path, fresh)
      ready = Legacy::SessionFence.observe!(path, 13, next_nonce, prior: original, fresh_generation: true)
      assert ready.last_reset_offset >= original.size
      assert_equal Digest::SHA256.hexdigest(fresh.byteslice(ready.last_reset_offset, ready.size - ready.last_reset_offset)), Gate.session_tail_sha256!(path, ready)
      # Owned stop/absence retains the exact ready generation, not the original.
      assert_equal ready.digest, Legacy::SessionFence.observe!(path, 13, next_nonce, prior: ready).digest
      assert_raises(Legacy::Failure) { Legacy::SessionFence.observe!(path, 12, nonce, prior: original) }
      Legacy::SessionFence::UNSAFE_MARKERS.each do |marker|
        File.write(path, fresh + marker + "\n")
        assert_raises(Legacy::Failure) { Legacy::SessionFence.observe!(path, 13, next_nonce, prior: ready) }
      end
    end
  end

  def test_whole_prefix_and_tail_corruption_are_separate_non_skippable_checks
    Dir.mktmpdir('microphone-v9-tail-mutation.') do |directory|
      path = directory + '/host.log'; nonce = 'c' * 64
      bytes = "historical-prefix\nWorldwide availability is waiting for the paired iPhone\nWorldwide paired-device availability is online pid=12 nonce=#{nonce}\n"
      File.write(path, bytes); File.chmod(0600, path)
      snapshot = Legacy::SessionFence.observe!(path, 12, nonce)
      tail = Gate.session_tail_sha256!(path, snapshot)
      # Historical corruption outside the tail cannot be excused by a matching
      # tail: the unchanged legacy full-prefix check must independently reject.
      File.write(path, bytes.sub('historical-prefix', 'historical-prefiy'))
      assert_equal tail, Gate.session_tail_sha256!(path, snapshot)
      assert_raises(Legacy::Failure) { Legacy::SessionFence.observe!(path, 12, nonce, prior: snapshot) }
      File.write(path, bytes.sub('paired iPhone', 'paired iPhonf'))
      refute_equal tail, Gate.session_tail_sha256!(path, snapshot)
      assert_raises(Legacy::Failure) { Legacy::SessionFence.observe!(path, 12, nonce, prior: snapshot) }
      assert_raises(Gate::Refused) { Gate.session_tail_sha256!(path, snapshot, deadline: 0) }
      File.write(path, bytes.byteslice(0, snapshot.size - 1))
      assert_raises(Gate::Refused) { Gate.session_tail_sha256!(path, snapshot) }
      File.write(path, bytes)
      alias_path = directory + '/alias'; File.symlink(path, alias_path)
      assert_raises(Gate::Refused) { Gate.session_tail_sha256!(alias_path, snapshot) }
      File.unlink(alias_path); File.link(path, alias_path)
      assert_raises(Gate::Refused) { Gate.session_tail_sha256!(path, snapshot) }
      File.unlink(alias_path)
      File.chmod(0666, path)
      assert_raises(Gate::Refused) { Gate.session_tail_sha256!(path, snapshot) }
      too_large = snapshot.dup; too_large.size = too_large.last_reset_offset + Gate::MAX_TAIL_BYTES + 1
      assert_raises(Gate::Refused) { Gate.session_tail_sha256!(path, too_large) }
    end
  end

  def session_result(implementation, path, pid = 12, nonce = 'c' * 64, **options)
    [:accepted, implementation.observe!(path, pid, nonce, **options).to_h]
  rescue Legacy::Failure => error
    [:refused, error.class, error.message]
  end

  def assert_session_equivalent(path, pid = 12, nonce = 'c' * 64, **options)
    expected = session_result(Legacy::SessionFence, path, pid, nonce, **options)
    assert_equal expected, session_result(Gate::SessionFenceAdapter, path, pid, nonce, **options)
    expected
  end

  def test_forward_last_match_is_literal_binary_and_overlap_equivalent
    values = ["".b, "aaaaa".b, "ababa\0\xffababa".b, "éλ".b + "Worldwide viewer disconnected\0".b]
    needles = ['aaa', 'aba', 'missing', "\0", "\xff".b, *Legacy::SessionFence::RESET_MARKERS, *Legacy::SessionFence::UNSAFE_MARKERS]
    values.each do |window|
      needles.each do |needle|
        expected = window.rindex(needle.b)
        actual = Gate::SessionFenceAdapter.last_match(window.b, needle.b)
        expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
      end
    end
  end

  def test_adapter_matches_frozen_reference_for_every_marker_across_one_mib_boundaries
    Dir.mktmpdir('microphone-v9-forward-boundary.') do |directory|
      path = directory + '/host.log'; nonce = 'c' * 64
      online = "Worldwide paired-device availability is online pid=12 nonce=#{nonce}"
      reset = Legacy::SessionFence::RESET_MARKERS.first
      markers = [online, *Legacy::SessionFence::RESET_MARKERS, *Legacy::SessionFence::UNSAFE_MARKERS, Legacy::SessionFence::STOP_MARKER]
      markers.each do |marker|
        split = [1, marker.bytesize / 2, marker.bytesize - 1]
        split.each do |before_boundary|
          prefix = (reset + "\n" + online + "\n" + "éλ\0\xff".b).b
          filler = 'x'.b * (Legacy::SessionFence::READ_CHUNK_BYTES - before_boundary - prefix.bytesize)
          bytes = prefix + filler + marker.b + "\n" + reset.b + "\n" + online.b + "\n"
          File.binwrite(path, bytes); File.chmod(0600, path)
          assert_equal :accepted, assert_session_equivalent(path).first
          # The boundary-spanning unsafe marker cannot hide behind a newer
          # prefix: without the final reset it must fail exactly like V91.
          if Legacy::SessionFence::UNSAFE_MARKERS.include?(marker)
            File.binwrite(path, prefix + filler + marker.b + "\n")
            assert_equal :refused, assert_session_equivalent(path).first
          end
        end
      end
    end
  end

  def test_adapter_preserves_prior_fresh_absent_recovery_and_corruption_decisions
    Dir.mktmpdir('microphone-v9-forward-prior.') do |directory|
      path = directory + '/host.log'; nonce = 'c' * 64; next_nonce = 'd' * 64
      bytes = "history\0\xff".b + "Worldwide paired-device availability is online pid=12 nonce=#{nonce}\nWorldwide viewer disconnected\n".b
      File.binwrite(path, bytes); File.chmod(0600, path)
      assert_equal :accepted, assert_session_equivalent(path).first
      prior = Legacy::SessionFence.observe!(path, 12, nonce)
      assert_equal :accepted, assert_session_equivalent(path, prior: prior).first
      assert_equal :refused, assert_session_equivalent(path, fresh_generation: true).first
      invalid = bytes + "Worldwide paired-device availability is online pid=13 nonce=#{next_nonce}\n".b
      File.binwrite(path, invalid)
      assert_equal :refused, assert_session_equivalent(path, 13, next_nonce, prior: prior, fresh_generation: true).first
      fresh = bytes + "Worldwide peer returned to idle\nWorldwide paired-device availability is online pid=13 nonce=#{next_nonce}\n".b
      File.binwrite(path, fresh)
      assert_equal :accepted, assert_session_equivalent(path, 13, next_nonce, prior: prior, fresh_generation: true).first
      ready = Legacy::SessionFence.observe!(path, 13, next_nonce, prior: prior, fresh_generation: true)
      assert_equal :accepted, assert_session_equivalent(path, 13, next_nonce, prior: ready).first
      assert_equal :refused, assert_session_equivalent(path, 12, nonce, prior: prior).first
      [fresh.sub('history', 'histori'), fresh.byteslice(0, prior.size - 1),
       fresh + "controlOpen=true\n".b, fresh + "Worldwide viewer disconnected\n".b].each do |mutant|
        File.binwrite(path, mutant)
        assert_equal :refused, assert_session_equivalent(path, 13, next_nonce, prior: ready).first
      end
      File.binwrite(path, fresh); replacement = directory + '/replacement'; File.binwrite(replacement, fresh); File.chmod(0600, replacement)
      File.rename(replacement, path)
      assert_equal :refused, assert_session_equivalent(path, 13, next_nonce, prior: ready).first
      assert_raises(Legacy::Failure) { Gate::SessionFenceAdapter.observe!(path, 13, next_nonce, deadline: 0) }
    end
  end

  def test_adapter_and_reference_reject_short_reads_and_mid_read_replacement_or_truncation
    Dir.mktmpdir('microphone-v9-forward-race.') do |directory|
      path = directory + '/host.log'; nonce = 'c' * 64
      bytes = "Worldwide availability is waiting for the paired iPhone\nWorldwide paired-device availability is online pid=12 nonce=#{nonce}\n"
      %i[short replace truncate].each do |mutation|
        results = [Legacy::SessionFence, Gate::SessionFenceAdapter].map do |implementation|
          File.binwrite(path, bytes); File.chmod(0600, path)
          File.open(path, File::RDONLY | File::NOFOLLOW) do |owned|
            pread = owned.method(:pread)
            owned.define_singleton_method(:pread) do |count, offset|
              value = pread.call(count, offset)
              case mutation
              when :short then value = value.byteslice(0, value.bytesize - 1)
              when :truncate then File.truncate(path, 1)
              when :replace
                replacement = directory + '/new'; File.binwrite(replacement, bytes); File.chmod(0600, replacement); File.rename(replacement, path)
              end
              value
            end
            File.stub(:open, ->(*_arguments, &block) { block.call(owned) }) { session_result(implementation, path) }
          end
        end
        assert_equal :refused, results.first.first
        assert_equal results.first, results.last
      end
    end
  end

  def test_real_dynamic_codesign_rejects_duplicate_and_wrong_identity
    host = Legacy::RealHost.new
    metadata = "Identifier=com.elamin.AudioStreamer.CaptureServer\nTeamIdentifier=MSMG8CJLB3\nCDHash=a8b4287bbf0299946c21a01f445787f85d82197e\n"
    assert host.send(:verify_dynamic_codesign_identity!, metadata, expected_cdhash: 'a8b4287bbf0299946c21a01f445787f85d82197e')
    [metadata + "CDHash=a8b4287bbf0299946c21a01f445787f85d82197e\n", metadata.sub('MSMG8CJLB3', 'WRONG'),
     metadata.sub('a8b4287b', '00000000'), metadata + "Identifier=com.elamin.AudioStreamer.CaptureServer\n"].each do |mutant|
      assert_raises(Legacy::Failure) { host.send(:verify_dynamic_codesign_identity!, mutant, expected_cdhash: 'a8b4287bbf0299946c21a01f445787f85d82197e') }
    end
  end

  def test_real_readiness_parser_rejects_non_idle_wrong_pid_or_extra_bytes
    host = Legacy::RealHost.new; host.instance_variable_set(:@candidate_executable_sha, Gate::BYTE_PINS['host_executable_sha256']); host.instance_variable_set(:@new_pid, 12)
    accepted = "V91_SECONDARY_VIEWER_ENDPOINT_IDLE_OK candidateSHA256=#{Gate::BYTE_PINS['host_executable_sha256']} pid=12 managerGeneration=7 probes=2\n"
    Legacy::Util.stub(:capture!, accepted) { assert_equal 7, host.send(:readiness_generation!) }
    [accepted.sub('pid=12', 'pid=13'), accepted.sub('probes=2', 'probes=1'), accepted.sub('managerGeneration=7', 'managerGeneration=07'),
     accepted.sub('IDLE_OK', 'BUSY'), accepted + 'extra'].each do |mutant|
      Legacy::Util.stub(:capture!, mutant) { assert_raises(Legacy::Failure) { host.send(:readiness_generation!) } }
    end
  end

  def test_no_mutation_command_can_cross_observer_dispatch
    tools = Gate::PREFIX + '/driver-microphone-v9-fixture/tools'; commands = Gate::Commands.new(tools)
    assert_equal ['/bin/launchctl', 'print', Gate::LABEL], commands.allowed!(['/bin/launchctl', 'print', Gate::LABEL])
    assert_equal ['/bin/zsh', '-f', tools + '/product/verify-v91-secondary-viewer-readiness.sh', Gate::LIVE_EXE, Gate::BYTE_PINS['host_executable_sha256']],
      commands.allowed!([tools + '/product/verify-v91-secondary-viewer-readiness.sh', Gate::LIVE_EXE, Gate::BYTE_PINS['host_executable_sha256']])
    [['/bin/launchctl', 'bootout', Gate::LABEL], ['/bin/launchctl', 'bootstrap', 'gui/501', Gate::PLIST], ['/usr/bin/sudo', '/bin/true'],
     [tools + '/observers/SwitchAudioSource', '-s', 'BlackHole 2ch'], [Gate::LIVE_EXE, '--worldwide'],
     ['/bin/ls', '-lde', '/Applications/.audiostreamer-failed-20260720-102747-44276'], ['/usr/bin/xattr', '-w', 'value', Gate::LIVE_APP]].each do |argv|
      assert_raises(Gate::Refused) { commands.run(*argv) }
    end
    assert_raises(Gate::Refused) { Gate.sealed_sources!('/private/unsealed', 'driver-microphone-v9-fixture', commands: commands) }
    assert_raises(Gate::Refused) { Gate.read_fd!(100_000) }
  end

  MetadataStat = Struct.new(:dev, :ino, :uid, :gid, :mode, :nlink, :size, :mtime, :ctime, :kind, keyword_init: true) do
    def directory?; kind == :directory end
    def file?; kind == :file end
  end
  MetadataStatus = Struct.new(:ok) do
    def success?; ok end
  end

  def metadata_stat(**changes)
    MetadataStat.new(**{ dev: 2, ino: 3, uid: 0, gid: 0, mode: 040755, nlink: 1,
      size: 128, mtime: Time.at(10), ctime: Time.at(20), kind: :directory }.merge(changes))
  end

  def root_metadata_fixture(mode: 'candidate-present', now_ms: 1_790_928_000_000)
    req = request
    value = { 'schema' => Gate::ROOT_METADATA_SCHEMA, 'namespace' => req['namespace'], 'nonce' => req['nonce'],
      'request_sha256' => Digest::SHA256.hexdigest(text(req)), 'worker_sha256' => req['worker_sha256'],
      'host_gate_sha256' => 'e' * 64, 'mode' => mode, 'observed_at_unix_ms' => now_ms.to_s,
      'sequence' => '1', 'acl_absent' => 'true', 'xattrs_empty' => 'true' }
    Gate::ROOT_METADATA_IDENTITY_KEYS.each_with_index do |key, index|
      value[key] = Gate.identity(metadata_stat(ino: 3 + index, mode: 040711)).join(',')
    end
    value
  end

  def root_metadata_text(value)
    value.map { |key, item| "#{key}=#{item}\n" }.join
  end

  def root_metadata_source_stub
    lambda do |path, sha, owner:, modes:|
      Gate.assert!(File.expand_path(path) == File.expand_path('opensteamer-microphone-v9-host-gate.rb', __dir__) &&
        sha == 'e' * 64 && owner == 0 && modes == [0444], 'root metadata sealed script bytes differ')
      ['offline sealed script', Gate.identity(metadata_stat(kind: :file, mode: 0100444))]
    end
  end

  def parse_root_metadata(value = root_metadata_fixture, expected: nil, mode: 'candidate-present', now_ms: 1_790_928_000_000)
    bytes = value.is_a?(Hash) ? root_metadata_text(value) : value
    Time.stub(:now, Time.at(Rational(now_ms, 1000))) do
      Gate.stub(:read_file!, root_metadata_source_stub) do
        Gate.root_metadata!(bytes, expected || Digest::SHA256.hexdigest(bytes), request,
          request_sha: Digest::SHA256.hexdigest(text(request)), mode: mode)
      end
    end
  end

  def test_root_metadata_wire_binds_every_field_and_exact_five_identities
    value = root_metadata_fixture; accepted = parse_root_metadata(value)
    assert accepted.frozen?
    assert_equal Gate.root_metadata_paths(request['namespace']).values.sort, accepted.keys.sort
    assert accepted.values.all?(&:frozen?)
    Gate::MODES.each do |mode|
      assert_equal accepted, parse_root_metadata(root_metadata_fixture(mode: mode), mode: mode)
    end
    Gate::ROOT_METADATA_KEYS.each do |key|
      assert_raises(Gate::Refused) { parse_root_metadata(value.reject { |field, _| field == key }) }
      assert_raises(Gate::Refused) { parse_root_metadata(value.merge(key => 'wrong')) }
    end
    bytes = root_metadata_text(value)
    [bytes + "unknown=1\n", bytes + "sequence=1\n", bytes + "path=#{Gate::PREFIX}\n", bytes.delete_suffix("\n"),
     bytes.sub("\n", "\r\n"), bytes.sub('schema=', 'schema=extra='), bytes.sub('namespace=', "namespace=é")].each do |mutant|
      assert_raises(Gate::Refused) { parse_root_metadata(mutant) }
    end
    assert_raises(Gate::Refused) { parse_root_metadata(value, expected: 'f' * 64) }
    assert_raises(Gate::Refused) { parse_root_metadata(value, mode: 'host-ready') }
    %w[nonce request_sha256 worker_sha256 host_gate_sha256].each do |key|
      assert_raises(Gate::Refused) { parse_root_metadata(value.merge(key => 'f' * 64)) }
    end
    %w[false TRUE 1].each do |mutant|
      %w[acl_absent xattrs_empty].each { |key| assert_raises(Gate::Refused) { parse_root_metadata(value.merge(key => mutant)) } }
    end
  end

  def test_root_metadata_identity_and_freshness_are_canonical_bounded_and_not_replayable
    value = root_metadata_fixture
    %w[0 01 65 18446744073709551616].each do |sequence|
      assert_raises(Gate::Refused) { parse_root_metadata(value.merge('sequence' => sequence)) }
    end
    assert_equal parse_root_metadata(value), parse_root_metadata(value.merge('sequence' => '64'))
    assert parse_root_metadata(value, now_ms: value['observed_at_unix_ms'].to_i + 5000)
    [-1, 5001].each do |age|
      assert_raises(Gate::Refused) { parse_root_metadata(value, now_ms: value['observed_at_unix_ms'].to_i + age) }
    end
    ['0', '01', '-1', '18446744073709551616'].each do |timestamp|
      assert_raises(Gate::Refused) { parse_root_metadata(value.merge('observed_at_unix_ms' => timestamp)) }
    end
    Gate::ROOT_METADATA_IDENTITY_KEYS.each do |key|
      tuple = value[key].split(',')
      { 0 => '0', 1 => '0', 2 => '501', 3 => '80', 4 => '16877', 5 => '0',
        7 => '9223372036854775808', 8 => '1000000000', 9 => '9223372036854775808', 10 => '1000000000' }.each do |index, item|
        mutant = tuple.dup; mutant[index] = item
        assert_raises(Gate::Refused) { parse_root_metadata(value.merge(key => mutant.join(','))) }
      end
      [tuple.drop(1).join(','), (tuple + ['1']).join(','), tuple.join(',') + ',',
       tuple.join(',').sub('2,', '02,'), tuple.join(',').sub('2,', '-2,'),
       tuple.join(',').sub('2,', '18446744073709551616,')].each do |mutant|
        assert_raises(Gate::Refused) { parse_root_metadata(value.merge(key => mutant)) }
      end
    end
  end

  MetadataFD = Struct.new(:before, :after, :bytes, :access, :closed, :stat_reads, keyword_init: true) do
    def stat
      self.stat_reads = stat_reads.to_i + 1
      stat_reads == 1 ? before : (after || before)
    end
    def fcntl(_operation); access end
    def pread(count, _offset); bytes.byteslice(0, count) end
    def close; self.closed = true end
  end

  def metadata_channel(value = root_metadata_fixture, **changes)
    bytes = root_metadata_text(value)
    MetadataFD.new(**{ before: metadata_stat(kind: :file, mode: 0100400, size: bytes.bytesize),
      bytes: bytes, access: Fcntl::O_RDONLY, closed: false }.merge(changes))
  end

  def consume_metadata_channel(channel, expected: Digest::SHA256.hexdigest(channel.bytes))
    Time.stub(:now, Time.at(Rational(1_790_928_000_000, 1000))) do
      Gate.stub(:read_file!, root_metadata_source_stub) do
        IO.stub(:for_fd, ->(fd, **options) { assert_equal 6, fd; assert_equal false, options[:autoclose]; channel }) do
          Gate.read_root_metadata_fd!(expected, request, request_sha: Digest::SHA256.hexdigest(text(request)), mode: 'candidate-present')
        end
      end
    end
  end

  def test_root_metadata_channel_is_mandatory_immutable_readonly_and_always_closed
    channel = metadata_channel
    assert_equal parse_root_metadata, consume_metadata_channel(channel)
    assert channel.closed
    base = channel.before
    [metadata_stat(kind: :directory, mode: 040400, size: base.size), metadata_stat(uid: 501, kind: :file, mode: 0100400, size: base.size),
     metadata_stat(gid: 20, kind: :file, mode: 0100400, size: base.size), metadata_stat(nlink: 2, kind: :file, mode: 0100400, size: base.size),
     metadata_stat(kind: :file, mode: 0100600, size: base.size), metadata_stat(kind: :file, mode: 0100400, size: 0),
     metadata_stat(kind: :file, mode: 0100400, size: Gate::MAX_BYTES + 1)].each do |stat|
      mutant = metadata_channel(before: stat)
      assert_raises(Gate::Refused) { consume_metadata_channel(mutant) }
      assert mutant.closed
    end
    [Fcntl::O_WRONLY, Fcntl::O_RDWR].each do |access|
      mutant = metadata_channel(access: access)
      assert_raises(Gate::Refused) { consume_metadata_channel(mutant) }
      assert mutant.closed
    end
    [metadata_channel(after: metadata_stat(kind: :file, mode: 0100400, size: base.size, ino: 99)),
     metadata_channel(bytes: channel.bytes.byteslice(0, channel.bytes.bytesize - 1))].each do |mutant|
      assert_raises(Gate::Refused) { consume_metadata_channel(mutant) }
      assert mutant.closed
    end
    mutant = metadata_channel
    assert_raises(Gate::Refused) { consume_metadata_channel(mutant, expected: 'f' * 64) }
    assert mutant.closed
    assert_raises(Gate::Refused) { Gate.read_fd!(100_000) }
  end

  # This exercises production policy and dispatch with no process or system-node IO.
  def clean_metadata_fixture(path: '/Library', before: metadata_stat, after: before,
      canonical: path, final_canonical: canonical, flags: "1048576\n", flags_ok: true,
      acl: "drwxr-xr-x 1 root wheel 128 fixture\n", xattrs: '', xattr_errors: '', xattr_ok: true, root_metadata: nil)
    tools = Gate::PREFIX + '/driver-microphone-v9-fixture/tools'
    commands = Gate::Commands.new(tools, root_metadata: root_metadata); calls = []
    stats = [before, after]; canonical_paths = [canonical, final_canonical]
    runner = lambda do |*argv|
      commands.allowed!(argv); calls << argv
      case argv.first
      when '/bin/ls' then [acl, '', MetadataStatus.new(true)]
      when '/usr/bin/xattr' then [xattrs, xattr_errors, MetadataStatus.new(xattr_ok)]
      when '/usr/bin/stat' then [flags, '', MetadataStatus.new(flags_ok)]
      else flunk 'unexpected metadata command'
      end
    end
    File.stub(:lstat, ->(_path) { stats.shift || after }) do
      File.stub(:realpath, ->(_path) { canonical_paths.shift || final_canonical }) do
        commands.stub(:run, runner) { commands.clean_metadata!(path) }
      end
    end
    calls
  end

  def test_exact_canonical_library_sf_nounlink_policy
    assert_equal [['/bin/ls', '-lde', '/Library'], ['/usr/bin/xattr', '/Library'],
      ['/usr/bin/stat', '-f', '%f', '/Library']], clean_metadata_fixture
    assert_equal 3, clean_metadata_fixture(path: '/Library/Application Support', flags: "0\n").size
    ["0\n", "1048577\n", "1048578\n", "1\n", "01048576\n", "1048576\r\n", '1048576', "1048576\nextra\n"].each do |flags|
      assert_raises(Gate::Refused) { clean_metadata_fixture(flags: flags) }
    end
    assert_raises(Gate::Refused) { clean_metadata_fixture(flags_ok: false) }
    [metadata_stat(uid: 501), metadata_stat(gid: 80), metadata_stat(mode: 040711),
     metadata_stat(mode: 040775), metadata_stat(mode: 040777), metadata_stat(kind: :file, mode: 0100755),
     metadata_stat(kind: :symlink, mode: 0120755)].each do |stat|
      assert_raises(Gate::Refused) { clean_metadata_fixture(before: stat) }
    end
    assert_raises(Gate::Refused) { clean_metadata_fixture(canonical: '/private/Library') }
    assert_raises(Gate::Refused) { clean_metadata_fixture(final_canonical: '/private/Library') }
    assert_raises(Gate::Refused) { clean_metadata_fixture(acl: "drwxr-xr-x+ 1 root wheel 128 fixture\n") }
    assert_raises(Gate::Refused) { clean_metadata_fixture(xattrs: "com.example.fixture\n") }
    assert_raises(Gate::Refused) { clean_metadata_fixture(xattr_errors: "refused\n") }
  end

  def test_library_flag_exception_does_not_extend_to_other_paths_or_aliases
    tools = Gate::PREFIX + '/driver-microphone-v9-fixture/tools'
    ['/Library/Application Support', tools, tools + '/product/fixture', '/private/unexpected',
     '/Library/', '/Library/.', '/private/Library', '//Library', '/'].each do |path|
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path) }
    end
    assert_raises(Gate::Refused) { clean_metadata_fixture(path: tools, flags: "0\n") }
  end

  def test_only_exact_attested_0711_directories_delegate_xattrs_and_retain_acl_flags_and_identity
    proof = parse_root_metadata
    proof.each do |path, tuple|
      stat = metadata_stat(ino: tuple[1], mode: 040711)
      calls = clean_metadata_fixture(path: path, before: stat, flags: "0\n", root_metadata: proof,
        xattr_ok: false, xattr_errors: 'EACCES')
      assert_equal [['/bin/ls', '-lde', path], ['/usr/bin/stat', '-f', '%f', path]], calls
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: stat, flags: "0\n", xattr_ok: false, xattr_errors: 'EACCES') }
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: stat, flags: "1\n", root_metadata: proof) }
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: stat, flags: "0\n", root_metadata: proof,
        acl: "drwx--x--x+ 1 root wheel 128 fixture\n") }
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: stat, flags: "0\n", root_metadata: proof, canonical: '/private/alias') }
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: stat, flags: "0\n", root_metadata: proof,
        after: metadata_stat(ino: tuple[1], mode: 040711, ctime: Time.at(21))) }
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: metadata_stat(ino: tuple[1]), flags: "0\n", root_metadata: proof) }
    end
    path = Gate::PREFIX + '/driver-microphone-v9-fixture/tools/product/readable.rb'
    assert_equal 3, clean_metadata_fixture(path: path, before: metadata_stat(kind: :file, mode: 0100444), flags: "0\n", root_metadata: proof).size
    assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, flags: "0\n", root_metadata: proof, xattr_ok: false, xattr_errors: 'EACCES') }
    assert_raises(Gate::Refused) { clean_metadata_fixture(path: '/Library/Application Support', flags: "0\n", root_metadata: proof, xattrs: 'com.example.fixture') }
    tools = Gate::PREFIX + '/driver-microphone-v9-fixture/tools'
    [proof.dup, proof.reject { |path, _| path == tools }.freeze, proof.merge(tools + '/extra' => proof.fetch(tools)).freeze].each do |mutant|
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: tools, before: metadata_stat(ino: proof.fetch(tools)[1], mode: 040711), flags: "0\n", root_metadata: mutant) }
    end
  end

  def test_attested_directory_all_identity_fields_are_rechecked_and_not_only_inode_and_mode
    proof = parse_root_metadata; path = Gate::PREFIX + '/driver-microphone-v9-fixture/tools'
    stat = metadata_stat(ino: proof.fetch(path)[1], mode: 040711)
    { dev: 4, ino: 99, uid: 501, gid: 80, mode: 040755, nlink: 2, size: 129,
      mtime: Time.at(11), ctime: Time.at(21) }.each do |field, item|
      changed = metadata_stat(ino: stat.ino, mode: stat.mode, **{ field => item })
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: changed, flags: "0\n", root_metadata: proof) }
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: stat, after: changed, flags: "0\n", root_metadata: proof) }
    end
    [metadata_stat(ino: stat.ino, mode: stat.mode, mtime: Time.at(10, 1, :nsec)),
     metadata_stat(ino: stat.ino, mode: stat.mode, ctime: Time.at(20, 1, :nsec))].each do |changed|
      assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: stat, after: changed, flags: "0\n", root_metadata: proof) }
    end
    assert_raises(Gate::Refused) { clean_metadata_fixture(path: path, before: stat, flags: "0\n", root_metadata: proof, final_canonical: '/private/alias') }
  end

  def test_sealed_sources_requires_all_five_bound_directory_identities_before_source_reads
    proof = parse_root_metadata; namespace = request['namespace']; tools = Gate::PREFIX + '/' + namespace + '/tools'
    adapter = File.expand_path('opensteamer-microphone-v9-host-gate.rb', __dir__)
    stats = proof.to_h { |path, tuple| [path, metadata_stat(ino: tuple[1], mode: 040711)] }
    active_stats = stats
    File.stub(:realpath, ->(path) { path == adapter ? tools + '/opensteamer-microphone-v9-host-gate.rb' : path }) do
      File.stub(:lstat, ->(path) { active_stats.fetch(path) }) do
        assert_raises(Gate::Refused) { Gate.sealed_sources!(tools, namespace, commands: Gate::Commands.new(tools)) }
        proof.keys.each do |path|
          active_stats = stats.merge(path => metadata_stat(ino: 99, mode: 040711))
          reached = false
          Gate.stub(:read_file!, ->(*_args, **_options) { reached = true; raise 'source read must not run' }) do
            commands = Gate::Commands.new(tools, root_metadata: proof)
            assert_raises(Gate::Refused) { Gate.sealed_sources!(tools, namespace, commands: commands) }
          end
          refute reached
        end
        active_stats = stats
      end
    end
  end

  def test_library_full_identity_is_retained_across_metadata_reads
    { dev: 4, ino: 4, uid: 501, gid: 80, mode: 040711, nlink: 2, size: 129,
      mtime: Time.at(11), ctime: Time.at(21) }.each do |field, value|
      assert_raises(Gate::Refused) { clean_metadata_fixture(after: metadata_stat(**{ field => value })) }
    end
    [metadata_stat(mtime: Time.at(10, 1, :nsec)), metadata_stat(ctime: Time.at(20, 1, :nsec))].each do |stat|
      assert_raises(Gate::Refused) { clean_metadata_fixture(after: stat) }
    end
  end

  def test_production_sealed_source_ancestry_includes_library_but_excludes_root
    namespace = 'driver-microphone-v9-fixture'; tools = Gate::PREFIX + '/' + namespace + '/tools'
    adapter = File.expand_path('opensteamer-microphone-v9-host-gate.rb', __dir__)
    seen = []; commands = Object.new
    commands.define_singleton_method(:sealed_root_metadata!) { true }
    commands.define_singleton_method(:clean_metadata!) { |path| seen << path }
    stat = lambda do |path|
      path == adapter ? metadata_stat(kind: :file, mode: 0100444) :
        metadata_stat(gid: path == '/Library/Application Support' ? 80 : 0)
    end
    File.stub(:realpath, ->(path) { path == adapter ? tools + '/opensteamer-microphone-v9-host-gate.rb' : path }) do
      File.stub(:lstat, stat) do
        Gate.stub(:read_file!, ->(*_args, **_options) { ['fixture', Gate.identity(metadata_stat(kind: :file))] }) do
          records = Gate.sealed_sources!(tools, namespace, commands: commands)
          assert records.key?('/Library')
          refute records.key?('/')
        end
      end
    end
    assert_includes seen, '/Library'
    refute_includes seen, '/'
    dispatch = Gate::Commands.new(tools)
    assert dispatch.metadata_path?('/Library')
    assert_raises(Gate::Refused) { dispatch.metadata_path?('/') }
  end

  def test_refusal_diagnostic_is_bounded_stage_class_and_hash_only
    private_message = "/private/fixture credential-like-value\nsecret\x00\xff".b
    error = Gate::Refused.new(private_message)
    Gate::CLI_STAGES.each do |stage|
      diagnostic = Gate.refusal_diagnostic(stage, error)
      assert_includes diagnostic, "stage=#{stage} class=Refused diagnostic=hashed"
      assert_includes diagnostic, 'reason_sha256=' + Digest::SHA256.hexdigest(private_message)
      refute_includes diagnostic, '/private/'
      refute_includes diagnostic, 'secret'
      assert diagnostic.ascii_only?
      assert_operator diagnostic.bytesize, :<, 400
    end
    diagnostic = Gate.refusal_diagnostic(private_message, Class.new(StandardError).new(private_message))
    assert_includes diagnostic, 'stage=unknown class=StandardError'
    refute_includes diagnostic, 'secret'
    { SystemCallError => SystemCallError.new('private', 13), IOError => IOError.new(private_message),
      ArgumentError => ArgumentError.new(private_message), TypeError => TypeError.new(private_message),
      EncodingError => EncodingError.new(private_message) }.each do |kind, exception|
      assert_includes Gate.refusal_diagnostic('observe', exception), "class=#{kind.name} diagnostic=hashed"
    end
    huge = Gate::Refused.new('s' * (Gate::MAX_DIAGNOSTIC_BYTES + 1))
    diagnostic = Gate.refusal_diagnostic('observe', huge)
    assert_includes diagnostic, 'diagnostic=extent_refused'
    assert_includes diagnostic, 'reason_sha256=' + Digest::SHA256.hexdigest('diagnostic message extent refused')
    assert_operator diagnostic.bytesize, :<, 400
  end

  def test_cli_sealed_source_refusal_retains_safe_stage_and_original_reason_hash
    bytes = text(request); reason = 'sealed node flags refused'; code = nil
    stdout, stderr = capture_io do
      Process.stub(:uid, 501) do
        Process.stub(:euid, 501) do
          ENV.stub(:keys, []) do
            Gate.stub(:read_fd!, bytes) do
              Gate.stub(:read_root_metadata_fd!, parse_root_metadata) do
                Gate.stub(:sealed_sources!, ->(*_args, **_options) { raise Gate::Refused, reason }) do
                  code = Gate.cli!(['--candidate-present', '/dev/fd/3', Digest::SHA256.hexdigest(bytes), 'e' * 64])
                end
              end
            end
          end
        end
      end
    end
    assert_equal 78, code
    assert_empty stdout
    assert_equal Gate.refusal_diagnostic('sealed_sources', Gate::Refused.new(reason)) + "\n", stderr
    refute_includes stderr, reason
  end

  def test_cli_missing_or_refused_metadata_never_reaches_sealed_sources_or_observers
    bytes = text(request); request_sha = Digest::SHA256.hexdigest(bytes)
    [ ['--candidate-present', '/dev/fd/3', request_sha],
      ['--candidate-present', '/dev/fd/3', request_sha, 'e' * 64] ].each do |argv|
      code = nil; reached = false
      stdout, stderr = capture_io do
        Process.stub(:uid, 501) do
          Process.stub(:euid, 501) do
            ENV.stub(:keys, []) do
              reader = ->(fd) { fd == 3 ? bytes : raise(Gate::Refused, 'root-held input unavailable') }
              Gate.stub(:read_fd!, reader) do
                Gate.stub(:sealed_sources!, ->(*_args, **_options) { reached = true; raise 'must not run' }) { code = Gate.cli!(argv) }
              end
            end
          end
        end
      end
      assert_equal 78, code; refute reached; assert_empty stdout
      assert_includes stderr, argv.size == 3 ? 'stage=caller' : 'stage=root_metadata'
    end
  end
end
