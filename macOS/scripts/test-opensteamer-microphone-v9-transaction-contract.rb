# frozen_string_literal: true
# Offline field/file mutants only. This never substitutes a runtime success.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'opensteamer-microphone-v9-transaction-contract'

class MicrophoneV9TransactionContractTests < Minitest::Test
  C = OpensteamerMicrophoneV9TransactionContract

  def native
    values = C::NATIVE_KEYS.to_h do |key|
      value = if key.end_with?('_sha256') || %w[nonce host_nonce].include?(key)
                'a' * 64
              elsif key.end_with?('_commit', '_tree')
                'b' * 40
              elsif key.end_with?('_path', '_root')
                '/private/tmp/fixture-' + key
              else
                '1'
              end
      [key, value]
    end
    values.merge!(C::FIXED)
    values['namespace'] = 'driver-microphone-v9-offline-001'
    values['guard_tooling_root'] = File.realpath(__dir__ + '/../..')
    values['guard_tooling_commit'] = 'c' * 40
    values['timeout_seconds'] = '180'
    values['host_nonce'] = 'd' * 64
    values['committed_host_pointer_path'] = C::HOST_ACTIVE_POINTER
    %w[result readiness journal].each do |role|
      values['committed_host_' + role + '_path'] = C::HOST_UPDATE_ROOT + '/fixture/' + role + '.txt'
    end
    values
  end

  def descriptor(path = '/private/tmp/offline')
    { 'path' => path, 'sha256' => 'a' * 64 }
  end

  def request
    { 'schema' => C::SCHEMA, 'nativeRequest' => native,
      'receiptRequest' => descriptor, 'freshBinding' => descriptor,
      'gateObservation' => descriptor,
      'tools' => C::TOOL_ROLES.to_h { |role| [role, descriptor('/private/tmp/' + role)] } }
  end

  def gate(n = native)
    mappings = {
      'namespace' => 'namespace', 'nonce' => 'nonce', 'hostPid' => 'host_pid',
      'hostStartIdentitySha256' => 'host_start_identity_sha256', 'hostNonce' => 'host_nonce',
      'hostLockDevice' => 'host_lock_device', 'hostLockInode' => 'host_lock_inode',
      'hostLaunchdRuns' => 'host_launchd_runs', 'hostDisplayIdentitySha256' => 'host_display_identity_sha256',
      'hostExecutableSha256' => 'host_executable_sha256', 'predecessorDriverInstance' => 'predecessor_driver_instance',
      'predecessorDriverDevice' => 'predecessor_driver_device', 'predecessorDriverInode' => 'predecessor_driver_inode',
      'predecessorDriverExecutableSha256' => 'predecessor_driver_executable_sha256',
      'inputUid' => 'input_uid', 'outputUid' => 'output_uid', 'systemOutputUid' => 'system_output_uid'
    }
    result = mappings.to_h { |observed, pinned| [observed, n.fetch(pinned)] }
    result.merge!(
      'schema' => 'opensteamer.microphone-v9-quiescent-observation.v1', 'observedAtUnixMs' => 10_000,
      'peerConnected' => false, 'authenticatedPeer' => false, 'iceConnected' => false,
      'controlOpen' => false, 'screenCaptureActive' => false, 'sessionBoundaryProven' => true,
      'routeNotifications' => 0, 'routeMonitorTeardownClean' => true,
      'hostTerminal' => 'COMMITTED_CANDIDATE', 'namespaceAbsent' => true
    )
    result
  end

  def refuse
    assert_raises(C::Refusal) { yield }
  end

  def test_exact_flat_round_trip_and_distinct_generations
    n = native
    assert_equal n, C.parse_native(C.native_text(n))
    assert_equal C::NATIVE_KEYS, C.native_text(n).lines.map { |line| line.split('=', 2)[0] }
    refute_equal n['producer_commit'], n['guard_tooling_commit']
    assert_equal C::PRODUCER_COMMIT, n['producer_commit']
    assert_equal C::PRODUCT_COMMIT, n['product_commit']
  end

  def test_all_native_missing_and_unknown_fields_refuse
    C::NATIVE_KEYS.each do |key|
      mutant = native; mutant.delete(key)
      refuse { C.native_text(mutant) }
    end
    mutant = native; mutant['execute_as_root'] = 'true'
    refuse { C.native_text(mutant) }
  end

  def test_every_reviewed_pin_refuses_mutation
    C::FIXED.each do |key, value|
      mutant = native; mutant[key] = value + 'x'
      refuse { C.validate_native!(mutant) }
    end
  end

  def test_producer_is_not_current_tooling_and_current_root_is_not_selectable
    mutant = native; mutant['guard_tooling_commit'] = C::PRODUCER_COMMIT
    refuse { C.validate_native!(mutant) }
    mutant = native; mutant['guard_tooling_root'] = '/private/tmp/foreign-tooling'
    refuse { C.validate_native!(mutant) }
  end

  def test_matching_host_commit_evidence_is_not_selectable_or_artifact_only
    %w[pointer result readiness journal].each do |role|
      mutant = native; mutant['committed_host_' + role + '_path'] = '/private/tmp/other-generation'
      refuse { C.validate_native!(mutant) }
    end
  end

  def test_fresh_receipt_request_only_changes_current_tooling_generation
    producer = {
      'toolingRoot' => native['guard_tooling_root'], 'toolingCommit' => C::PRODUCER_COMMIT,
      'toolingTree' => C::PRODUCER_TREE, 'productCommit' => C::PRODUCT_COMMIT,
      'productTree' => C::PRODUCT_TREE, 'receiptPath' => '/private/tmp/original-receipt',
      'receiptSha256' => 'e' * 64, 'callerUid' => 501, 'timeoutSeconds' => 180
    }
    fresh = producer.merge('toolingCommit' => native['guard_tooling_commit'], 'toolingTree' => native['guard_tooling_tree'])
    assert C.validate_fresh_receipt_request!(native, fresh, producer)
    refuse { C.validate_fresh_receipt_request!(native, producer, producer) }
    producer.keys.each do |key|
      next if %w[toolingCommit toolingTree].include?(key)
      mutant = fresh.dup; mutant[key] = 'mutated'
      refuse { C.validate_fresh_receipt_request!(native, mutant, producer) }
    end
    mutant = fresh.dup; mutant['staleReceiptAccepted'] = true
    refuse { C.validate_fresh_receipt_request!(native, mutant, producer) }
  end

  def test_native_duplicate_unknown_control_and_non_utf8_refuse
    text = C.native_text(native)
    refuse { C.parse_native(text + 'caller_uid=501' + "\n") }
    refuse { C.parse_native(text + 'unknown=1' + "\n") }
    refuse { C.parse_native(text.sub('timeout_seconds=180', "timeout_seconds=180\r")) }
    refuse { C.parse_native(text.sub('timeout_seconds=180', 'timeout_seconds=180=1')) }
    refuse { C.parse_native(text.chomp) }
    refuse { C.parse_native(text.b.sub('driver-microphone-v9-offline-001', "driver-microphone-v9-\xff".b)) }
    refuse { C.parse_native(text.sub('/fixture/', '/fíxture/')) }
    mutant = native; mutant['nonce'] = mutant['host_nonce']
    refuse { C.native_text(mutant) }
    mutant = native; mutant['committed_host_result_path'] += '/'
    refuse { C.native_text(mutant) }
  end

  def test_namespace_and_numeric_bounds_are_not_coercible
    %w[driver-microphone-v9-../x driver-microphone-v9--x v17 /private/tmp/x].each do |value|
      mutant = native; mutant['namespace'] = value
      refuse { C.validate_native!(mutant) }
    end
    %w[0 -1 01 1.0 181 99999999999999].each do |value|
      mutant = native; mutant['timeout_seconds'] = value
      refuse { C.validate_native!(mutant) }
    end
    %w[0 -1 00 1.0].each do |value|
      mutant = native; mutant['host_pid'] = value
      refuse { C.validate_native!(mutant) }
    end
    mutant = native; mutant['predecessor_driver_instance'] = '18446744073709551615'
    assert_equal mutant, C.validate_native!(mutant)
    mutant['predecessor_driver_instance'] = '18446744073709551616'
    refuse { C.validate_native!(mutant) }
    mutant = native; mutant['host_pid'] = '2147483648'
    refuse { C.validate_native!(mutant) }
  end

  def test_strict_json_duplicate_nested_unknown_and_invalid_bytes
    refuse { C.parse_json('{"schema":1,"schema":2}') }
    refuse { C.parse_json('{"nested":{"x":1,"x":1}}') }
    refuse { C.parse_json("{\"x\":\"\xff\"}".b) }
    mutant = request; mutant['authority'] = true
    refuse { C.validate_request!(mutant) }
    mutant = request; mutant['tools']['worker']['extra'] = true
    refuse { C.validate_request!(mutant) }
  end

  def test_request_tool_crosslinks_and_fresh_receipt_crosslink
    assert_equal request, C.validate_request!(request)
    C::TOOL_ROLES.each do |role|
      mutant = request; mutant['tools'][role]['sha256'] = 'd' * 64
      refuse { C.validate_request!(mutant) }
    end
    mutant = request; mutant['freshBinding']['sha256'] = 'e' * 64
    refuse { C.validate_request!(mutant) }
  end

  def test_unchanged_original_product_verifier_rejects_expired_and_future_receipts
    product = '/Volumes/t7/beluga-quality-step.idpzQO/source'
    verifier = product + '/scripts/microphone-regression-gate.rb'
    signing = product + '/scripts/microphone-simulator-signing.rb'
    assert_equal 'fcc1bd5556b7dd52450d9e673b0c946ecf20e44357e700b4b0ab4ff707b84c85', Digest::SHA256.file(verifier).hexdigest
    assert_equal '749dd678af0da3b2a17473dc1820195d4dc5835acd04b53896ece0d38dbf339d', Digest::SHA256.file(signing).hexdigest
    require verifier
    root = File.realpath(Dir.mktmpdir('microphone-v9-expiry-unit-')); File.chmod(0700, root)
    path = root + '/receipt.json'
    receipt = %w[source tools simulator invocation mac_format phases artifacts coverage].to_h { |key| [key, {}] }
    receipt.merge!('schema' => MicrophoneRegressionGate::SCHEMA, 'status' => 'passed',
                   'scope' => 'offline-source-only', 'root' => root)
    [10_000 - 7 * 86400 - 1, 10_001].each do |created|
      receipt['created_at'] = created
      File.write(path, JSON.generate(receipt)); File.chmod(0600, path)
      error = assert_raises(RuntimeError) { MicrophoneRegressionGate.verify_receipt(path, Digest::SHA256.file(path).hexdigest, root, 10_000) }
      assert_equal 'future or expired receipt', error.message
    end
  ensure
    FileUtils.remove_entry_secure(root) if root && File.directory?(root)
  end

  def test_fresh_quiescent_gate_is_only_a_value_validation
    assert C.validate_gate!(native, gate, now_ms: 10_000)
    assert C.validate_gate!(native, gate, now_ms: 15_000)
    refuse { C.validate_gate!(native, gate, now_ms: 15_001) }
    refuse { C.validate_gate!(native, gate, now_ms: 9999) }
    assert_equal false, C::FIXED.key?('deploymentAuthority')
  end

  def test_each_live_peer_capture_and_guard_failure_refuses
    %w[peerConnected authenticatedPeer iceConnected controlOpen screenCaptureActive].each do |key|
      mutant = gate; mutant[key] = true
      refuse { C.validate_gate!(native, mutant, now_ms: 10_000) }
      mutant[key] = nil
      refuse { C.validate_gate!(native, mutant, now_ms: 10_000) }
    end
    %w[sessionBoundaryProven routeMonitorTeardownClean namespaceAbsent].each do |key|
      mutant = gate; mutant[key] = false
      refuse { C.validate_gate!(native, mutant, now_ms: 10_000) }
    end
  end

  def test_each_current_generation_route_and_terminal_drift_refuses
    gate.each do |key, value|
      next unless value.is_a?(String)
      mutant = gate; mutant[key] = value + 'x'
      refuse { C.validate_gate!(native, mutant, now_ms: 10_000) }
    end
    mutant = gate; mutant['routeNotifications'] = 1
    refuse { C.validate_gate!(native, mutant, now_ms: 10_000) }
    %w[SEALED_PREBUILT_ARTIFACT_NOT_DEPLOYED COMMITTED_CANDIDATE_UNVERIFIED pending-terminal].each do |value|
      mutant = gate; mutant['hostTerminal'] = value
      refuse { C.validate_gate!(native, mutant, now_ms: 10_000) }
    end
  end

  def test_mutation_free_file_fence_rejects_bad_bytes_mode_symlink_and_link
    root = File.realpath(Dir.mktmpdir('microphone-v9-contract-unit-'))
    File.chmod(0700, root)
    path = root + '/value.json'
    File.write(path, '{}'); File.chmod(0600, path)
    d = { 'path' => path, 'sha256' => Digest::SHA256.file(path).hexdigest }
    bytes, observed = C.read_file!(d, mode: 0600, maximum: 128)
    assert_equal '{}', bytes; assert_equal d['sha256'], observed['sha256']
    bad = d.merge('sha256' => 'f' * 64)
    refuse { C.read_file!(bad, mode: 0600) }
    File.chmod(0644, path)
    refuse { C.read_file!(d, mode: 0600) }
    File.chmod(0600, path)
    File.link(path, root + '/hardlink')
    refuse { C.read_file!(d, mode: 0600) }
    File.unlink(root + '/hardlink')
    File.symlink(path, root + '/alias')
    refuse { C.read_file!(d.merge('path' => root + '/alias'), mode: 0600) }
    refuse { C.read_file!(d, mode: 0600, maximum: 1) }
    refuse { C.read_file!(d, mode: 0600, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1) }
  ensure
    FileUtils.remove_entry_secure(root) if root && File.directory?(root)
  end

  def test_reviewed_bundle_byte_oracle_rejects_real_extra_node_mode_and_byte_mutants
    root = File.realpath(Dir.mktmpdir('microphone-v9-bundle-unit-')); File.chmod(0700, root)
    copy = root + '/OpensteamerVirtualMicrophone.driver'
    FileUtils.cp_r(C::ARTIFACT_ROOT + '/OpensteamerVirtualMicrophone.driver', copy)
    baseline = C.verify_bundle_bytes!(copy)
    assert_equal 11, baseline.length
    extra = copy + '/Contents/extra'
    File.write(extra, 'not part of signed layout'); File.chmod(0644, extra)
    refuse { C.verify_bundle_bytes!(copy) }
    File.unlink(extra)
    executable = copy + '/Contents/MacOS/OpensteamerVirtualMicrophone'
    File.chmod(0644, executable)
    refuse { C.verify_bundle_bytes!(copy) }
    File.chmod(0755, executable)
    bytes = File.binread(executable); bytes.setbyte(0, bytes.getbyte(0) ^ 1)
    File.binwrite(executable, bytes)
    refuse { C.verify_bundle_bytes!(copy) }
  ensure
    FileUtils.remove_entry_secure(root) if root && File.directory?(root)
  end

  def test_no_live_execution_or_root_dispatch_surface
    refuse { C.main(['--execute-authorized', '/private/tmp/request', 'a' * 64]) }
    source = File.read(__dir__ + '/opensteamer-microphone-v9-transaction-contract.rb')
    refute_match(/Process\.(?:spawn|kill)|sudo|launchctl|coreaudiod|installer\s+-pkg/, source)
  end

  def prepared_fixture
    root = File.realpath(Dir.mktmpdir('microphone-v9-final-unit-')); File.chmod(0700, root)
    make = lambda do |leaf, value, mode = 0600|
      bytes = value.is_a?(String) ? value : JSON.generate(value) + "\n"
      path = root + '/' + leaf
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, mode) { |file| file.write(bytes) }
      { 'path' => path, 'sha256' => Digest::SHA256.hexdigest(bytes) }
    end
    n = native
    producer = { 'toolingRoot' => n['guard_tooling_root'], 'toolingCommit' => C::PRODUCER_COMMIT, 'toolingTree' => C::PRODUCER_TREE }
    receipt = make.call('receipt.json', producer.merge('toolingCommit' => n['guard_tooling_commit'], 'toolingTree' => n['guard_tooling_tree']))
    static = make.call('static', 'immutable source evidence')
    static_identity = C.read_file!(static)[1]
    binding = make.call('binding.json', { 'inputs' => { 'fixture' => static_identity } })
    n['fresh_binding_sha256'] = binding['sha256']
    tools = C::TOOL_ROLES.zip(C::TOOL_DIGEST_KEYS).to_h do |role, key|
      d = make.call(role, 'offline executable ' + role, 0700); n[key] = d['sha256']; [role, d]
    end
    initial = { 'schema' => C::SCHEMA, 'nativeRequest' => n, 'receiptRequest' => receipt,
      'freshBinding' => binding, 'tools' => tools, 'gateObservation' => make.call('old-gate.json', gate(n)) }
    calls = []; clock = [Time.at(10)]
    artifacts = ->(**_options) { calls << :artifacts; [{ 'fixture' => static_identity }, producer] }
    revalidate = ->(_binding, _fresh) { calls << :receipt; clock[0] = Time.at(20); true }
    C.stub(:verify_artifacts!, artifacts) do
      OpensteamerMicrophoneReceiptBinding.stub(:revalidate, revalidate) do
        Time.stub(:now, -> { clock[0] }) { yield initial, make, static, calls, clock }
      end
    end
  ensure
    FileUtils.remove_entry_secure(root) if root && File.directory?(root)
  end

  def test_full_static_audits_precede_actual_fresh_collection_without_restamping_old_gate
    prepared_fixture do |initial, make, _static, calls, _clock|
      result = C.verify_with_fresh_collection(initial) do |prepared|
        assert_equal [:artifacts, :receipt, :artifacts], calls
        assert prepared.frozen?; assert prepared['nativeRequest'].frozen?
        actual = gate(prepared['nativeRequest']).merge('observedAtUnixMs' => 20_000)
        prepared.merge('gateObservation' => make.call('actual-fresh-gate.json', actual))
      end
      assert_equal false, result['deploymentAuthority']
      assert_equal 10_000, C.parse_json(File.binread(initial['gateObservation']['path']))['observedAtUnixMs']
      assert_equal 20_000, C.parse_json(File.binread(result['gateObservation']['path']))['observedAtUnixMs']
      assert_equal [:artifacts, :receipt, :artifacts], calls # No receipt CLI after collection.
    end
    prepared_fixture { |initial, _make, _static, _calls, _clock| refuse { C.verify(initial) } }
  end

  def test_final_gate_stale_future_reused_and_static_field_mutants_refuse
    [-1, 14_999, 20_001].each do |timestamp|
      prepared_fixture do |initial, make, _static, _calls, _clock|
        refuse do
          C.verify_with_fresh_collection(initial) { |prepared|
            prepared.merge('gateObservation' => make.call('bad-gate.json', gate(prepared['nativeRequest']).merge('observedAtUnixMs' => timestamp)))
          }
        end
      end
    end
    prepared_fixture { |initial, _make, _static, _calls, _clock| refuse { C.verify_with_fresh_collection(initial) { |prepared| prepared } } }
    prepared_fixture do |initial, make, _static, _calls, _clock|
      refuse do
        C.verify_with_fresh_collection(initial) { |prepared|
          changed = prepared['nativeRequest'].merge('host_pid' => '2')
          prepared.merge('nativeRequest' => changed, 'gateObservation' => make.call('drift-gate.json', gate(changed).merge('observedAtUnixMs' => 20_000)))
        }
      end
    end
  end

  def test_final_prepared_file_mutation_and_callback_failure_refuse
    prepared_fixture do |initial, make, static, _calls, _clock|
      refuse do
        C.verify_with_fresh_collection(initial) { |prepared|
          File.open(static['path'], 'ab') { |file| file.write(' changed') }
          prepared.merge('gateObservation' => make.call('fresh-gate.json', gate(prepared['nativeRequest']).merge('observedAtUnixMs' => 20_000)))
        }
      end
    end
    prepared_fixture do |initial, _make, _static, _calls, _clock|
      error = assert_raises(RuntimeError) { C.verify_with_fresh_collection(initial) { raise 'owned collection failed' } }
      assert_equal 'owned collection failed', error.message
    end
  end

  def test_internal_preparation_is_single_use_deadline_bound_and_not_a_selectable_token
    prepared_fixture do |initial, make, _static, _calls, _clock|
      context = C.send(:prepare_verification, initial)
      fresh = initial.merge('gateObservation' => make.call('fresh-gate.json', gate(initial['nativeRequest']).merge('observedAtUnixMs' => 20_000)))
      assert C.send(:finish_verification, context, fresh, refresh: true)
      refuse { C.send(:finish_verification, context, fresh, refresh: true) }
      refuse { C.send(:finish_verification, {}, fresh, refresh: true) }
    end
    prepared_fixture do |initial, make, _static, _calls, _clock|
      context = C.send(:prepare_verification, initial)
      context.instance_variable_set(:@deadline, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
      fresh = initial.merge('gateObservation' => make.call('fresh-gate.json', gate(initial['nativeRequest']).merge('observedAtUnixMs' => 20_000)))
      refuse { C.send(:finish_verification, context, fresh, refresh: true) }
    end
  end
end
