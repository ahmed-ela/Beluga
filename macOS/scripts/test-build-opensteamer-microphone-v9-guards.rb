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
    fixture = { 'sources' => (Build.source_paths + [root + '/public/main.swift']).to_h { |path| [path, nil] },
                'commands' => Build.compile_recipes(root).map { |argv| { 'argv' => argv } } }
    assert Build.audit_recipes!(fixture, root)
    mutants = [
      ->(value) { value['sources'].delete(Build.source_paths.first) },
      ->(value) { value['sources']['/private/tmp/foreign.swift'] = nil },
      ->(value) { value['commands'][0]['argv'] = ['/usr/bin/true'] },
      ->(value) { value['commands'][1]['argv'].delete('-warnings-as-errors') },
      ->(value) { value['commands'][2]['argv'][-1] = root + '/not-the-probe' },
      ->(value) { value['commands'] << value['commands'][0] },
      ->(value) { value['commands'].reverse! },
      ->(value) { value['commands'] << { 'argv' => ['/bin/sh', '-c', 'true'] } }
    ]
    mutants.each do |mutation|
      value = Marshal.load(Marshal.dump(fixture)); mutation.call(value)
      assert_raises(Build::Refused) { Build.audit_recipes!(value, root) }
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
