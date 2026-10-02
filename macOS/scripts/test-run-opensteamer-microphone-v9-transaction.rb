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
    script = S.bootstrap_script(native, '/private/tmp/beluga-microphone-v9-supervisor.offline-001/native-request.txt', 'e' * 64,
      '/private/tmp/beluga-microphone-v9-guards.offline/build-proof.json', 'f' * 64,
      '/private/tmp/beluga-microphone-v9-guards.offline/transaction')
    assert_includes script, '/usr/bin/shasum -a 256'
    assert_includes script, '--seal-authorized-v9-inputs'
    refute_match(/launchctl|coreaudiod|kill|installer|\.pkg|HAL/, script)
    directory do |path|
      assert_equal '', S::Build::Commands.new(path).run('/bin/sh', '-n', '-c', script)
    end
    %w[/Volumes/t7/fixture/native-request.txt /private/tmp/request /tmp/beluga-microphone-v9-supervisor.fixture/native-request.txt
       /private/tmp/beluga-microphone-v9-supervisor./native-request.txt /private/tmp/beluga-microphone-v9-supervisor.fixture/request.txt
       /private/tmp/beluga-microphone-v9-supervisor.fixture/other/native-request.txt
       /private/tmp/beluga-microphone-v9-supervisor.fixture/../native-request.txt
       /private/tmp/beluga-microphone-v9-supervisor.fixture!/native-request.txt].each do |request|
      assert_raises(S::Refused, C::Refusal) { S.bootstrap_script(native, request, 'e' * 64,
        '/private/tmp/beluga-microphone-v9-guards.offline/build-proof.json', 'f' * 64,
        '/private/tmp/beluga-microphone-v9-guards.offline/transaction') }
    end
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

  def seal_fixture
    directory do |path|
      make = lambda do |name, value, mode = 0600|
        target = File.join(path, name); bytes = value.is_a?(String) ? value : JSON.generate(value) + "\n"
        File.open(target, File::WRONLY | File::CREAT | File::EXCL, mode) { |file| file.write(bytes) }
        { 'path' => target, 'sha256' => Digest::SHA256.hexdigest(bytes) }
      end
      n = native; tools = C::TOOL_ROLES.to_h { |role| [role, make.call(role, role, 0700)] }
      C::TOOL_ROLES.zip(C::TOOL_DIGEST_KEYS).each { |role, key| n[key] = tools[role]['sha256'] }
      binding = make.call('binding.json', {}); n['fresh_binding_sha256'] = binding['sha256']
      gate = lambda do |ms|
        mappings = %w[namespace nonce hostPid hostStartIdentitySha256 hostNonce hostLockDevice hostLockInode hostLaunchdRuns hostDisplayIdentitySha256 hostExecutableSha256 predecessorDriverInstance predecessorDriverDevice predecessorDriverInode predecessorDriverExecutableSha256 inputUid outputUid systemOutputUid].zip(
          %w[namespace nonce host_pid host_start_identity_sha256 host_nonce host_lock_device host_lock_inode host_launchd_runs host_display_identity_sha256 host_executable_sha256 predecessor_driver_instance predecessor_driver_device predecessor_driver_inode predecessor_driver_executable_sha256 input_uid output_uid system_output_uid])
        mappings.to_h { |key, pinned| [key, n.fetch(pinned)] }.merge(
          'schema' => 'opensteamer.microphone-v9-quiescent-observation.v1', 'observedAtUnixMs' => ms,
          'peerConnected' => false, 'authenticatedPeer' => false, 'iceConnected' => false,
          'controlOpen' => false, 'screenCaptureActive' => false, 'sessionBoundaryProven' => true,
          'routeNotifications' => 0, 'routeMonitorTeardownClean' => true,
          'hostTerminal' => 'COMMITTED_CANDIDATE', 'namespaceAbsent' => true)
      end
      initial = { 'schema' => C::SCHEMA, 'nativeRequest' => n, 'receiptRequest' => make.call('receipt.json', {}),
        'freshBinding' => binding, 'gateObservation' => make.call('old-gate.json', gate.call(100_000)), 'tools' => tools }
      initial_descriptor = make.call('initial.json', initial)
      manifest = %w[productCommit productTree guardToolingCommit guardToolingTree].zip(%w[product_commit product_tree guard_tooling_commit guard_tooling_tree]).to_h { |key, pinned| [key, n[pinned]] }
      manifest['tools'] = tools.transform_values { |entry| S::Build.file_record(entry['path']) }
      manifest['sources'] = {}; manifest['sealedInputs'] = {}
      manifest['originalInputs'] = {}; manifest['releaseInputs'] = {}
      manifest['reusedTools'] = { 'buildProof' => S::Build.file_record(tools['worker']['path']), 'tools' => {} }
      %w[swiftCompiler rustCompiler sdkSettings].each { |key| manifest[key] = S::Build.file_record(tools['worker']['path']) }
      manifest_descriptor = make.call('manifest.json', manifest)
      events = []; clock = [Time.at(100)]; dispatched = []; evidence_path = nil
      verification = lambda do |request|
        native_bytes = C.native_text(request.fetch('nativeRequest'))
        { 'nativeRequest' => native_bytes, 'nativeRequestSha256' => Digest::SHA256.hexdigest(native_bytes),
          'gateObservation' => C.read_file!(request.fetch('gateObservation'), mode: 0600, maximum: C::MAX_JSON)[1] }
      end
      session_factory = lambda do |evidence, **_options|
        session = Object.new
        session.define_singleton_method(:abort_reason) { nil }
        session.define_singleton_method(:abort!) { |_reason| }
        session.define_singleton_method(:run) do |argv|
          events << :dispatch; dispatched << argv
          preparation = C.parse_json(File.binread(File.join(evidence, 'dispatch-inputs.json')))
          fields = { 'schema' => S::SEAL_SCHEMA, 'namespace' => n['namespace'], 'nonce' => n['nonce'],
            'request_sha256' => preparation['nativeRequest']['sha256'], 'build_manifest_sha256' => manifest_descriptor['sha256'],
            'worker_sha256' => n['worker_sha256'], 'terminal' => 'SEALED_INPUTS_NOT_INSTALLED', 'authority_sha256' => 'e' * 64 }
          [fields.map { |key, value| "#{key}=#{value}\n" }.join, '', Struct.new(:success?).new(true)]
        end
        session
      end
      audit = lambda { |*_arguments| events << :audit; clock[0] = Time.at(200); manifest }
      fresh_verification = lambda do |request, &callback|
        events << :prepare
        fresh = callback.call(C.freeze_tree(C.parse_json(JSON.generate(request))))
        events << :finish
        assert File.file?(File.join(evidence_path, 'dispatch-inputs.json')), 'private persistence must precede final Contract fences'
        C.validate_gate!(n, C.parse_json(File.binread(fresh['gateObservation']['path'])), now_ms: (clock[0].to_r * 1000).to_i)
        verification.call(fresh)
      end
      original_mktemp = Dir.method(:mktmpdir)
      mktemp = lambda do |prefix, parent|
        assert_equal '/private/tmp', parent
        evidence_path = original_mktemp.call(prefix, parent)
      end
      S.stub(:original_uid!, nil) do
        S::Build.stub(:audit_build!, audit) do
          S.stub(:local_source_generation!, ->(*_arguments) { events << :source }) do
            S.stub(:bootstrap_script, 'offline-never-executed') do
              S::OwnedSession.stub(:new, session_factory) do
                Dir.stub(:mktmpdir, mktemp) do
                  Time.stub(:now, -> { clock[0] }) do
                    C.stub(:verify_with_fresh_collection, fresh_verification) do
                      yield initial, initial_descriptor, manifest_descriptor, make, gate, events, clock, dispatched, verification
                    end
                  end
                end
              end
            end
          end
        end
      end
    ensure
      FileUtils.remove_entry_secure(evidence_path) if evidence_path
    end
  end

  def test_slow_audits_precede_fresh_collection_and_final_fences_follow_private_fsync
    seal_fixture do |initial, descriptor, manifest, make, gate, events, _clock, dispatched, _verify|
      fresh_descriptor = nil
      result = S.seal!(descriptor['path'], descriptor['sha256'], manifest['path'], manifest['sha256'], collect_fresh: lambda { |prepared|
        events << :collect; assert prepared.frozen?; assert prepared['nativeRequest'].frozen?
        fresh_descriptor = make.call('fresh.json', initial.merge('gateObservation' => make.call('new-gate.json', gate.call(200_000))))
      })
      assert_equal [:audit, :prepare, :collect, :source, :finish, :dispatch], events
      assert_equal 1, dispatched.size
      refute result['deploymentAuthority']; refute result['liveInstalled']
      preparation = C.parse_json(File.binread(File.join(result['evidence'], 'dispatch-inputs.json')))
      assert_equal fresh_descriptor, preparation['coordinator']
      assert_equal 100_000, C.parse_json(File.binread(initial['gateObservation']['path']))['observedAtUnixMs']
    end
  end

  def test_callback_failure_static_drift_and_stale_after_persistence_never_dispatch
    [:failure, :drift, :stale, :request_replacement].each do |kind|
      seal_fixture do |initial, descriptor, manifest, make, gate, _events, clock, dispatched, _verify|
        persist = S.method(:persist_dispatch_inputs!)
        persistence = lambda do |*arguments|
          value = persist.call(*arguments); clock[0] = Time.at(206) if kind == :stale
          if kind == :request_replacement
            replacement = make.call('native-replacement.txt', File.binread(value[0]))
            File.rename(replacement['path'], value[0])
          end
          value
        end
        S.stub(:persist_dispatch_inputs!, persistence) do
          error = assert_raises(kind == :failure ? RuntimeError : (kind == :stale ? C::Refusal : S::Refused)) do
            S.seal!(descriptor['path'], descriptor['sha256'], manifest['path'], manifest['sha256'], collect_fresh: lambda { |_prepared|
              raise 'owned collector failed' if kind == :failure
              fresh = initial.merge('gateObservation' => make.call('new-gate.json', gate.call(200_000)))
              fresh = fresh.merge('nativeRequest' => fresh['nativeRequest'].merge('host_pid' => '2')) if kind == :drift
              make.call('fresh.json', fresh)
            })
          end
          assert_equal 'owned collector failed', error.message if kind == :failure
          assert_empty dispatched
        end
      end
    end
  end

  def test_same_byte_manifest_inode_replacement_never_dispatches
    seal_fixture do |initial, descriptor, manifest, make, gate, _events, _clock, dispatched, _verify|
      assert_raises(S::Refused) do
        S.seal!(descriptor['path'], descriptor['sha256'], manifest['path'], manifest['sha256'], collect_fresh: lambda { |_prepared|
          replacement = make.call('manifest-replacement.json', File.binread(manifest['path']))
          File.rename(replacement['path'], manifest['path'])
          make.call('fresh.json', initial.merge('gateObservation' => make.call('new-gate.json', gate.call(200_000))))
        })
      end
      assert_empty dispatched
    end
  end

  def test_manifest_v2_original_release_and_reused_records_reject_same_byte_inode_replacement
    %w[original release reusedProof reusedTool].each do |changed_role|
      directory do |path|
        records = %w[compiler original release reusedProof reusedTool].to_h do |role|
          target = File.join(path, role)
          File.open(target, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write('same bytes') }
          [role, S::Build.file_record(target)]
        end
        manifest = { 'sources' => {}, 'tools' => {}, 'sealedInputs' => {},
          'originalInputs' => { 'original' => records.fetch('original') },
          'releaseInputs' => { 'release' => records.fetch('release') },
          'reusedTools' => { 'buildProof' => records.fetch('reusedProof'), 'tools' => { 'worker' => records.fetch('reusedTool') } } }
        %w[swiftCompiler rustCompiler sdkSettings].each { |role| manifest[role] = records.fetch('compiler') }
        assert S.manifest_identity_fence!(manifest)
        record = records.fetch(changed_role); replacement = File.join(path, 'replacement')
        File.open(replacement, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write('same bytes') }
        File.rename(replacement, record.fetch('path'))
        assert_equal record.fetch('sha256'), Digest::SHA256.file(record.fetch('path')).hexdigest
        refute_equal record.fetch('identity')[1], File.lstat(record.fetch('path')).ino
        assert_raises(S::Refused) { S.manifest_identity_fence!(manifest) }
      end
    end
  end

  def test_standalone_stale_seal_and_changed_local_source_still_refuse
    seal_fixture do |initial, descriptor, manifest, _make, _gate, _events, clock, dispatched, _verify|
      C.stub(:verify, lambda { |request|
        C.validate_gate!(request['nativeRequest'], C.parse_json(File.binread(initial['gateObservation']['path'])), now_ms: (clock[0].to_r * 1000).to_i)
      }) do
        assert_raises(C::Refusal) { S.seal!(descriptor['path'], descriptor['sha256'], manifest['path'], manifest['sha256']) }
      end
      assert_empty dispatched
    end
    commands = Object.new; commands.define_singleton_method(:run) { |*_arguments| 'different' }
    assert_raises(S::Refused) { S.local_source_generation!({ 'productCommit' => 'a' * 40, 'productTree' => 'b' * 40 }, commands) }
  end

  def internal_directory
    path = Dir.mktmpdir('beluga-microphone-v9-supervisor.offline-', '/private/tmp'); File.chmod(0700, path)
    held = File.open(path, File::RDONLY | File::NOFOLLOW)
    commands = Object.new; commands.define_singleton_method(:run) { |*_arguments| 'drwx------  2 ahmed staff fixture' + "\n" }
    yield path, held, commands
  ensure
    held&.close
    FileUtils.remove_entry_secure(path) if path && File.exist?(path)
    FileUtils.remove_entry_secure(path + '-held') if path && File.exist?(path + '-held')
  end

  def test_internal_directory_exact_owner_mode_acl_and_held_inode_fences
    internal_directory do |path, held, commands|
      identity = S.internal_directory_fence!(path, held, nil, commands)
      assert_equal 501, identity[2]
      assert_equal identity, S.internal_directory_fence!(path, held, identity, commands)
      File.chmod(0755, path)
      assert_raises(S::Refused) { S.internal_directory_fence!(path, held, identity, commands) }
      File.chmod(0700, path)
      commands.define_singleton_method(:run) { |*_arguments| "drwx------+ 2 ahmed staff fixture\n 0: user:other allow read\n" }
      assert_raises(S::Refused) { S.internal_directory_fence!(path, held, identity, commands) }
    end
    internal_directory do |path, held, commands|
      identity = S.internal_directory_fence!(path, held, nil, commands)
      File.rename(path, path + '-held'); Dir.mkdir(path, 0700)
      assert_raises(S::Refused) { S.internal_directory_fence!(path, held, identity, commands) }
    end
  end

  def test_internal_directory_alias_wrong_owner_and_unknown_request_roles_refuse
    internal_directory do |path, held, commands|
      before = File.lstat(path); wrong_owner = before.dup
      wrong_owner.define_singleton_method(:uid) { 0 }
      original_stat = File.method(:lstat)
      File.stub(:lstat, ->(target) { target == path ? wrong_owner : original_stat.call(target) }) do
        assert_raises(S::Refused) { S.internal_directory_fence!(path, held, nil, commands) }
      end
      File.rename(path, path + '-held'); File.symlink(path + '-held', path)
      assert_raises(S::Refused) { S.internal_directory_fence!(path, held, nil, commands) }
      File.unlink(path); File.rename(path + '-held', path)
      assert_raises(S::Refused) { S.internal_directory_fence!('/private/tmp/arbitrary', held, nil, commands) }
    end
    S.stub(:original_uid!, nil) do
      assert_raises(S::Refused) { S.execute!('--execute-authorized', '/Volumes/t7/old-attempt/native-request.txt', 'a' * 64, 'b' * 64) }
      assert_raises(S::Refused) { S.execute!('--resume-authorized', '/private/tmp/arbitrary/native-request.txt', 'a' * 64, 'b' * 64) }
    end
  end
end
