#!/usr/bin/env ruby
# Offline only. No sudo, root staging, CoreAudio call, host or HAL mutation.
require 'minitest/autorun'
require_relative 'run-opensteamer-microphone-v9-transaction'

class MicrophoneV9SupervisorTest < Minitest::Test
  S = BelugaMicrophoneV9Supervisor
  C = OpensteamerMicrophoneV9TransactionContract
  def native
    values = C::NATIVE_KEYS.to_h do |key|
      [key, if key.end_with?('_sha256') || %w[nonce host_nonce].include?(key)
              'a' * 64
            elsif key.end_with?('_commit', '_tree')
              'b' * 40
            elsif key.end_with?('_path', '_root')
              '/private/tmp/fixture-' + key
            else
              '1'
            end]
    end
    values.merge!(C::FIXED)
    values['namespace'] = 'driver-microphone-v9-offline-001'
    values['guard_tooling_root'] = File.realpath(__dir__ + '/../..')
    values['guard_tooling_commit'] = 'c' * 40
    values['timeout_seconds'] = '180'; values['host_nonce'] = 'd' * 64
    values['committed_host_pointer_path'] = C::HOST_ACTIVE_POINTER
    %w[result readiness journal].each { |role| values['committed_host_' + role + '_path'] = C::HOST_UPDATE_ROOT + '/fixture/' + role + '.txt' }
    values
  end
  def directory
    root = Dir.mktmpdir('beluga-v9-supervisor-offline.', '/private/tmp'); File.chmod(0700, root)
    yield root
  ensure
    FileUtils.remove_entry_secure(root) if root
  end
  def outcome
    { 'schema' => S::RUN_SCHEMA, 'namespace' => native['namespace'], 'request_sha256' => 'e' * 64,
      'terminal' => 'REFUSED', 'normal_restarts' => '0', 'rollback_restarts' => '0', 'reason' => 'LIVE_ADMISSION_DISABLED_PENDING_WHOLE_PATH_REVIEW' }
  end
  def flat(fields)
    fields.map { |key, value| "#{key}=#{value}\n" }.join
  end

  def test_typed_non_green_result_and_restart_budget_mutants
    assert_equal 'REFUSED', S.validate_outcome!(flat(outcome), native, 'e' * 64)['terminal']
    outcome.keys.each do |key|
      value = outcome.dup; value.delete(key)
      assert_raises(S::Refused) { S.validate_outcome!(flat(value), native, 'e' * 64) }
    end
    [ ['namespace', 'other'], ['request_sha256', 'f' * 64], ['terminal', 'PASSED_FIXTURE'],
      ['normal_restarts', '2'], ['rollback_restarts', '1'], ['normal_restarts', 'true'] ].each do |key, mutation|
      value = outcome.merge(key => mutation)
      assert_raises(S::Refused) { S.validate_outcome!(flat(value), native, 'e' * 64) }
    end
    assert_raises(S::Refused) { S.validate_outcome!(flat(outcome) + "terminal=COMMITTED_V9\n", native, 'e' * 64) }
    assert_raises(S::Refused) { S.validate_outcome!(flat(outcome).chomp, native, 'e' * 64) }
    %w[COMMITTED_V9 COMMITTED_V9_UNVERIFIED].each do |terminal|
      assert_raises(S::Refused) { S.validate_outcome!(flat(outcome.merge('terminal' => terminal)), native, 'e' * 64) }
      assert_equal terminal, S.validate_outcome!(flat(outcome.merge('terminal' => terminal, 'normal_restarts' => '1')), native, 'e' * 64)['terminal']
    end
    assert_raises(S::Refused) { S.validate_outcome!(flat(outcome.merge('terminal' => 'ROLLED_BACK_EXACT_V8', 'normal_restarts' => '1')), native, 'e' * 64) }
    assert_equal 'ROLLED_BACK_EXACT_V8', S.validate_outcome!(flat(outcome.merge('terminal' => 'ROLLED_BACK_EXACT_V8', 'normal_restarts' => '1', 'rollback_restarts' => '1')), native, 'e' * 64)['terminal']
  end

  def test_exact_sealed_execution_has_pre_exec_ancestry_and_no_existing_acl_mutation
    script = S.sealed_execution_script(native, '--execute-authorized', 'e' * 64, native['worker_sha256'])
    assert_includes script, '/usr/bin/shasum -a 256'
    assert_includes script, 'drwx--x--x '
    assert_includes script, '--execute-authorized'
    refute_match(/chmod|chown|mkdir|cp|launchctl|coreaudiod|kill|installer|\.pkg/, script)
    directory do |path|
      assert_equal '', S::Build::Commands.new(path).run('/bin/sh', '-n', '-c', script)
    end
    assert_raises(S::Refused) { S.sealed_execution_script(native, '--anything', 'e' * 64, native['worker_sha256']) }
  end

  def test_static_bootstrap_is_syntax_checked_but_never_executed
    script = S.bootstrap_script(native, '/Volumes/t7/fixture/request.txt', 'e' * 64,
      '/private/tmp/beluga-microphone-v9-guards.offline/build-proof.json', 'f' * 64,
      '/private/tmp/beluga-microphone-v9-guards.offline/transaction')
    assert_includes script, '/usr/bin/shasum -a 256'
    assert_includes script, '--seal-authorized-v9-inputs'
    refute_match(/launchctl|coreaudiod|kill|installer|\.pkg|HAL/, script)
    directory do |path|
      assert_equal '', S::Build::Commands.new(path).run('/bin/sh', '-n', '-c', script)
    end
    assert_raises(S::Refused) { S.bootstrap_script(native, '/private/tmp/request', 'e' * 64,
      '/private/tmp/beluga-microphone-v9-guards.offline/build-proof.json', 'f' * 64,
      '/private/tmp/beluga-microphone-v9-guards.offline/transaction') }
  end

  def test_actual_owned_dispatcher_returns_nonzero_and_logs_without_success_claim
    directory do |path|
      session = S::OwnedSession.new(path, seconds: 1)
      stdout, stderr, status = session.run(['/usr/bin/ruby', '-e', 'STDOUT.write("offline"); exit 7'])
      assert_equal 'offline', stdout; assert_equal '', stderr; assert_equal 7, status.exitstatus
      assert_nil session.pid; assert_nil session.abort_reason
      assert_equal 0600, File.stat(session.records[0]['stdout']).mode & 0777
    end
  end

  def test_deadline_sends_one_abort_and_child_is_actually_reaped
    directory do |path|
      session = S::OwnedSession.new(path, seconds: 0.05, recovery_seconds: 1)
      stdout, stderr, status = session.run(['/usr/bin/ruby', '-e', 'line=STDIN.gets; exit 4 unless line=="ABORT\n"; exit 5 unless STDIN.read.empty?; STDOUT.write("aborted"); exit 0'])
      assert_equal 'aborted', stdout; assert_equal '', stderr; assert status.success?
      assert_equal 'DEADLINE', session.abort_reason
      assert_raises(Errno::ECHILD) { Process.waitpid(session.records[0]['pid'], Process::WNOHANG) }
    end
  end

  def test_explicit_interruption_uses_same_abort_not_process_kill
    directory do |path|
      session = S::OwnedSession.new(path, seconds: 2, recovery_seconds: 1)
      session.abort!('INT'); session.abort!('TERM')
      stdout, stderr, status = session.run(['/usr/bin/ruby', '-e', 'STDOUT.write(STDIN.read); exit 0'])
      assert_equal "ABORT\n", stdout; assert_equal '', stderr; assert status.success?
      assert_equal 'INT', session.abort_reason
    end
  end

  def test_initial_execute_revalidates_original_receipt_not_a_cached_marker
    directory do |path|
      make = ->(name, value) {
        target = File.join(path, name); bytes = JSON.generate(value) + "\n"
        File.open(target, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(bytes) }
        { 'path' => target, 'sha256' => Digest::SHA256.hexdigest(bytes) }
      }
      producer = C.parse_json(File.binread(C::ARTIFACT_ROOT + '/binding-request.json'))
      binding = { 'offlineFixtureOnly' => true, 'deploymentAuthority' => false }
      binding_descriptor = make.call('binding.json', binding)
      n = native; n['fresh_binding_sha256'] = binding_descriptor['sha256']
      fresh = producer.merge('toolingRoot' => n['guard_tooling_root'], 'toolingCommit' => n['guard_tooling_commit'], 'toolingTree' => n['guard_tooling_tree'])
      fresh_descriptor = make.call('fresh-request.json', fresh)
      coordinator = { 'schema' => C::SCHEMA, 'nativeRequest' => n, 'receiptRequest' => fresh_descriptor,
        'freshBinding' => binding_descriptor, 'gateObservation' => { 'path' => '/private/tmp/unused-stale-gate', 'sha256' => 'a' * 64 },
        'tools' => C::TOOL_ROLES.to_h { |role| [role, { 'path' => '/private/tmp/' + role, 'sha256' => 'a' * 64 }] } }
      coordinator_descriptor = make.call('coordinator.json', coordinator)
      request_path = File.join(path, 'native-request.txt'); request_bytes = C.native_text(n)
      File.open(request_path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(request_bytes) }
      request_sha = Digest::SHA256.hexdigest(request_bytes)
      make.call('dispatch-inputs.json', { 'schema' => 'opensteamer.microphone-v9-dispatch-inputs.v1',
        'coordinator' => coordinator_descriptor, 'buildManifest' => { 'path' => '/private/tmp/unused-build', 'sha256' => 'f' * 64 },
        'nativeRequest' => { 'path' => request_path, 'sha256' => request_sha } })
      manifest = %w[productCommit productTree guardToolingCommit guardToolingTree].zip(%w[product_commit product_tree guard_tooling_commit guard_tooling_tree]).to_h { |key, native_key| [key, n[native_key]] }
      manifest['tools'] = coordinator['tools']
      calls = []
      S::Build.stub(:audit_build!, manifest) do
        OpensteamerMicrophoneReceiptBinding.stub(:revalidate, ->(actual_binding, actual_fresh) {
          calls << [actual_binding, actual_fresh]; true
        }) do
          assert S.fresh_execute_inputs!(request_path, request_sha, n, Object.new)
          assert_equal [[binding, fresh]], calls
          assert_raises(S::Refused) { S.fresh_execute_inputs!(request_path, '0' * 64, n, Object.new) }
          assert_equal 1, calls.size
        end
      end
    end
  end
end
