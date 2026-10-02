#!/usr/bin/env ruby
require 'minitest/autorun'
require_relative 'build-opensteamer-microphone-v9-guards'

class MicrophoneV9GuardBuilderTest < Minitest::Test
  Build = BelugaMicrophoneV9GuardBuild
  def with_directory
    path = Dir.mktmpdir('beluga-v9-builder-offline.', '/private/tmp'); File.chmod(0700, path)
    yield path
  ensure
    # Only this test's exact fresh private directory, never a workspace/service.
    FileUtils.remove_entry_secure(path) if path
  end

  def test_actual_bounded_command_and_empty_logs
    with_directory do |path|
      commands = Build::Commands.new(path)
      assert_equal '', commands.run('/usr/bin/true')
      assert_equal 'offline', commands.run('/usr/bin/printf', '%s', 'offline')
      assert_equal 2, commands.records.size
      commands.records.each do |record|
        assert_equal false, record['timedOutOrLogBound']; assert_equal 0, record['exitStatus']
        %w[stdout stderr].each do |key|
          assert_equal record[key]['sha256'], Digest::SHA256.file(record[key]['path']).hexdigest
          assert_equal 0600, File.stat(record[key]['path']).mode & 0777
        end
      end
    end
  end

  def test_nonzero_actual_child_is_not_a_build
    with_directory do |path|
      commands = Build::Commands.new(path)
      assert_raises(Build::Refused) { commands.run('/usr/bin/false') }
      assert_equal 1, commands.records.size
      assert_equal 1, commands.records[0]['exitStatus']
    end
  end

  def test_launcher_interrupt_terminates_and_reaps_its_actual_owned_child
    with_directory do |path|
      commands = Build::Commands.new(path)
      thread = Thread.new { commands.run('/bin/sleep', '30') }
      thread.report_on_exception = false
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      sleep 0.005 until commands.active_pid || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      pid = commands.active_pid
      refute_nil pid
      thread.raise(Interrupt, 'offline launcher interrupt')
      assert_raises(Interrupt) { thread.value }
      assert_nil commands.active_pid
      assert_raises(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) }
      assert File.file?(File.join(path, '001.stdout'))
      assert File.file?(File.join(path, '001.stderr'))
    end
  end

  def test_early_leader_exit_cannot_leave_a_descendant_or_become_a_green_build
    with_directory do |path|
      commands = Build::Commands.new(path)
      code = "pid = Process.spawn('/bin/sleep', '30'); STDOUT.write(pid.to_s); STDOUT.flush; exit! 0"
      assert_raises(Build::Refused) { commands.run('/usr/bin/ruby', '-e', code) }
      descendant = File.binread(File.join(path, '001.stdout')).to_i
      assert_operator descendant, :>, 0
      assert_nil commands.active_pid
      # A dead reparented descendant may remain a launchd-owned zombie briefly;
      # the builder cannot reap a process which is no longer its direct child.
      gone = false; deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      until gone || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        begin Process.getpgid(descendant); rescue Errno::ESRCH; gone = true; end
        sleep 0.005 unless gone
      end
      unless gone
        state, status = Open3.capture2e(Build::SAFE_ENV, '/bin/ps', '-p', descendant.to_s, '-o', 'stat=', unsetenv_others: true)
        assert status.success? && state.strip.start_with?('Z'), "owned descendant cleanup: pid=#{descendant} status=#{status.exitstatus} state=#{state.inspect} pgid=#{Process.getpgid(descendant)}"
      end
      assert gone || !Build::OwnedDarwinChild.other_members(commands.records[0]['pid']).include?(descendant),
             'owned descendant remains an active process-group member'
    end
  end

  def test_build_input_bytes_identity_mode_and_alias_refusals
    with_directory do |path|
      input = File.join(path, 'input')
      File.open(input, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write('offline') }
      digest = Digest::SHA256.hexdigest('offline')
      assert_equal digest, Build.file_record(input, digest: digest)['sha256']
      assert_raises(Build::Refused) { Build.file_record(input, digest: 'a' * 64) }
      File.chmod(0620, input)
      assert_raises(Build::Refused) { Build.file_record(input) }
      File.chmod(0600, input)
      File.symlink(input, File.join(path, 'alias'))
      assert_raises(Build::Refused) { Build.file_record(File.join(path, 'alias')) }
      File.link(input, File.join(path, 'link'))
      assert_raises(Build::Refused) { Build.file_record(input) }
    end
  end

  def test_build_input_growing_read_refuses_at_pinned_extent
    with_directory do |path|
      input = File.join(path, 'input')
      File.open(input, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write('offline') }
      actual_open = File.method(:open); reads = 0
      replacement = lambda do |*arguments, &block|
        actual_open.call(*arguments) do |file|
          file.define_singleton_method(:read) { |_maximum| reads += 1; 'growing!' }
          block.call(file)
        end
      end
      File.stub(:open, replacement) do
        assert_raises(Build::Refused) { Build.file_record(input) }
      end
      assert_equal 1, reads
      assert_equal 'offline', File.binread(input)
    end
  end

  def test_leader_exit_between_nonreaping_wait_and_group_check_is_contained
    with_directory do |path|
      output = File.open(File.join(path, 'child'), 'w')
      leader = Process.spawn(Build::SAFE_ENV, '/usr/bin/ruby', '-e',
        "pid = Process.spawn('/bin/sleep', '30'); STDOUT.write(pid.to_s); STDOUT.flush; exit! 0",
        unsetenv_others: true, pgroup: true, out: output)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      sleep 0.005 until Build::OwnedDarwinChild.exited?(leader) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      assert Build::OwnedDarwinChild.exited?(leader)
      descendant = File.binread(File.join(path, 'child')).to_i
      original_wait = Build::OwnedDarwinChild.method(:exited?); reads = 0
      Build::OwnedDarwinChild.stub(:exited?, ->(pid) { reads += 1; reads == 1 ? false : original_wait.call(pid) }) do
        Process.stub(:getpgid, ->(_pid) { raise Errno::ESRCH }) do
          assert Build::Commands.new(path).terminate_owned!(leader).success?
        end
      end
      assert_raises(Errno::ECHILD) { Process.waitpid(leader, Process::WNOHANG) }
      assert !Build::OwnedDarwinChild.other_members(leader).include?(descendant)
    ensure
      output&.close
    end
  end

  class GitFixture
    attr_accessor :mutate
    def run(*argv)
      root = argv[2]; arguments = argv[3..-1]
      value = case arguments
              when ['rev-parse', 'HEAD'] then root == Build::PRODUCT ? Build::PRODUCT_COMMIT : 'b' * 40
              when ['rev-parse', 'HEAD^{tree}'] then root == Build::PRODUCT ? Build::PRODUCT_TREE : 'c' * 40
              when ['status', '--porcelain=v1', '--untracked-files=all'] then ''
              when ['symbolic-ref', '--short', 'HEAD'] then Build::BRANCH
              when ['rev-parse', '@{u}'] then 'b' * 40
              when ['remote', 'get-url', '--all', 'origin'], ['remote', 'get-url', '--push', '--all', 'origin'] then Build::REMOTE
              when ['ls-remote', '--exit-code', '--refs', '--heads', 'origin', 'refs/heads/' + Build::BRANCH]
                'b' * 40 + "\trefs/heads/" + Build::BRANCH
              else raise 'unreviewed fixture command'
              end
      @mutate ? @mutate.call(root, arguments, value) : value
    end
  end

  def test_clean_exact_source_fixture_and_changed_source_refusals
    fixture = GitFixture.new
    assert_equal Build::PRODUCT_COMMIT, Build.source_proof!(fixture)['productCommit']
    [
      [Build::PRODUCT, ['rev-parse', 'HEAD'], 'a' * 40],
      [Build::PRODUCT, ['status', '--porcelain=v1', '--untracked-files=all'], ' M driver.c'],
      [Build::ROOT, ['status', '--porcelain=v1', '--untracked-files=all'], '?? untracked.rs'],
      [Build::ROOT, ['rev-parse', '@{u}'], 'a' * 40],
      [Build::ROOT, ['remote', 'get-url', '--push', '--all', 'origin'], 'https://example.invalid/other'],
      [Build::ROOT, ['ls-remote', '--exit-code', '--refs', '--heads', 'origin', 'refs/heads/' + Build::BRANCH], 'wrong']
    ].each do |root, arguments, value|
      fixture.mutate = ->(actual_root, actual_arguments, original) { actual_root == root && actual_arguments == arguments ? value : original }
      assert_raises(Build::Refused) { Build.source_proof!(fixture) }
    end
  end

  def test_sealed_observer_inputs_are_exact_read_only_byte_records
    records = Build.sealed_inputs!
    gate = BelugaMicrophoneV9HostGate
    expected = ['tools/opensteamer-microphone-v9-host-gate.rb'] +
      gate::PRODUCT_PINS.keys.map { |name| 'tools/product/' + name } +
      gate::OBSERVER_PINS.keys.map { |name| 'tools/observers/' + name }
    assert_equal expected.sort, records.keys.sort
    records.each do |relative, record|
      assert_equal %w[identity path sha256], record.keys.sort
      assert_equal 501, record.fetch('identity')[2]
      assert_equal 11, record.fetch('identity').size
      assert_equal File.realpath(record.fetch('path')), record.fetch('path')
      assert_equal Digest::SHA256.file(record.fetch('path')).hexdigest, record.fetch('sha256')
      refute relative.include?('select-live-display')
    end
  end

  def test_exact_compiler_recipes_and_full_source_closure_are_required
    root = '/private/tmp/beluga-microphone-v9-guards.offline'
    [false, true].each do |legacy|
      paths = legacy ? Build.legacy_source_paths : Build.source_paths
      recipes = legacy ? Build.legacy_compile_recipes(root) : Build.compile_recipes(root)
      fixture = { 'sources' => (paths + [root + '/public/main.swift']).to_h { |path| [path, nil] },
                  'commands' => recipes.map { |argv| { 'argv' => argv } } }
      assert Build.audit_recipes!(fixture, root, legacy: legacy)
      mutants = [
        ->(value) { value['sources'].delete(paths.first) },
        ->(value) { value['sources']['/private/tmp/foreign.swift'] = nil },
        ->(value) { value['commands'][0]['argv'] = ['/usr/bin/true'] },
        ->(value) { value['commands'][0]['argv'].delete('warnings') },
        ->(value) { value['commands'][0]['argv'][-1] = root + '/not-the-worker' },
        ->(value) { value['commands'] << value['commands'][0] },
        ->(value) { value['commands'] << { 'argv' => ['/bin/sh', '-c', 'true'] } }
      ]
      if legacy
        mutants += [
          ->(value) { value['commands'][1]['argv'].delete('-warnings-as-errors') },
          ->(value) { value['commands'][2]['argv'][-1] = root + '/not-the-probe' },
          ->(value) { value['commands'].reverse! }
        ]
      else
        mutants << ->(value) { value['commands'] << { 'argv' => Build.legacy_compile_recipes(root)[1] } }
      end
      mutants.each do |mutation|
        value = Marshal.load(Marshal.dump(fixture)); mutation.call(value)
        assert_raises(Build::Refused) { Build.audit_recipes!(value, root, legacy: legacy) }
      end
    end
    assert_includes Build.source_paths, Build::ROOT + '/macOS/scripts/opensteamer-microphone-v9-input-staging.rb'
    assert_equal [Build::RUSTC], Build.compile_recipes(root).map(&:first)
  end

  def reuse_fixture
    root = File.dirname(Build::REUSE_PROOF); records = {}; inode = 10
    make = lambda do |path, sha = ('a' * 64), mode = 0644, size = 1|
      inode += 1
      records[path] = { 'path' => path, 'sha256' => sha, 'identity' => [1, inode, 501, 20, 0100000 | mode, 1, size, 1, 0, 1, 0] }
    end
    sources = (Build.legacy_source_paths + [root + '/public/main.swift']).to_h { |path| [path, make.call(path)] }
    sources[Build::DECODER] = make.call(Build::DECODER, Build::DECODER_SHA)
    sources[Build::MONITOR] = make.call(Build::MONITOR, Build::MONITOR_SHA)
    tools = { 'worker' => 'transaction' }.merge(Build::REUSED_ROLES).to_h { |role, name| [role, make.call(root + '/' + name, 'b' * 64, 0755)] }
    commands = Build.legacy_compile_recipes(root).each_with_index.map do |argv, index|
      logs = %w[stdout stderr].to_h { |channel| [channel, make.call(root + '/commands/' + format('%03d.%s', index + 1, channel), Digest::SHA256.hexdigest(''), 0600, 0)] }
      { 'argv' => argv, 'pid' => index + 1, 'exitStatus' => 0, 'termSignal' => nil, 'timedOutOrLogBound' => false }.merge(logs)
    end
    proof = { 'schema' => 'opensteamer.microphone-v9.native-guard-build.v1', 'deploymentAuthority' => false,
      'liveQueriesPerformed' => false, 'productCommit' => Build::PRODUCT_COMMIT, 'productTree' => Build::PRODUCT_TREE,
      'guardToolingCommit' => Build::REUSE_COMMIT, 'guardToolingTree' => Build::REUSE_TREE,
      'sources' => sources, 'tools' => tools, 'commands' => commands, 'sealedInputs' => {} }
    proof['swiftCompiler'] = make.call(Build::SWIFTC, Build::SWIFT_SHA)
    proof['rustCompiler'] = make.call(Build::RUSTC, Build::RUST_SHA)
    proof['sdkSettings'] = make.call(Build::SDK + '/SDKSettings.json', Build::SDK_SHA)
    manifest = make.call(Build::REUSE_PROOF, Build::REUSE_SHA, 0600, 1000)
    [Marshal.load(Marshal.dump(proof)), records, manifest]
  end

  def fixture_reuse(proof, records)
    active = []
    allowed = [Build::REUSE_PROOF] + proof['commands'].flat_map { |command| %w[stdout stderr].map { |key| command[key]['path'] } } +
      proof['sources'].keys.select { |path| path.end_with?('.swift') } +
      Build::REUSED_ROLES.values.map { |name| File.dirname(Build::REUSE_PROOF) + '/' + name }
    reader = lambda do |path, **options|
      raise 'historical non-Swift source was relabeled/currently audited' unless allowed.include?(path)
      active << path
      value = records.fetch(path)
      raise Build::Staging::Refused, 'fixture changed' if options[:expected] && options[:expected] != value
      value
    end
    result = File.stub(:realpath, ->(path) { path }) do
      Build::Staging.stub(:record!, reader) do
        Build.stub(:proof_bytes!, ->(_record) { JSON.generate(proof) }) do
          Build.stub(:file_record, ->(path, **_options) { records.fetch(path) }) { Build.reused_tools! }
        end
      end
    end
    [result, active]
  end

  def test_reused_v1_original_provenance_and_unchanged_swift_records
    proof, records, manifest = reuse_fixture
    result, active = fixture_reuse(proof, records)
    assert_equal %w[buildProof guardToolingCommit guardToolingTree tools], result.keys.sort
    assert_equal manifest, result['buildProof']
    assert_equal Build::REUSE_COMMIT, result['guardToolingCommit']
    assert_equal Build::REUSE_TREE, result['guardToolingTree']
    assert_equal Build::REUSED_ROLES.keys.sort, result['tools'].keys.sort
    Build::REUSED_ROLES.each_key { |role| assert_equal proof['tools'][role], result['tools'][role] }
    refute_includes active, Build::ROOT + '/macOS/scripts/build-opensteamer-microphone-v9-guards.rb'
    refute_includes active, Build::ROOT + '/macOS/scripts/opensteamer-microphone-v9-transaction.rs'
  end

  def test_reused_v1_refuses_relabeling_fields_recipes_and_record_drift
    mutants = [
      ->(proof, _records) { proof['schema'] = 'opensteamer.microphone-v9.native-guard-build.v2' },
      ->(proof, _records) { proof['originalInputs'] = {} },
      ->(proof, _records) { proof['reusedTools'] = {} },
      ->(proof, _records) { proof['releaseInputs'] = {} },
      ->(proof, _records) { proof['deploymentAuthority'] = true },
      ->(proof, _records) { proof['liveQueriesPerformed'] = true },
      ->(proof, _records) { proof['guardToolingCommit'] = 'c' * 40 },
      ->(proof, _records) { proof['guardToolingTree'] = 'c' * 40 },
      ->(proof, _records) { proof['commands'][1]['argv'].delete('-warnings-as-errors') },
      ->(proof, _records) { proof['sources'].delete(Build::MONITOR) },
      ->(proof, _records) { proof['tools'].delete('routeGuardian') },
      ->(_proof, records) { records[Build::REUSE_PROOF]['sha256'] = 'd' * 64 }
    ]
    mutants.each do |mutation|
      proof, records, = reuse_fixture; mutation.call(proof, records)
      assert_raises(Build::Refused) { fixture_reuse(proof, records) }
    end
    %w[idleHelper bothOrderProbe routeGuardian].each do |role|
      proof, records, = reuse_fixture
      input = proof['tools'].fetch(role); input['sha256'] = 'e' * 64
      assert_raises(Build::Refused) { fixture_reuse(proof, records) }
    end
  end

  def test_disappearing_member_is_only_discarded_after_fresh_group_inventory
    reads = 0
    Build::OwnedDarwinChild.stub(:inventory, ->(_pid) { reads += 1; reads == 1 ? [12, 13] : [13] }) do
      Build::OwnedDarwinChild.stub(:member_identity, ->(member) {
        member == 12 ? nil : [13, 0, 10, 0, 0, 0, 0, 0, 0, 501, 0, 501]
      }) do
        assert_equal [13], Build::OwnedDarwinChild.other_members(10)
      end
    end
    Build::OwnedDarwinChild.stub(:inventory, ->(_pid) { [12] }) do
      Build::OwnedDarwinChild.stub(:member_identity, ->(_member) { nil }) do
        assert_raises(Build::Refused) { Build::OwnedDarwinChild.other_members(10) }
      end
    end
  end

  def test_duplicate_build_proof_json_refuses_before_command_dispatch
    with_directory do |path|
      input = File.join(path, 'proof.json')
      File.open(input, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write('{"schema":"a","schema":"b"}') }
      commands = Object.new
      def commands.run(*)
        raise 'duplicate proof must not dispatch'
      end
      assert_raises(Build::Refused) { Build.audit_build!(input, Digest::SHA256.file(input).hexdigest, commands) }
    end
  end
end
