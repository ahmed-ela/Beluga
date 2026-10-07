#!/usr/bin/ruby
# Exercises the production parsers/verifier with temporary result and tool fixtures.
# No compiler, Simulator, physical device, installed driver, host, or credential is used.
require 'minitest/autorun'
require_relative 'microphone-regression-gate'

class MicrophoneRegressionGateTests < Minitest::Test
  Gate = MicrophoneRegressionGate
  Signing = MicrophoneSimulatorSigning
  SIMULATOR = 'C171496A-3277-466F-8E5D-3D9E2D187ECE'.freeze

  def setup
    @temporary = File.realpath(Dir.mktmpdir('beluga-microphone-gate-selftest-'))
    @root = File.join(@temporary, 'source')
    @scratch = File.join(@temporary, 'scratch')
    @evidence = File.join(@scratch, 'validation-runs/microphone-fixture')
    FileUtils.mkdir_p(@root, mode: 0700)
    FileUtils.mkdir_p(@evidence, mode: 0700)
    _, status = Open3.capture2e('/usr/bin/git', 'init', '--quiet', @root)
    assert status.success?
    @sim_methods = (Gate::SIMULATOR_PINNED + Gate::SIMULATOR_SKIPS + ['IOSAudioDiagnosticsJournalTests/testJournalFixture']).uniq.sort
    classes = Gate::SIMULATOR_CLASSES.map do |name|
      methods = @sim_methods.select { |method| method.start_with?(name + '/') }
      "final class #{name}: XCTestCase {\n" + methods.map { |method| "func #{method.split('/').last}() {}\n" }.join + "}\n"
    end
    write(File.join(@root, 'iOS/opensteamer/Tests/AudioTests.swift'), classes.join)
    @pairing_methods = Gate::PAIRING_PINNED.dup
    reviewed_root = File.dirname(File.dirname(File.realpath(__FILE__)))
    # Read source bytes only: fixture declarations and the reviewed App root are
    # never compiled or launched by these parser/receipt self-tests.
    (Gate::PAIRING_FILES.values + [Gate::PAIRING_APP_ROOT]).each do |relative|
      write(File.join(@root, relative), File.binread(File.join(reviewed_root, relative)))
    end
    @gate_methods = Gate.gate_inventory(File.dirname(File.dirname(File.realpath(__FILE__))))
    write(File.join(@root, 'scripts/test-validate-microphone-regressions.rb'),
          @gate_methods.map { |method| "def #{method}\nend\n" }.join)
    @signing_methods = Gate.simulator_signing_inventory(File.dirname(File.dirname(File.realpath(__FILE__))))
    write(File.join(@root, 'scripts/test-microphone-simulator-signing.rb'),
          @signing_methods.map { |method| "def #{method}\nend\n" }.join)
    @producer_methods = Gate.mac_producer_inventory(File.dirname(File.dirname(File.realpath(__FILE__))))
    write(File.join(@root, 'macOS/scripts/verify-beluga-mac-client-tests.rb'),
          @producer_methods.map { |method| "def #{method}\nend\n" }.join)
    write(File.join(@root, 'macOS/scripts/retained-beluga-mac-client-tests.rb'), '# included cases are flattened in the synthetic main inventory')
    write(File.join(@root, 'macOS/scripts/update-trial-artifact-tests.rb'), '# included cases are flattened in the synthetic main inventory')
    write(File.join(@root, 'macOS/scripts/update-trial-package-tests.rb'), '# included cases are flattened in the synthetic main inventory')
    write(File.join(@root, 'shared/Vendor/LiveKitWebRTC/LiveKitWebRTC.xcframework.zip'), 'fixture vendor bytes')
    write(File.join(@root, 'iOS/opensteamer/Frameworks/OpensteamerAudioTransactionAuthority.xcframework/Info.plist'), 'fixture Rust artifact')
    crate = File.join(@root, 'iOS/opensteamer/Rust/AudioTransactionAuthority')
    Gate::RUST_SOURCE_FILES.each { |path| write(File.join(crate, path), 'Rust source fixture ' + path) }
    source_manifest = Gate::RUST_SOURCE_FILES.map { |path| Gate.sha(File.join(crate, path)) + '  ' + path + "\n" }.join
    write(File.join(crate, 'SOURCE_MANIFEST.sha256'), source_manifest)
    artifact = File.join(@root, 'iOS/opensteamer/Frameworks/OpensteamerAudioTransactionAuthority.xcframework')
    write(File.join(artifact, 'SOURCE_MANIFEST.sha256'), source_manifest)
    write(File.join(artifact, 'ios-arm64/libopensteamer_audio_transaction_authority.a'), 'device library fixture')
    write(File.join(artifact, 'ios-arm64_x86_64-simulator/libopensteamer_audio_transaction_authority-simulator.a'), 'Simulator library fixture')
    artifact_files = Dir.glob(File.join(artifact, '**', '*')).select { |path| File.file?(path) }
    write(File.join(artifact, 'ARTIFACT_MANIFEST.sha256'), artifact_files.map { |path| Gate.sha(path) + '  ./' + path.delete_prefix(artifact + '/') + "\n" }.join)
    write(File.join(@root, '.gitignore'), "shared/Vendor/BelugaCore.xcframework/\n")
    Gate::BELUGA_CORE_SOURCE_FILES.each { |path| write(File.join(core_crate, path), 'Beluga core source fixture ' + path) }
    write(File.join(core_artifact, 'Info.plist'), core_plist)
    write(File.join(core_artifact, 'BUILD_METADATA.txt'),
          Gate::BELUGA_CORE_METADATA_PREFIX.join("\n") + "\n" +
          "rustc 1.97.1 (abcdef123 2026-09-30)\nbinary: rustc\ncommit-hash: " + 'a' * 40 +
          "\ncommit-date: 2026-09-30\nhost: aarch64-apple-darwin\nrelease: 1.97.1\nLLVM version: 22.1.6\n" +
          Gate::XCODE_VERSION + "macos-sdk=26.6\niphoneos-sdk=26.6\niphonesimulator-sdk=26.6\n")
    Gate::BELUGA_CORE_SLICES.keys.each do |slice|
      framework = File.join(core_artifact, slice, Gate::BELUGA_CORE_FRAMEWORK)
      write(File.join(framework, 'BelugaCore'), core_archive_fixture(slice))
      { 'beluga_core.h' => 'Headers/beluga_core.h', 'module.modulemap' => 'Modules/module.modulemap' }.each do |name, published|
        write(File.join(framework, published), File.binread(File.join(core_crate, 'include', name)))
      end
      write(File.join(framework, 'Info.plist'), fixture_plist(Gate.beluga_core_framework_info(slice)))
    end
    write(File.join(core_artifact, 'THIRD_PARTY_NOTICES.html'), File.binread(File.join(core_crate, 'THIRD_PARTY_NOTICES.html')))
    refresh_core_source_manifest
    refresh_core_artifact_manifest
    %w[OpensteamerVirtualAudioCoreTests.c OpensteamerVirtualMicrophoneDriverTests.c].each do |name|
      label = name.include?('CoreTests') ? 'core invariant' : 'driver interface'
      entries = Gate::C_PINNED.fetch(label).map { |test| "{\"#{test}\", test_behavior},\n" }.join
      write(File.join(@root, 'macOS/VirtualAudioDriver/tests', name), "int main() {\nstruct fixture { int value; } tests[] = {\n" + entries + "};\n}\n")
    end
    @mac_methods = (Gate::MAC_CLASSES.map { |name| name + '/testFixture' } + Gate::MAC_PINNED).uniq.sort
    @shared_methods = (Gate::SHARED_SIGNALING_PINNED + %w[firstConcurrentFixture secondConcurrentFixture].map do |name|
      Gate::SHARED_SIGNALING_SUITE + '/' + name + '()'
    end).sort
    @shared_replay_methods = Gate::SHARED_REPLAY_PINNED.transform_values { |ids| ids.sort }
    Gate::SHARED_REPLAY_FILES.each do |suite, relative|
      # Source/result parser fixture only, not compiled Swift or AEAD evidence.
      methods = @shared_replay_methods.fetch(suite).map { |id| id.split('/').last.delete_suffix('()') }
      write(File.join(@root, relative), "struct #{suite.split('.').last} {\n" +
        methods.map { |method| "  @Test func #{method}() {}\n" }.join + "}\n")
    end
    @shared_reconnect_counter_methods = (Gate::SHARED_RECONNECT_COUNTER_PINNED +
      [Gate::SHARED_RECONNECT_COUNTER_SUITE + '/additionalCounterFixture()']).sort
    write(File.join(@root, Gate::SHARED_RECONNECT_COUNTER_FILE), "struct #{Gate::SHARED_RECONNECT_COUNTER_SUITE.split('.').last} {\n" +
      @shared_reconnect_counter_methods.map { |id| "  @Test func #{id.split('/').last.delete_suffix('()')}() {}\n" }.join + "}\n")
    @handoff_methods = (Gate::SHARED_HANDOFF_CLASSES.map { |name| name + '/testFixture' } + Gate::SHARED_HANDOFF_PINNED).uniq.sort
    @rust_methods = Gate::RUST_PINNED.sort
    @core_methods = (Gate::BELUGA_CORE_PINNED + ['additional_core_behavior_fixture']).sort
    @c_methods = Gate.c_inventory(@root)
    @developer = File.join(@temporary, 'fixture-Xcode.app/Contents/Developer')
    @tools = %w[xcodebuild swift swiftc clang make ruby cargo rustc node].map do |name|
      path = if name == 'xcodebuild'
               File.join(@developer, 'usr/bin', name)
             elsif %w[swift swiftc clang].include?(name)
               File.join(@developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin', name)
             else
               File.join(@temporary, 'fixture-tools/usr/bin', name)
             end
      write(path, 'throwaway tool identity ' + name)
      [path, Gate.sha(path)]
    end.to_h
    # The fixed read-only collector tools are hashed, never replaced or written.
    Signing::DEPENDENCIES.each { |path| @tools[path] = Gate.sha(path) }
    @tools['/usr/bin/lipo'] = Gate.sha('/usr/bin/lipo')
    @tools['/usr/bin/xcrun'] = Gate.sha('/usr/bin/xcrun')
    # Substitute only the reviewed tool pin in this test process; the executable
    # CLI has no override. All source, logs, artifacts and result checks are real.
    @production_xcode_pin = Gate::XCODEBUILD_SHA256
    Gate.send(:remove_const, :XCODEBUILD_SHA256)
    Gate.const_set(:XCODEBUILD_SHA256, @tools.find { |path, _| path.end_with?('/usr/bin/xcodebuild') }.last)
  end

  def teardown
    if @production_xcode_pin
      Gate.send(:remove_const, :XCODEBUILD_SHA256)
      Gate.const_set(:XCODEBUILD_SHA256, @production_xcode_pin)
    end
    FileUtils.remove_entry_secure(@temporary) if @temporary && File.directory?(@temporary)
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(path), mode: 0700)
    File.write(path, text)
  end

  def core_crate
    File.join(@root, Gate::BELUGA_CORE_CRATE)
  end

  def core_artifact
    File.join(@root, Gate::BELUGA_CORE_ARTIFACT)
  end

  def core_plist(libraries = nil)
    libraries ||= Gate::BELUGA_CORE_SLICES.map do |identifier, properties|
      properties.merge('LibraryIdentifier' => identifier,
                       'LibraryPath' => 'BelugaCore.framework', 'BinaryPath' => 'BelugaCore.framework/BelugaCore')
    end
    values = libraries.map do |library|
      fixture_plist_dict(library)
    end.join
    '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>AvailableLibraries</key><array>' + values +
      '</array><key>CFBundlePackageType</key><string>XFWK</string><key>XCFrameworkFormatVersion</key><string>1.0</string></dict></plist>'
  end

  def fixture_plist_dict(values)
    '<dict>' + values.map do |key, value|
      rendered = value.is_a?(Array) ? '<array>' + value.map { |item| '<string>' + item + '</string>' }.join + '</array>' : '<string>' + value + '</string>'
      '<key>' + key + '</key>' + rendered
    end.join + '</dict>'
  end

  def fixture_plist(values)
    '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0">' + fixture_plist_dict(values) + '</plist>'
  end

  def core_archive_fixture(slice)
    member = "!<arch>\ninert core archive fixture\n".b
    return member if slice != 'ios-arm64_x86_64-simulator'
    [0xcafebabe, 2, 0x0100000c, 0, 48, member.bytesize, 0,
     0x01000007, 3, 48 + member.bytesize, member.bytesize, 0].pack('N*') + member * 2
  end

  def core_link_log
    Gate::BELUGA_CORE_RUNTIME_MARKERS.join("\n") + "\nBELUGA_CORE_LINK_SMOKE_PASS\n" +
      Gate::BELUGA_CORE_TARGETS.drop(1).map { |target| "BELUGA_CORE_CROSS_LINK_PASS target=#{target}\n" }.join
  end

  def core_mutations_log(names = Gate::BELUGA_CORE_MUTANTS)
    names.map do |name|
      test = Gate::BELUGA_CORE_MUTANT_TESTS.fetch(name)
      # Inert text fixtures replay the actual production validator. No Rust
      # compiler or mutant is run by this self-test process.
      "\nrunning 1 test\ntest #{test} ... FAILED\n\nfailures:\n" +
        "thread '#{test}' (123) panicked at tests/fixture.rs:1:1:\n" +
        "assertion `left == right` failed: reviewed behavioral fixture\n  left: 0\n right: 1\n" +
        "test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 6 filtered out; finished in 0.00s\n" +
        "    Finished `test` profile [unoptimized + debuginfo] target(s) in 0.01s\n" +
        "error: test failed, to rerun pass `--test fixture`\n" +
        "Behavioral mutation rejected: #{name}\nBELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
    end.join + "BELUGA_CORE_MUTATIONS_PASS cases=#{names.length}\n"
  end

  def refresh_core_source_manifest(publish: true)
    paths = Gate.beluga_core_files(core_crate, exclude: %w[target SOURCE_MANIFEST.sha256])
    text = paths.map { |path| Gate.sha(File.join(core_crate, path)) + '  ' + path + "\n" }.join
    write(File.join(core_crate, 'SOURCE_MANIFEST.sha256'), text)
    write(File.join(core_artifact, 'SOURCE_MANIFEST.sha256'), text) if publish
  end

  def refresh_core_artifact_manifest
    paths = Gate.beluga_core_files(core_artifact, exclude: %w[ARTIFACT_MANIFEST.sha256])
    text = paths.map { |path| Gate.sha(File.join(core_artifact, path)) + '  ./' + path + "\n" }.join
    write(File.join(core_artifact, 'ARTIFACT_MANIFEST.sha256'), text)
  end

  def pairing_summary
    counts = { 'passedTests' => 106, 'skippedTests' => 0, 'failedTests' => 0, 'expectedFailures' => 0 }
    counts.merge('result' => 'Passed', 'totalTestCount' => 106, 'testFailures' => [],
                 'devicesAndConfigurations' => [counts.merge('device' => { 'deviceId' => SIMULATOR, 'platform' => 'iOS Simulator' })])
  end

  def pairing_results
    { 'testNodes' => @pairing_methods.map { |id| { 'nodeType' => 'Test Case', 'nodeIdentifier' => id + '()', 'result' => 'Passed' } } }
  end

  def pairing_process_fixture(name, argv, start, finish, pid = 12345)
    { 'schema' => 'beluga.pairing.process-group.v1', 'phase' => name, 'pid' => pid, 'pgid' => pid,
      'argvSHA256' => Digest::SHA256.hexdigest(JSON.generate(argv)), 'startedAtNanoseconds' => start, 'finishedAtNanoseconds' => finish,
      'timeoutSeconds' => Gate::PAIRING_PHASE_TIMEOUTS.fetch(name), 'leaderReaped' => true, 'leaderExitStatus' => 0, 'leaderSignal' => nil,
      'groupAbsent' => true, 'absenceProof' => 'ESRCH', 'termSent' => false, 'killSent' => false, 'completion' => 'success' }
  end

  def pairing_build_fixture
    started = (Time.now.to_r * 1_000_000_000).to_i
    app_root = File.join(@root, Gate::PAIRING_APP_ROOT)
    paths = Gate.pairing_compiler_paths(@scratch)
    bytes = { 'Beluga.SwiftFileList' => Shellwords.escape(app_root) + "\n",
              'opensteamer-OutputFileMap.json' => JSON.generate(app_root => { 'object' => paths.fetch('OpensteamerApp.o') }),
              'OpensteamerApp.o' => 'fixture only: actual object reading/linking is not executed by parser self-tests' }
    paths.each { |name, path| write(path, bytes.fetch(name)) }
    swiftc = File.join(@developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
    driver = Shellwords.join(['builtin-SwiftDriver', '--', swiftc, '-module-name', 'opensteamer', '-target', 'arm64-apple-ios17.0-simulator',
                             '-DDEBUG', '-DOPENSTEAMER_UPDATE_VALIDATION_HOST', '-c', '@' + paths.fetch('Beluga.SwiftFileList'),
                             '-output-file-map', paths.fetch('opensteamer-OutputFileMap.json')]) + "\n"
    log = driver + 'SwiftCompile normal arm64 ' + app_root + " (in target 'opensteamer' from project 'opensteamer')\n** BUILD SUCCEEDED **\n"
    finished = (Time.now.to_r * 1_000_000_000).to_i
    invocation = { 'developer_directory' => @developer, 'scratch' => @scratch }
    argv = Gate.pairing_commands(@root, @evidence, invocation, SIMULATOR).fetch('pairing-inert-build')
    @pairing_build_process = pairing_process_fixture('pairing-inert-build', argv, started, finished)
    @pairing_original_object = Gate.pairing_object_metadata(paths.fetch('OpensteamerApp.o'))
    contract = Gate.pairing_compiler_proof(@root, @scratch, @developer, @tools, log, bytes, @pairing_build_process, @pairing_original_object)
    parent = File.join(@evidence, 'pairing-inert-root-contract')
    FileUtils.mkdir_p(parent, mode: 0700)
    bytes.merge('app-swift-driver.txt' => driver).each do |name, contents|
      path = File.join(parent, name)
      write(path, contents); File.chmod(0600, path)
    end
    contract['retainedObjectMetadata'] = Gate.pairing_object_metadata(File.join(parent, 'OpensteamerApp.o'))
    [log, bytes, contract]
  end

  def assert_pairing_retired(executor, completion, exit_status = nil)
    proof = executor.last_proof
    assert_equal 'beluga.pairing.process-group.v1', proof.fetch('schema')
    assert_equal completion, proof.fetch('completion')
    assert_equal true, proof.fetch('leaderReaped')
    assert_equal true, proof.fetch('groupAbsent')
    assert_equal 'ESRCH', proof.fetch('absenceProof')
    assert_equal proof.fetch('pid'), proof.fetch('pgid')
    assert_equal exit_status, proof.fetch('leaderExitStatus') if exit_status
    assert_raises(Errno::ESRCH) { Process.kill(0, -proof.fetch('pgid')) }
    assert_raises(Errno::ECHILD) { Process.waitpid(proof.fetch('pid'), Process::WNOHANG) }
  end

  def test_pairing_executor_success_nonzero_and_timeout_retire_exact_group
    executor = Gate::PairingExecutor.new
    log = File.join(@evidence, 'pairing-process.log')
    environment = { 'PATH' => '/usr/bin:/bin' }
    assert_equal "inert fixture\n", executor.run(['/usr/bin/ruby', '-e', 'puts "inert fixture"'], environment, @root, log, 1)
    assert_pairing_retired(executor, 'success', 0)
    rejects('unsuccessfully') { executor.run(['/usr/bin/ruby', '-e', 'exit 7'], environment, @root, log, 1) }
    assert_pairing_retired(executor, 'exit-failure', 7)
    rejects('exceeded its deadline') { executor.run(['/usr/bin/ruby', '-e', 'sleep 5'], environment, @root, log, 0.05) }
    assert_pairing_retired(executor, 'timeout')
  end

  def test_pairing_executor_reaped_leader_cannot_abandon_living_descendant
    executor = Gate::PairingExecutor.new
    log = File.join(@evidence, 'pairing-descendant.log')
    script = 'reader, writer = IO.pipe; child = fork { reader.close; trap("TERM") {}; writer.write("ready"); writer.close; loop { sleep 1 } }; writer.close; reader.read; puts child; STDOUT.flush; exit! 0'
    text = executor.run(['/usr/bin/ruby', '-e', script], { 'PATH' => '/usr/bin:/bin' }, @root, log, 1)
    assert_match(/\A\d+\n\z/, text)
    assert_equal true, executor.last_proof.fetch('termSent')
    assert_equal true, executor.last_proof.fetch('killSent')
    assert_pairing_retired(executor, 'success', 0)
    assert_raises(Errno::ESRCH) { Process.kill(0, Integer(text.strip)) }
  end

  def test_pairing_executor_interruption_still_reaps_and_proves_group_absent
    executor = Gate::PairingExecutor.new
    log = File.join(@evidence, 'pairing-interruption.log')
    executing = Thread.current
    interrupt = Thread.new { sleep 0.1; executing.raise Interrupt, 'owned fixture interruption' }
    assert_raises(Interrupt) do
      executor.run(['/usr/bin/ruby', '-e', 'sleep 5'], { 'PATH' => '/usr/bin:/bin' }, @root, log, 2)
    end
    assert_pairing_retired(executor, 'interrupted')
  ensure
    interrupt.join if interrupt
  end

  def test_pairing_executor_eperm_never_becomes_a_successful_absence_proof
    probe_class = Class.new(Gate::PairingExecutor) do
      def group_present?(_pgid)
        raise RuntimeError, 'pairing owned process group cannot be proven absent: EPERM'
      end
    end
    executor = probe_class.new
    log = File.join(@evidence, 'pairing-eperm.log')
    rejects('EPERM') { executor.run(['/usr/bin/ruby', '-e', 'exit 0'], { 'PATH' => '/usr/bin:/bin' }, @root, log, 1) }
    assert_nil executor.last_proof
    assert_raises(Errno::ESRCH) { Process.kill(0, -executor.last_pgid) }
    signal_class = Class.new(Gate::PairingExecutor) do
      def signal_group(_signal, _pgid)
        raise RuntimeError, 'pairing owned process group teardown refused: EPERM'
      end
    end
    executor = signal_class.new
    rejects('EPERM') { executor.run(['/usr/bin/ruby', '-e', 'sleep 5'], { 'PATH' => '/usr/bin:/bin' }, @root, log, 0.05) }
    assert_nil executor.last_proof
  ensure
    # This is only an injected-permission fixture's exact owned group; it is
    # never the canonical gate, a compiler, an app or an external process.
    if executor && executor.last_pgid
      begin
        Process.kill('KILL', -executor.last_pgid)
      rescue Errno::ESRCH
      end
      begin
        Process.waitpid(executor.last_pgid)
      rescue Errno::ECHILD
      end
      assert_raises(Errno::ESRCH) { Process.kill(0, -executor.last_pgid) }
    end
  end

  def test_pairing_stale_object_and_forged_process_records_refuse_before_launch
    log, bytes, contract = pairing_build_fixture
    context = { 'scratch' => @scratch, 'developer_directory' => @developer }
    original = @pairing_original_object
    %w[modifiedAtNanoseconds changedAtNanoseconds].each do |key|
      stale = original.merge(key => @pairing_build_process.fetch('startedAtNanoseconds') - 1)
      rejects('stale or outside') do
        Gate.pairing_compiler_proof(@root, @scratch, @developer, @tools, log, bytes, @pairing_build_process, stale)
      end
      future = original.merge(key => @pairing_build_process.fetch('finishedAtNanoseconds') + 1)
      rejects('stale or outside') do
        Gate.pairing_compiler_proof(@root, @scratch, @developer, @tools, log, bytes, @pairing_build_process, future)
      end
    end
    path = Gate.pairing_compiler_paths(@scratch).fetch('OpensteamerApp.o')
    File.utime(Time.at(1), Time.at(1), path)
    rejects('stale or outside') do
      Gate.pairing_compiler_proof(@root, @scratch, @developer, @tools, log, bytes, @pairing_build_process, Gate.pairing_object_metadata(path))
    end
    retained = File.join(@evidence, 'pairing-inert-root-contract/OpensteamerApp.o')
    File.chmod(0400, retained)
    rejects('metadata differs') { Gate.validate_pairing_contract(@root, @evidence, context, @tools, log, contract, @pairing_build_process) }
    File.chmod(0600, retained)
    value = receipt
    commands = Gate.commands(@root, @evidence, value['invocation'], @tools, SIMULATOR, @mac_methods, @handoff_methods)
    records = value.fetch('pairing_processes')
    assert_equal records, Gate.validate_pairing_processes(records, commands, (value['created_at'] + 1) * 1_000_000_000, 1800)
    %w[leaderReaped groupAbsent].each do |key|
      forged = Marshal.load(Marshal.dump(records)); forged.first[key] = false
      rejects('reap and ESRCH') { Gate.validate_pairing_processes(forged, commands, (value['created_at'] + 1) * 1_000_000_000, 1800) }
    end
    [{ 'leaderExitStatus' => 1 }, { 'leaderSignal' => 9 }, { 'completion' => 'timeout' }, { 'absenceProof' => 'EPERM' },
     { 'argvSHA256' => '0' * 64 }, { 'pgid' => records.first['pid'] + 1 }, { 'timeoutSeconds' => 601 },
     { 'finishedAtNanoseconds' => (value['created_at'] + 2) * 1_000_000_000 }].each do |replacement|
      forged = Marshal.load(Marshal.dump(records)); forged.first.merge!(replacement)
      rejects('pairing process') { Gate.validate_pairing_processes(forged, commands, (value['created_at'] + 1) * 1_000_000_000, 1800) }
    end
    [records.drop(1), records.reverse, records + [records.first]].each do |forged|
      rejects('missing, duplicated or reordered') { Gate.validate_pairing_processes(forged, commands, (value['created_at'] + 1) * 1_000_000_000, 1800) }
    end
    forged = Marshal.load(Marshal.dump(records)); forged[1]['startedAtNanoseconds'] = forged[0]['finishedAtNanoseconds'] - 1
    rejects('ordering or overall') { Gate.validate_pairing_processes(forged, commands, (value['created_at'] + 1) * 1_000_000_000, 1800) }
    %w[pairing_processes].each do |key|
      missing = receipt; missing.delete(key)
      rejects('unrecognized field set') { verify(missing) }
    end
    forged = receipt; forged['pairing_processes'].first['groupAbsent'] = false
    rejects('reap and ESRCH') { verify(forged) }
    forged = receipt; forged['pairing_inert_root']['originalObjectMetadata']['modifiedAtNanoseconds'] = 1
    rejects('stale or outside') { verify(forged) }
    forged = receipt; forged['pairing_processes'].first['startedAtNanoseconds'] += 1
    rejects('differs from actual build') { verify(forged) }
  end

  def test_pairing_inventory_is_exact104_separate_from_original_simulator_skips
    assert_equal [60, 8, 22, 16], Gate::PAIRING_BY_CLASS.values.map(&:length)
    assert_equal 106, Gate::PAIRING_PINNED.length
    assert_equal @pairing_methods, Gate.pairing_inventory(@root)
    assert_empty Gate::PAIRING_CLASSES & Gate::SIMULATOR_CLASSES
    assert_empty Gate::PAIRING_PINNED & Gate::SIMULATOR_SKIPS
    assert_equal @sim_methods, Gate.simulator_inventory(@root)
    Gate::PAIRING_FILES.each do |name, relative|
      path = File.join(@root, relative)
      original = File.binread(path)
      begin
        File.write(path, original.sub(/\bfunc\s+test\w+\s*\(/, 'func removed('))
        rejects('reviewed source changed') { Gate.pairing_inventory(@root) }
        File.write(path, original + "\nfunc testUnreviewedExtra() {}\n")
        rejects('reviewed source changed') { Gate.pairing_inventory(@root) }
        File.write(path, original.sub(name + ': XCTestCase', 'RenamedFixture: XCTestCase'))
        rejects('reviewed source changed') { Gate.pairing_inventory(@root) }
      ensure
        File.binwrite(path, original)
      end
    end
  end

  def test_pairing_zero_skip_named_results_cannot_omit_duplicate_or_fail_cases
    assert_equal @pairing_methods, Gate.validate_pairing(pairing_summary, pairing_results, @pairing_methods, SIMULATOR)
    @pairing_methods.each do |id|
      changed = pairing_results
      changed['testNodes'].reject! { |entry| entry['nodeIdentifier'] == id + '()' }
      rejects('pairing cases') { Gate.validate_pairing(pairing_summary, changed, @pairing_methods, SIMULATOR) }
    end
    %w[Skipped Failed ExpectedFailure Unknown].each do |status|
      changed = pairing_results; changed['testNodes'].first['result'] = status
      rejects('failed or skipped') { Gate.validate_pairing(pairing_summary, changed, @pairing_methods, SIMULATOR) }
    end
    changed = pairing_results; changed['testNodes'] << changed['testNodes'].first.dup
    rejects('pairing cases') { Gate.validate_pairing(pairing_summary, changed, @pairing_methods, SIMULATOR) }
    changed = pairing_results; changed['testNodes'].first['nodeIdentifier'] = 'Unreviewed/testExtra()'
    rejects('unexpected') { Gate.validate_pairing(pairing_summary, changed, @pairing_methods, SIMULATOR) }
    %w[totalTestCount passedTests skippedTests failedTests expectedFailures].each do |key|
      changed = pairing_summary; changed[key] += 1
      rejects('pairing summary') { Gate.validate_pairing(changed, pairing_results, @pairing_methods, SIMULATOR) }
    end
    changed = pairing_summary; changed['devicesAndConfigurations'].first['passedTests'] = 103
    rejects('per-configuration') { Gate.validate_pairing(changed, pairing_results, @pairing_methods, SIMULATOR) }
    changed = pairing_summary; changed['devicesAndConfigurations'].first['device']['platform'] = 'iOS'
    rejects('physical or different') { Gate.validate_pairing(changed, pairing_results, @pairing_methods, SIMULATOR) }
    rejects('expected inventory') { Gate.validate_pairing(pairing_summary, pairing_results, @pairing_methods.drop(1), SIMULATOR) }
  end

  def test_pairing_compiler_requires_fresh_inert_driver_source_filelist_map_and_object
    log, bytes, contract = pairing_build_fixture
    context = { 'scratch' => @scratch, 'developer_directory' => @developer }
    assert_equal contract, Gate.validate_pairing_contract(@root, @evidence, context, @tools, log, contract, @pairing_build_process)
    driver = log.lines.first
    mutations = [log.sub(driver, ''), driver + log, log.sub('-module-name opensteamer', '-module-name foreign'),
                 log.sub('-DDEBUG', ''), log.sub('-DOPENSTEAMER_UPDATE_VALIDATION_HOST', ''),
                 log.sub('-DDEBUG', '-DDEBUG -DDEBUG'), log.sub('arm64-apple-ios17.0-simulator', 'arm64-apple-ios17.0'),
                 log.sub('-c ', ''), log.sub('-output-file-map ', '-wrong-file-map '),
                 log.sub(/^SwiftCompile[^\n]+\n/, ''), log + log.lines[1], log.sub('BUILD SUCCEEDED', 'BUILD FAILED')]
    mutations.each do |changed|
      rejects('pairing') { Gate.pairing_compiler_proof(@root, @scratch, @developer, @tools, changed, bytes, @pairing_build_process, @pairing_original_object) }
    end
    app_root = File.join(@root, Gate::PAIRING_APP_ROOT)
    [{ 'Beluga.SwiftFileList' => '' }, { 'Beluga.SwiftFileList' => bytes.fetch('Beluga.SwiftFileList') * 2 },
     { 'Beluga.SwiftFileList' => '/foreign/App.swift' }, { 'opensteamer-OutputFileMap.json' => '{}' },
     { 'OpensteamerApp.o' => '' }, { 'OpensteamerApp.o' => 'x' * (16 * 1024 * 1024 + 1) }].each do |replacement|
      rejects('pairing') { Gate.pairing_compiler_proof(@root, @scratch, @developer, @tools, log, bytes.merge(replacement), @pairing_build_process, @pairing_original_object) }
    end
    original = File.binread(app_root)
    begin
      File.write(app_root, original + '// changed root')
      rejects('inert App root changed') { Gate.pairing_compiler_proof(@root, @scratch, @developer, @tools, log, bytes, @pairing_build_process, @pairing_original_object) }
    ensure
      File.binwrite(app_root, original)
    end
    changed = Marshal.load(Marshal.dump(contract)); changed['driverSHA256'] = '0' * 64
    rejects('differs from actual build') { Gate.validate_pairing_contract(@root, @evidence, context, @tools, log, changed, @pairing_build_process) }
    path = File.join(@evidence, contract['driverPath']); original = File.binread(path)
    begin
      File.write(path, original + 'unbound line')
      rejects('differs from actual build') { Gate.validate_pairing_contract(@root, @evidence, context, @tools, log, contract, @pairing_build_process) }
    ensure
      File.binwrite(path, original)
    end
  end

  def test_pairing_owned_compiler_files_and_lock_replacement_fail_closed
    log, bytes, contract = pairing_build_fixture
    path = Gate.pairing_compiler_paths(@scratch).fetch('OpensteamerApp.o')
    assert_equal bytes.fetch('OpensteamerApp.o'), Gate.pairing_owned_bytes(path, 1024)
    rejects('unbounded') { Gate.pairing_owned_bytes(path, 1) }
    original = File.binread(path)
    File.rename(path, path + '.kept')
    begin
      File.symlink(path + '.kept', path)
      rejects('noncanonical') { Gate.pairing_owned_bytes(path, 1024) }
      File.unlink(path); File.link(path + '.kept', path)
      rejects('unsafe') { Gate.pairing_owned_bytes(path, 1024) }
      File.unlink(path)
      rejects('absent or inaccessible') { Gate.pairing_owned_bytes(path, 1024) }
    ensure
      File.unlink(path) if File.exist?(path) || File.symlink?(path)
      File.rename(path + '.kept', path)
    end
    lock_path = File.join(@scratch, '.microphone-regressions.lock')
    held = File.open(lock_path, File::RDWR | File::CREAT, 0600)
    assert held.flock(File::LOCK_EX | File::LOCK_NB)
    runner = Gate::Runner.new(@root, { scratch: @scratch, timeout: 1800 })
    runner.instance_variable_set(:@lock, held)
    runner.instance_variable_set(:@pairing_started, true)
    runner.instance_variable_set(:@pairing_lock_path, lock_path)
    runner.instance_variable_set(:@pairing_lock_identity, [held.stat.dev, held.stat.ino])
    runner.instance_variable_set(:@pairing_compiler_files, contract.fetch('files'))
    assert_nil runner.check_pairing_fences
    begin
      File.write(path, original + 'changed object')
      rejects('input/object changed') { runner.check_pairing_fences }
      File.binwrite(path, original)
      File.rename(lock_path, lock_path + '.kept')
      File.open(lock_path, File::RDWR | File::CREAT, 0600) { |file| file.write('foreign lock') }
      rejects('cache lock identity changed') { runner.check_pairing_fences }
      File.unlink(lock_path); File.rename(lock_path + '.kept', lock_path)
      runner.instance_variable_set(:@pairing_deadline, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
      rejects('bounded deadline') { runner.check_pairing_fences }
    ensure
      File.binwrite(path, original)
      if File.exist?(lock_path + '.kept')
        File.unlink(lock_path) if File.exist?(lock_path)
        File.rename(lock_path + '.kept', lock_path)
      end
      held.close
    end
  end

  def test_pairing_run_never_launches_without_fresh_compiler_custody
    log, _bytes, _contract = pairing_build_fixture
    lock_path = File.join(@scratch, '.microphone-regressions.lock')
    held = File.open(lock_path, File::RDWR | File::CREAT, 0600)
    assert held.flock(File::LOCK_EX | File::LOCK_NB)
    fake_class = Class.new do
      attr_reader :calls, :last_proof
      def initialize(text)
        @text = text; @calls = []
      end
      def run(argv, _environment, _root, log_path, timeout)
        started = (Time.now.to_r * 1_000_000_000).to_i
        @calls << argv
        raise RuntimeError, 'unexpected native test launch' if argv[1] == 'test'
        File.write(log_path, @text)
        @last_proof = { 'schema' => 'beluga.pairing.process-group.v1', 'pid' => 12345, 'pgid' => 12345,
          'argvSHA256' => Digest::SHA256.hexdigest(JSON.generate(argv)), 'startedAtNanoseconds' => started,
          'finishedAtNanoseconds' => (Time.now.to_r * 1_000_000_000).to_i, 'timeoutSeconds' => timeout,
          'leaderReaped' => true, 'leaderExitStatus' => 0, 'leaderSignal' => nil, 'groupAbsent' => true,
          'absenceProof' => 'ESRCH', 'termSent' => false, 'killSent' => false, 'completion' => 'success' }
        @text
      end
    end
    [log.sub(/^SwiftCompile[^\n]+\n/, ''), log.sub('-DOPENSTEAMER_UPDATE_VALIDATION_HOST', ''), log].each do |text|
      fake = fake_class.new(text)
      runner = Gate::Runner.new(@root, { scratch: @scratch, timeout: 1800 }, fake, fake)
      { source: Gate.source_identity(@root), tools: @tools, evidence: @evidence, environment: {}, lock: held }.each do |name, value|
        runner.instance_variable_set('@' + name.to_s, value)
      end
      capture_io { rejects('pairing') { runner.run_pairing(@scratch, @developer, SIMULATOR) } }
      assert_equal ['build'], fake.calls.map { |argv| argv[1] }
      assert_nil runner.instance_variable_get(:@pairing_result)
    end
  ensure
    held.close if held && !held.closed?
  end

  def test_pairing_receipt_cannot_omit_rehash_or_weaken_inert_phases_and_artifacts
    names = Gate::PAIRING_PHASE_TIMEOUTS.keys
    assert_equal 42, Gate::PHASES.length
    assert_equal names, Gate::PHASES[Gate::PHASES.index('simulator-entitlements') + 1, 6]
    assert_equal 1200, Gate::PAIRING_OVERALL_SECONDS
    assert_equal 'passed', verify(receipt)['status']
    names.each do |name|
      value = receipt; value['phases'].reject! { |entry| entry['name'] == name }
      rejects('absent, duplicate') { verify(value) }
    end
    %w[pairing-inert-build pairing-tests].each do |name|
      value = receipt; argv = value['phases'].find { |entry| entry['name'] == name }['argv']
      argv.delete(Gate::PAIRING_INERT_CONDITIONS)
      rejects('canonical offline invocation') { verify(value) }
    end
    value = receipt
    argv = value['phases'].find { |entry| entry['name'] == 'pairing-tests' }['argv']
    argv.delete('-only-testing:opensteamerTests/ViewerPairingPersistenceTests')
    rejects('canonical offline invocation') { verify(value) }
    %w[pairing-result pairing-app pairing-inert-root-contract].each do |name|
      value = receipt; value['artifacts'].reject! { |entry| entry['name'] == name }
      rejects('artifacts are incomplete') { verify(value) }
    end
    value = receipt; value['coverage']['pairing'].shift
    rejects('pairing coverage differs') { verify(value) }
    value = receipt
    changed = pairing_results; changed['testNodes'].first['result'] = 'Skipped'
    path = File.join(@evidence, 'pairing-results.log'); File.write(path, JSON.generate(changed))
    value['phases'].find { |entry| entry['name'] == 'pairing-results' }['sha256'] = Gate.sha(path)
    rejects('failed or skipped') { verify(value) }
    value = receipt
    path = File.join(@evidence, 'pairing-inert-build.log')
    File.write(path, File.read(path).sub('-DOPENSTEAMER_UPDATE_VALIDATION_HOST', ''))
    value['phases'].find { |entry| entry['name'] == 'pairing-inert-build' }['sha256'] = Gate.sha(path)
    rejects('inert definitions') { verify(value) }
    value = receipt
    proof = value['pairing_inert_root']
    path = File.join(@evidence, proof['driverPath']); File.write(path, File.read(path) + 'forged compiler')
    proof['driverSHA256'] = Gate.sha(path)
    value['artifacts'].find { |entry| entry['name'] == 'pairing-inert-root-contract' }['sha256'] = Gate.tree_identity(File.dirname(path))
    rejects('differs from actual build') { verify(value) }
  end

  def summary
    counts = { 'passedTests' => @sim_methods.length - Gate::SIMULATOR_SKIPS.length,
               'skippedTests' => Gate::SIMULATOR_SKIPS.length, 'failedTests' => 0, 'expectedFailures' => 0 }
    counts.merge('result' => 'Passed', 'totalTestCount' => @sim_methods.length, 'testFailures' => [],
                 'devicesAndConfigurations' => [counts.merge('device' => { 'deviceId' => SIMULATOR, 'platform' => 'iOS Simulator' })])
  end

  def results
    { 'testNodes' => @sim_methods.map do |method|
      { 'nodeType' => 'Test Case', 'nodeIdentifier' => method + '()', 'result' => Gate::SIMULATOR_SKIPS.include?(method) ? 'Skipped' : 'Passed' }
    end }
  end

  def mac_log(methods = @mac_methods)
    "Test Suite 'Selected tests' started at 2026-10-01 12:00:00.000.\n" + methods.map do |id|
      klass, name = id.split('/')
      "Test Case '-[#{klass} #{name}]' started.\nTest Case '-[#{klass} #{name}]' passed (0.001 seconds).\n"
    end.join + "Test Suite 'Selected tests' passed at 2026-10-01 12:00:01.000.\n\t Executed #{methods.length} tests, with 0 failures (0 unexpected) in 1.000 (1.001) seconds\n"
  end

  def rust_log(methods = @rust_methods)
    methods.map { |method| "test #{method} ... ok\n" }.join + "test result: ok. #{methods.length} passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s\n"
  end

  def c_log
    @c_methods.map do |inventory|
      inventory['names'].map { |name| "PASS: #{name}\n" }.join + "PASS: #{inventory['names'].length}/#{inventory['names'].length} production #{inventory['kind']} tests\n"
    end.join
  end

  def signing_log
    @signing_methods.map { |method| "MicrophoneSimulatorSigningTests##{method} = 0.00 s = .\n" }.join +
      "#{@signing_methods.length} runs, 184 assertions, 0 failures, 0 errors, 0 skips\n" +
      "microphone Simulator signing behavior tests passed\n"
  end

  def gate_log
    @gate_methods.map { |method| "MicrophoneRegressionGateTests##{method} = 0.00 s = .\n" }.join +
      "#{@gate_methods.length} runs, 349 assertions, 0 failures, 0 errors, 0 skips\n"
  end

  def producer_log
    @producer_methods.map { |method| "BelugaMacClientContractTests##{method} = 0.00 s = .\n" }.join +
      "#{@producer_methods.length} runs, 602 assertions, 0 failures, 0 errors, 0 skips\n"
  end

  def shared_log(methods = @shared_methods)
    "◇ Test run started.\n↳ Testing Library Version: 1902\n↳ Target Platform: arm64e-apple-macos14.0\n" +
      "◇ Suite DurableSignalingClientTests started.\n" +
      methods.map { |id| "◇ Test #{id.split('/').last} started.\n" }.join +
      methods.reverse.map { |id| "✔ Test #{id.split('/').last} passed after 0.001 seconds.\n" }.join +
      "✔ Suite DurableSignalingClientTests passed after 0.003 seconds.\n" +
      "✔ Test run with #{methods.length} tests in 1 suite passed after 0.003 seconds.\n"
  end

  def replay_log(suite, methods = @shared_replay_methods.fetch(suite))
    name = suite.split('.').last
    "◇ Test run started.\n↳ Testing Library Version: 1902\n↳ Target Platform: arm64e-apple-macos14.0\n" +
      "◇ Suite #{name} started.\n" +
      methods.map { |id| "◇ Test #{id.split('/').last} started.\n" }.join +
      methods.reverse.map { |id| "✔ Test #{id.split('/').last} passed after 0.001 seconds.\n" }.join +
      "✔ Suite #{name} passed after 0.003 seconds.\n" +
      "✔ Test run with #{methods.length} tests in 1 suite passed after 0.003 seconds.\n"
  end

  def signing_record_fixture(relative = 'simulator-app/Beluga.app')
    # Structural receipt fixture, deliberately not a signed executable. The
    # collector's actual byte/signature parser has its own mandatory test phase.
    app = File.join(@evidence, relative)
    write(app + '/Info.plist', 'fixture Info identity')
    write(app + '/Beluga', 'x' * 17000)
    file_record = lambda do |path|
      { 'path' => path, 'sha256' => Gate.sha(path), 'stat' => Signing.stat_record(File.stat(path)) }
    end
    record = { 'schema' => 'beluga.microphone.simulator-signing.v1',
      'claim' => 'signed-arm64-simulator-development-appgroup', 'appPath' => app,
      'appStat' => Signing.stat_record(File.stat(app)),
      'info' => file_record.call(app + '/Info.plist').merge(
        'bundleIdentifier' => Signing::BUNDLE_ID, 'executable' => 'Beluga', 'bundlePackageType' => 'APPL',
        'supportedPlatforms' => ['iPhoneSimulator'], 'platformName' => 'iphonesimulator', 'mediaAppGroup' => Signing::MEDIA_GROUP),
      'executable' => file_record.call(app + '/Beluga').merge(
        'architecture' => 'arm64', 'platform' => 7, 'fileType' => 2,
        'xml' => { 'offset' => 512, 'length' => 400, 'sha256' => '1' * 64 },
        'der' => { 'offset' => 8192, 'length' => Signing::CANONICAL_DER.bytesize, 'sha256' => Signing::DER_SHA256 },
        'codeSignature' => { 'offset' => 16384, 'length' => 216 },
        'codeDirectory' => { 'offset' => 16404, 'length' => 196, 'sha256' => '2' * 64,
          'version' => 0x20400, 'flags' => 2, 'codeLimit' => 16384, 'codeSlots' => 1,
          'pageSizeLog2' => 14, 'hashType' => 2, 'hashSize' => 32 },
        'xmlDerParity' => true, 'coveredCodePagesVerified' => true),
      'applicationIdentifier' => Signing::APPLICATION_ID, 'applicationGroups' => [Signing::MEDIA_GROUP],
      'infoTool' => '/usr/bin/plutil', 'signature' => { 'tool' => '/usr/bin/codesign', 'before' => true, 'after' => true } }
    Signing.validate_record(record, expected_app: app)
    record
  end

  def receipt
    @collected_signing_record = signing_record_fixture
    @collected_pairing_signing_record = signing_record_fixture('pairing-app/Beluga.app')
    pairing_build, _pairing_bytes, pairing_contract = pairing_build_fixture
    log_texts = {
      'gate-self-tests' => gate_log,
      'simulator-signing-self-tests' => signing_log,
      'release-hook-self-tests' => "microphone release gate behavior tests passed\n",
      'host-release-hook-self-tests' => "microphone host release gate behavior tests passed\n",
      'mac-producer-contract-tests' => producer_log,
      'product-identity' => "Beluga product identity check passed\n",
      'product-identity-mutations' => "opensteamer product identity regression tests passed\n",
      'mac-discovery' => (@mac_methods + @shared_methods + @shared_replay_methods.values.flatten + @shared_reconnect_counter_methods + @handoff_methods).join("\n") + "\n", 'mac-tests' => mac_log,
      'shared-signaling-tests' => shared_log,
      'shared-handoff-tests' => mac_log(@handoff_methods),
      'simulator-summary' => JSON.generate(summary), 'simulator-results' => JSON.generate(results),
      'simulator-entitlements' => JSON.generate(@collected_signing_record),
      'pairing-inert-build' => pairing_build,
      'pairing-summary' => JSON.generate(pairing_summary), 'pairing-results' => JSON.generate(pairing_results),
      'pairing-entitlements' => JSON.generate(@collected_pairing_signing_record),
      'rust-discovery' => @rust_methods.map { |method| method + ': test' }.join("\n") + "\n",
      'beluga-core-discovery' => @core_methods.map { |method| method + ': test' }.join("\n") + "\n",
      'beluga-core-tests' => rust_log(@core_methods),
      'beluga-core-link' => core_link_log,
      'beluga-core-mutations' => core_mutations_log,
      'rust-tests' => rust_log, 'driver-tests' => c_log, 'driver-sanitizers' => c_log * 2,
      'driver-load' => "VERIFIED_BUILT_DRIVER_BUNDLE_LOAD\nPASS: loaded production driver idle-registration pressure and exact PCM\nPASS: loaded driver pristine and retired idle contract mutations\n",
      'driver-malformed-bundles' => "ALL_DRIVER_BUNDLE_VERIFIER_MUTATIONS_REJECTED\n",
      'driver-diagnostic-reader' => "DIAGNOSTIC_SNAPSHOT_READER_TESTS_PASSED_WITHOUT_CORE_AUDIO_IO\n"
    }
    Gate::SHARED_REPLAY_PHASES.each do |phase, suite|
      log_texts[phase] = replay_log(suite)
    end
    log_texts[Gate::SHARED_RECONNECT_COUNTER_PHASE] = replay_log(Gate::SHARED_RECONNECT_COUNTER_SUITE, @shared_reconnect_counter_methods)
    invocation = { 'developer_directory' => @developer, 'scratch' => @scratch, 'swift_scratch' => File.join(@scratch, 'SwiftPM'), 'timeout_seconds' => 1800 }
    commands = Gate.commands(@root, @evidence, invocation, @tools, SIMULATOR, @mac_methods, @handoff_methods)
    phases = Gate::PHASES.map do |name|
      log = name + '.log'
      path = File.join(@evidence, log)
      write(path, log_texts.fetch(name, 'fixture executor exited successfully'))
      { 'name' => name, 'argv' => commands.fetch(name), 'log' => log, 'sha256' => Gate.sha(path) }
    end
    artifacts = %w[simulator-result driver-bundle-1 driver-bundle-2].map do |name|
      path = name + '-artifact'
      write(File.join(@evidence, path, 'bytes'), name == 'simulator-result' ? 'fresh result tree' : 'identical universal bundle fixture')
      { 'name' => name, 'path' => path, 'sha256' => Gate.tree_identity(File.join(@evidence, path)), 'tree' => true }
    end
    artifacts << { 'name' => 'simulator-app', 'path' => 'simulator-app/Beluga.app',
                   'sha256' => Gate.tree_identity(@collected_signing_record['appPath']), 'tree' => true }
    write(File.join(@evidence, 'pairing.xcresult/bytes'), 'fresh pairing result fixture')
    [['pairing-result', 'pairing.xcresult'], ['pairing-app', 'pairing-app/Beluga.app'],
     ['pairing-inert-root-contract', 'pairing-inert-root-contract']].each do |name, relative|
      artifacts << { 'name' => name, 'path' => relative, 'sha256' => Gate.tree_identity(File.join(@evidence, relative)), 'tree' => true }
    end
    processes = [@pairing_build_process]
    Gate::PAIRING_PHASE_TIMEOUTS.keys.drop(1).each_with_index do |name, index|
      start = processes.last.fetch('finishedAtNanoseconds')
      processes << pairing_process_fixture(name, commands.fetch(name), start, start + 1, 12346 + index)
    end
    { 'schema' => Gate::SCHEMA, 'status' => 'passed', 'scope' => 'offline-source-only', 'root' => @root,
      'created_at' => Time.now.to_i, 'source' => Gate.source_identity(@root), 'tools' => @tools, 'simulator' => SIMULATOR,
      'invocation' => invocation, 'mac_format' => 'darwin-xctest-log', 'phases' => phases, 'artifacts' => artifacts, 'pairing_inert_root' => pairing_contract, 'pairing_processes' => processes,
      'coverage' => { 'mac' => @mac_methods, 'simulator' => @sim_methods, 'intentional_simulator_skips' => Gate::SIMULATOR_SKIPS, 'pairing' => @pairing_methods.dup,
                      'rust' => @rust_methods, 'beluga_core' => @core_methods, 'shared_handoff' => @handoff_methods, 'shared_replay' => @shared_replay_methods.transform_values(&:dup), 'shared_reconnect_counters' => @shared_reconnect_counter_methods.dup, 'c' => @c_methods } }
  end

  def save_receipt(value)
    path = File.join(@evidence, 'receipt.json')
    File.write(path, JSON.pretty_generate(value) + "\n")
    File.chmod(0600, path)
    [path, Gate.sha(path)]
  end

  def verify(value, during_collection: nil)
    path, digest = save_receipt(value)
    # Isolated fixture seam only. Production receipt verification always uses
    # the fixed codesign/plutil collector on the retained real app.
    Signing.stub(:collect, lambda { |app|
      record = [@collected_signing_record, @collected_pairing_signing_record].find { |candidate| candidate['appPath'] == app }
      raise Signing::Refusal, 'fixture app binding differs' unless record
      during_collection.call if during_collection
      Marshal.load(Marshal.dump(record))
    }) { Gate.verify_receipt(path, digest, @root) }
  end

  def rejects(message)
    error = assert_raises(RuntimeError) { yield }
    assert_includes error.message, message
  end

  def test_positive_receipt_replays_every_actual_parser
    value = receipt
    assert_equal 'passed', verify(value)['status']
    assert_equal @sim_methods, Gate.simulator_inventory(@root)
  end

  def test_gate_named_inventory_pins_new_refusal_cases
    assert_equal @gate_methods, Gate.gate_inventory(@root)
    path = File.join(@root, 'scripts/test-validate-microphone-regressions.rb')
    original = File.read(path)
    Gate::GATE_PINNED.each do |method|
      File.write(path, original.sub("def #{method}\nend\n", ''))
      rejects('harness inventory') { Gate.gate_inventory(@root) }
    end
    File.write(path, original + "def #{@gate_methods.first}\nend\n")
    rejects('harness inventory') { Gate.gate_inventory(@root) }
  end

  def test_gate_named_results_reject_omission_duplication_failure_skip_and_bad_footer
    assert_nil Gate.validate_harness(gate_log, @gate_methods)
    [gate_log.lines.drop(1).join, gate_log + gate_log.lines.first,
     gate_log.sub(@gate_methods.first, 'testUnexpectedFixture'), gate_log.sub(' s = .', ' s = ?')].each do |text|
      rejects('gate behavioral results') { Gate.validate_harness(text, @gate_methods) }
    end
    %w[S E F].each do |status|
      rejects('gate behavioral results') { Gate.validate_harness(gate_log.sub(' s = .', ' s = ' + status), @gate_methods) }
    end
    footer = gate_log.lines.last
    [gate_log.sub(footer, ''), gate_log + footer, footer + gate_log.sub(footer, ''),
     gate_log.sub('0 skips', '1 skips'), gate_log.sub('349 assertions', '0 assertions'),
     gate_log.sub("#{@gate_methods.length} runs", '0 runs')].each do |text|
      rejects('gate behavioral harness footer') { Gate.validate_harness(text, @gate_methods) }
    end
  end

  def test_gate_named_phase_cannot_remove_verbose_or_rehash_skipped_results
    value = receipt
    value['phases'].find { |phase| phase['name'] == 'gate-self-tests' }['argv'].delete('--verbose')
    rejects('canonical offline invocation') { verify(value) }
    value = receipt
    path = File.join(@evidence, 'gate-self-tests.log')
    File.write(path, gate_log.sub(' s = .', ' s = S'))
    value['phases'].find { |phase| phase['name'] == 'gate-self-tests' }['sha256'] = Gate.sha(path)
    rejects('gate behavioral results') { verify(value) }
  end

  def test_missing_critical_source_test_fails_inventory
    path = File.join(@root, 'iOS/opensteamer/Tests/AudioTests.swift')
    File.write(path, File.read(path).sub("func #{Gate::SIMULATOR_PINNED.first.split('/').last}() {}\n", ''))
    rejects('missing critical Simulator test') { Gate.simulator_inventory(@root) }
  end

  def test_missing_one_critical_executed_simulator_test
    value = results
    value['testNodes'].reject! { |node| node['nodeIdentifier'] == Gate::SIMULATOR_PINNED.first + '()' }
    rejects('missing or duplicate') { Gate.validate_simulator(summary, value, @sim_methods, SIMULATOR) }
  end

  def test_shipped_screen_awake_regressions_are_mandatory
    %w[ScreenVideoIdleTimerTests ScreenVideoIdleTimerViewTests].each do |name|
      assert_includes Gate::SIMULATOR_CLASSES, name
      methods = Gate::SIMULATOR_PINNED.select { |id| id.start_with?(name + '/') }
      refute_empty methods
      methods.each do |id|
        value = results
        value['testNodes'].reject! { |node| node['nodeIdentifier'] == id + '()' }
        rejects('missing or duplicate') { Gate.validate_simulator(summary, value, @sim_methods, SIMULATOR) }
      end
    end
    assert_includes Gate::SIMULATOR_PINNED,
                    'WorldwideAudioLifecycleTests/testExternalPausePublishesNotificationWhileStatisticsReaderIsSuspended'
  end

  def test_zero_executed_simulator_tests_cannot_borrow_summary
    rejects('zero Simulator tests') { Gate.validate_simulator(summary, { 'testNodes' => [] }, @sim_methods, SIMULATOR) }
  end

  def test_only_skipped_simulator_tests_cannot_pass
    value = results
    value['testNodes'].each { |node| node['result'] = 'Skipped' }
    rejects('unexpected failure, skip') { Gate.validate_simulator(summary, value, @sim_methods, SIMULATOR) }
  end

  def test_unexpected_simulator_skip_and_expected_failure_are_rejected
    value = results
    value['testNodes'].find { |node| node['nodeIdentifier'] == Gate::SIMULATOR_PINNED.first + '()' }['result'] = 'Skipped'
    rejects('unexpected failure, skip') { Gate.validate_simulator(summary, value, @sim_methods, SIMULATOR) }
    changed = summary
    changed['expectedFailures'] = 1
    rejects('summary counts') { Gate.validate_simulator(changed, results, @sim_methods, SIMULATOR) }
  end

  def test_duplicate_simulator_results_and_wrong_destination_fail
    value = results
    value['testNodes'] << value['testNodes'].first.dup
    rejects('missing or duplicate') { Gate.validate_simulator(summary, value, @sim_methods, SIMULATOR) }
    changed = summary
    changed['devicesAndConfigurations'][0]['device']['platform'] = 'iOS'
    rejects('physical or different') { Gate.validate_simulator(changed, results, @sim_methods, SIMULATOR) }
  end

  def test_mac_zero_omitted_skipped_and_duplicate_cases_fail
    rejects('zero executed') { Gate.validate_mac_log(mac_log([]), @mac_methods) }
    rejects('missing Mac result') { Gate.validate_mac_log(mac_log(@mac_methods.drop(1)), @mac_methods) }
    rejects('failed, skipped') { Gate.validate_mac_log(mac_log.sub('passed (0.001 seconds)', 'skipped (0.001 seconds)'), @mac_methods) }
    rejects('duplicate') { Gate.validate_mac_log(mac_log(@mac_methods + [@mac_methods.first]), @mac_methods) }
  end

  def test_xunit_requires_exact_non_skipping_behavioral_results
    cases = @mac_methods.map { |id| klass, name = id.split('/'); %Q{<testcase classname="#{klass}" name="#{name}"/>} }
    assert_equal @mac_methods, Gate.validate_xunit('<testsuite>' + cases.join + '</testsuite>', @mac_methods)
    rejects('failed or skipped') { Gate.validate_xunit('<testsuite>' + cases.join.sub('/>', '><skipped/></testcase>') + '</testsuite>', @mac_methods) }
    rejects('zero Mac') { Gate.validate_xunit('<testsuite/>', @mac_methods) }
  end

  def test_rust_missing_ignored_and_zero_results_fail
    assert_equal @rust_methods, Gate.validate_rust(rust_log, @rust_methods)
    rejects('missing, duplicate') { Gate.validate_rust(rust_log.lines.drop(1).join, @rust_methods) }
    rejects('ignored') { Gate.validate_rust(rust_log.sub('... ok', '... ignored'), @rust_methods) }
    rejects('zero Rust') { Gate.validate_rust('test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;', @rust_methods) }
  end

  def test_beluga_core_has_independent_discovered_non_skipping_coverage
    text = @core_methods.map { |method| method + ': test' }.join("\n")
    assert_equal @core_methods, Gate.beluga_core_inventory(text)
    refute (Gate::RUST_PINNED & @core_methods).any?
    assert_equal @core_methods, Gate.validate_rust(rust_log(@core_methods), @core_methods)
    rejects('critical Rust') { Gate.rust_inventory(text) }
    Gate::BELUGA_CORE_PINNED.each do |id|
      rejects('missing critical Beluga core') { Gate.beluga_core_inventory((@core_methods - [id]).map { |method| method + ': test' }.join("\n")) }
    end
    rejects('duplicate Beluga core') { Gate.beluga_core_inventory(text + "\n" + @core_methods.first + ': test') }
    rejects('empty or duplicate Beluga core') { Gate.beluga_core_inventory('') }
    rejects('valid UTF-8') { Gate.beluga_core_inventory(text.b + "\xFF".b) }
    rejects('ignored') { Gate.validate_rust(rust_log(@core_methods).sub('... ok', '... ignored'), @core_methods) }
    rejects('missing, duplicate') { Gate.validate_rust(rust_log(@core_methods.drop(1)), @core_methods) }
    rejects('ignored coverage') { Gate.validate_rust(rust_log(@core_methods).sub('0 filtered out', '1 filtered out'), @core_methods) }
  end

  def test_beluga_core_phases_and_exact_crate_commands_are_mandatory
    %w[beluga-core-artifact-validation beluga-core-link beluga-core-mutations beluga-core-discovery beluga-core-tests].each do |name|
      value = receipt
      value['phases'].reject! { |phase| phase['name'] == name }
      rejects('absent, duplicate') { verify(value) }
      value = receipt
      value['phases'].find { |phase| phase['name'] == name }['argv'] = ['/usr/bin/true']
      rejects('canonical offline invocation') { verify(value) }
    end
    %w[beluga-core-discovery beluga-core-tests].each do |name|
      %w[--offline --locked --manifest-path].each do |option|
        value = receipt
        value['phases'].find { |phase| phase['name'] == name }['argv'].delete(option)
        rejects('canonical offline invocation') { verify(value) }
      end
      value = receipt
      argv = value['phases'].find { |phase| phase['name'] == name }['argv']
      argv[argv.index('--manifest-path') + 1] = File.join(@root, 'iOS/opensteamer/Rust/AudioTransactionAuthority/Cargo.toml')
      rejects('canonical offline invocation') { verify(value) }
    end
    value = receipt
    value['coverage'].delete('beluga_core')
    rejects('unrecognized field set') { verify(value) }
    value = receipt
    value['coverage']['beluga_core'] = @rust_methods
    rejects('Beluga core coverage differs') { verify(value) }
  end

  def test_beluga_core_rehashed_results_cannot_omit_or_skip_discovered_cases
    [rust_log(@core_methods.drop(1)), rust_log(@core_methods).sub('... ok', '... ignored')].each do |text|
      value = receipt
      path = File.join(@evidence, 'beluga-core-tests.log')
      File.write(path, text)
      value['phases'].find { |phase| phase['name'] == 'beluga-core-tests' }['sha256'] = Gate.sha(path)
      rejects(text.include?('... ignored') ? 'ignored' : 'missing, duplicate') { verify(value) }
    end
    value = receipt
    id = Gate::BELUGA_CORE_PINNED.first
    path = File.join(@evidence, 'beluga-core-discovery.log')
    File.write(path, (@core_methods - [id]).map { |method| method + ': test' }.join("\n"))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-discovery' }['sha256'] = Gate.sha(path)
    value['coverage']['beluga_core'] = @core_methods - [id]
    result = File.join(@evidence, 'beluga-core-tests.log')
    File.write(result, rust_log(@core_methods - [id]))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-tests' }['sha256'] = Gate.sha(result)
    rejects('missing critical Beluga core') { verify(value) }
  end

  def test_beluga_core_ignored_artifact_complete_bytes_are_source_bound
    value = receipt
    entries = value['source']['files'].select { |entry| entry.first.start_with?(Gate::BELUGA_CORE_ARTIFACT + '/') }
    assert_equal (Gate::BELUGA_CORE_ARTIFACT_FILES + ['ARTIFACT_MANIFEST.sha256']).sort,
                 entries.map { |entry| entry.first.delete_prefix(Gate::BELUGA_CORE_ARTIFACT + '/') }.sort
    File.write(File.join(core_artifact, 'macos-arm64/BelugaCore.framework/BelugaCore'), 'changed ignored archive')
    rejects('source identity') { verify(value) }
    rejects('checksum differs') { Gate.validate_beluga_core_artifacts(@root) }
  end

  def test_beluga_core_rejects_missing_unbound_symlinked_or_empty_artifact
    path = File.join(core_artifact, 'macos-arm64/BelugaCore.framework/BelugaCore')
    original = File.binread(path)
    File.unlink(path)
    rejects('missing or unbound files') { Gate.validate_beluga_core_artifacts(@root) }
    File.symlink(File.join(core_crate, 'src/lib.rs'), path)
    rejects('unsupported node') { Gate.validate_beluga_core_artifacts(@root) }
    File.unlink(path)
    File.write(path, '')
    refresh_core_artifact_manifest
    rejects('empty required file') { Gate.validate_beluga_core_artifacts(@root) }
    File.binwrite(path, original)
    write(File.join(core_artifact, 'unbound-extra'), 'not enrolled')
    refresh_core_artifact_manifest
    rejects('missing or unbound files') { Gate.validate_beluga_core_artifacts(@root) }
  end

  def test_beluga_core_rejects_absent_or_symlinked_artifact
    FileUtils.remove_entry_secure(core_artifact)
    rejects('absent, symlinked or noncanonical') { Gate.source_identity(@root) }
    rejects('absent, symlinked or noncanonical') { Gate.validate_beluga_core_artifacts(@root) }
    File.symlink(core_crate, core_artifact)
    rejects('absent, symlinked or noncanonical') { Gate.source_identity(@root) }
    rejects('absent, symlinked or noncanonical') { Gate.validate_beluga_core_artifacts(@root) }
    File.unlink(core_artifact)
    FileUtils.mkdir_p(core_artifact)
    parent = File.dirname(core_artifact)
    retained = File.join(@temporary, 'private-vendor-parent')
    FileUtils.mv(parent, retained)
    File.symlink(retained, parent)
    rejects('noncanonical') { Gate.source_identity(@root) }
    rejects('noncanonical') { Gate.validate_beluga_core_artifacts(@root) }
  end

  def test_beluga_core_actual_link_and_named_assertion_mutations_cannot_be_skipped
    %w[beluga-core-link beluga-core-mutations].each do |name|
      value = receipt
      path = File.join(@evidence, name + '.log')
      File.write(path, 'PASS')
      value['phases'].find { |phase| phase['name'] == name }['sha256'] = Gate.sha(path)
      rejects(name == 'beluga-core-link' ? 'link oracle is incomplete' : 'mutation oracle is incomplete') { verify(value) }
    end
    rejects('link oracle is incomplete') { Gate.validate_beluga_core_link("BELUGA_CORE_LINK_SMOKE_PASS\n" * 2) }
    markers = Gate::BELUGA_CORE_MUTANTS.map { |name| "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n" }
    footer = "BELUGA_CORE_MUTATIONS_PASS cases=#{markers.length}\n"
    [markers.drop(1).join + footer, markers.reverse.join + footer, markers.join + markers.first + footer,
     footer + markers.join, markers.join + footer * 2, markers.join.sub('assertion-failed', 'compile-failed') + footer,
     markers.join + footer.sub(markers.length.to_s, '0')].each do |text|
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(text) }
    end
  end

  def test_beluga_core_rejects_stale_or_missing_source_manifest_and_unbound_source
    path = File.join(core_crate, 'src/lib.rs')
    File.write(path, 'changed source without rebuilt artifact')
    rejects('checksum differs') { Gate.validate_beluga_core_artifacts(@root) }
    refresh_core_source_manifest(publish: false)
    rejects('published source manifest is stale') { Gate.validate_beluga_core_artifacts(@root) }
    refresh_core_source_manifest
    refresh_core_artifact_manifest
    assert_nil Gate.validate_beluga_core_artifacts(@root)
    write(File.join(core_crate, 'src/unbound.rs'), 'new source file without manifest entry')
    rejects('required source files are missing or unbound') { Gate.validate_beluga_core_artifacts(@root) }
    File.unlink(File.join(core_crate, 'src/unbound.rs'))
    File.unlink(File.join(core_crate, 'SOURCE_MANIFEST.sha256'))
    rejects('could not read a required file') { Gate.validate_beluga_core_artifacts(@root) }
  end

  def test_beluga_core_rejects_symlinked_source_and_duplicate_manifest_records
    source = File.join(core_crate, 'src/lib.rs')
    bytes = File.binread(source)
    File.unlink(source)
    File.symlink(File.join(core_crate, 'include/beluga_core.h'), source)
    rejects('unsupported node') { Gate.validate_beluga_core_artifacts(@root) }
    File.unlink(source)
    File.binwrite(source, bytes)
    manifest = File.join(core_crate, 'SOURCE_MANIFEST.sha256')
    original = File.binread(manifest)
    File.binwrite(manifest, original + original.lines.first)
    rejects('missing, duplicate or unbound files') { Gate.validate_beluga_core_artifacts(@root) }
    File.binwrite(manifest, original)
    published = File.join(core_artifact, 'ARTIFACT_MANIFEST.sha256')
    original = File.binread(published)
    File.binwrite(published, original + original.lines.first)
    rejects('missing, duplicate or unbound files') { Gate.validate_beluga_core_artifacts(@root) }
  end

  def test_beluga_core_pinned_link_tools_cannot_be_omitted_or_replaced
    [File.join(@developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'),
     File.join(@developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/clang'), '/usr/bin/lipo', '/usr/bin/xcrun',
     @tools.keys.find { |path| File.basename(path) == 'rustc' }].each do |tool|
      value = receipt
      value['tools'] = value['tools'].dup
      value['tools'].delete(tool)
      rejects('reviewed tool identities') { verify(value) }
      value = receipt
      value['tools'] = value['tools'].dup
      digest = value['tools'].delete(tool)
      substitute = File.join(@temporary, 'fixture-tools/replaced', File.basename(tool))
      write(substitute, 'unreviewed tool fixture')
      value['tools'][substitute] = Gate.sha(substitute)
      refute_equal digest, value['tools'][substitute]
      rejects(File.basename(tool) == 'rustc' ? 'recorded Beluga core Rust compiler' : 'recorded Beluga core tools') { verify(value) }
    end
  end

  def test_beluga_core_rehashed_header_slice_or_tool_metadata_drift_is_rejected
    path = File.join(core_artifact, 'macos-arm64/BelugaCore.framework/Headers/beluga_core.h')
    original = File.binread(path)
    File.write(path, 'different exported ABI')
    refresh_core_artifact_manifest
    rejects('published header, module or notice differs') { Gate.validate_beluga_core_artifacts(@root) }
    File.binwrite(path, original)
    plist_path = File.join(core_artifact, 'Info.plist')
    plist = File.binread(plist_path)
    [plist.sub('<string>macos</string>', '<string>ios</string>'),
     plist.sub('<string>arm64</string>', '<string>x86_64</string>'),
     plist.sub('<key>SupportedPlatform</key>', '<key>LibraryPath</key>'),
     plist.sub('<key>LibraryPath</key>', '<key>SupportedPlatformVariant</key>')].each do |bytes|
      File.binwrite(plist_path, bytes)
      refresh_core_artifact_manifest
      rejects('Beluga core XCFramework') { Gate.validate_beluga_core_artifacts(@root) }
    end
    File.binwrite(plist_path, plist)
    metadata_path = File.join(core_artifact, 'BUILD_METADATA.txt')
    metadata = File.binread(metadata_path)
    [metadata.sub('1.97.1', '1.98.0'), metadata.sub('supported-architecture=arm64', 'supported-architecture=x86_64'),
     metadata.sub('Xcode 26.6', 'Xcode 27.0'), metadata + "release: 1.97.1\n"].each do |bytes|
      File.binwrite(metadata_path, bytes)
      refresh_core_artifact_manifest
      rejects('build metadata differs') { Gate.validate_beluga_core_artifacts(@root) }
    end
  end

  def test_beluga_core_multiplatform_slice_inventory_and_each_copied_abi_are_exact
    assert_equal %w[ios-arm64 ios-arm64_x86_64-simulator macos-arm64], Gate::BELUGA_CORE_SLICES.keys.sort
    assert_equal 16, Gate::BELUGA_CORE_ARTIFACT_FILES.length
    assert_equal 32, Gate::BELUGA_CORE_SOURCE_FILES.length
    %w[src/handoff_transactions.rs tests/handoff_transactions.rs src/handoff_offers.rs tests/handoff_offers.rs
       src/youtube_handoff_operation.rs tests/youtube_handoff_operation.rs].each do |path|
      assert_includes Gate::BELUGA_CORE_SOURCE_FILES, path
    end
    assert_nil Gate.validate_beluga_core_artifacts(@root)
    Gate::BELUGA_CORE_SLICES.keys.each do |slice|
      path = File.join(core_artifact, slice, 'BelugaCore.framework/BelugaCore')
      bytes = File.binread(path)
      File.unlink(path)
      refresh_core_artifact_manifest
      rejects('missing or unbound files') { Gate.validate_beluga_core_artifacts(@root) }
      File.binwrite(path, bytes)
      %w[Headers/beluga_core.h Modules/module.modulemap].each do |name|
        path = File.join(core_artifact, slice, 'BelugaCore.framework', name)
        bytes = File.binread(path)
        File.write(path, 'stale ABI copy for ' + slice)
        refresh_core_artifact_manifest
        rejects('published header, module or notice differs') { Gate.validate_beluga_core_artifacts(@root) }
        File.binwrite(path, bytes)
      end
    end
    plist_path = File.join(core_artifact, 'Info.plist')
    original = File.binread(plist_path)
    libraries = Gate.beluga_core_plist_value(REXML::Document.new(original).root.elements.to_a.first)['AvailableLibraries']
    File.write(plist_path, core_plist(libraries.reverse))
    refresh_core_artifact_manifest
    assert_nil Gate.validate_beluga_core_artifacts(@root)
    variations = [libraries.drop(1), libraries + [libraries.first], [libraries.first] * libraries.length]
    libraries.each_index do |index|
      ['LibraryIdentifier', 'HeadersPath', 'LibraryPath', 'BinaryPath', 'SupportedArchitectures', 'SupportedPlatform', 'SupportedPlatformVariant'].each do |key|
        copy = Marshal.load(Marshal.dump(libraries))
        copy[index][key] = key == 'SupportedArchitectures' ? ['x86_64'] : 'wrong'
        variations << copy
        copy = Marshal.load(Marshal.dump(libraries))
        copy[index].delete(key)
        variations << copy if libraries[index].key?(key)
      end
    end
    variations.each do |changed|
      File.write(plist_path, core_plist(changed))
      refresh_core_artifact_manifest
      rejects('Beluga core XCFramework') { Gate.validate_beluga_core_artifacts(@root) }
    end
    File.binwrite(plist_path, original)
    refresh_core_artifact_manifest
    assert_nil Gate.validate_beluga_core_artifacts(@root)
  end

  def test_beluga_core_framework_layout_rejects_flat_header_collision_and_wrong_bundle_metadata
    assert_equal 'BelugaCore.framework', Gate::BELUGA_CORE_FRAMEWORK
    assert_includes Gate::BELUGA_CORE_METADATA_PREFIX, 'packaging-profile=static-framework-v1'
    assert_nil Gate.validate_beluga_core_artifacts(@root)
    Gate::BELUGA_CORE_SLICES.keys.each do |slice|
      framework = File.join(core_artifact, slice, 'BelugaCore.framework')
      path = File.join(framework, 'Info.plist')
      original = File.binread(path)
      info = Gate.beluga_core_plist(original, 'Fixture framework plist')
      assert_equal 9, info.length
      assert_equal 'BelugaCore', info['CFBundleExecutable']
      assert_equal 'FMWK', info['CFBundlePackageType']
      assert_equal 'com.elamin.beluga.core', info['CFBundleIdentifier']
      info.each_key do |key|
        changed = info.dup
        changed[key] = info[key].is_a?(Array) ? ['WrongPlatform'] : 'wrong'
        File.write(path, fixture_plist(changed))
        refresh_core_artifact_manifest
        rejects('framework bundle metadata differs') { Gate.validate_beluga_core_artifacts(@root) }
        changed = info.dup
        changed.delete(key)
        File.write(path, fixture_plist(changed))
        refresh_core_artifact_manifest
        rejects('framework bundle metadata differs') { Gate.validate_beluga_core_artifacts(@root) }
      end
      File.write(path, fixture_plist(info.merge('HeadersPath' => 'Headers')))
      refresh_core_artifact_manifest
      rejects('framework bundle metadata differs') { Gate.validate_beluga_core_artifacts(@root) }
      duplicate = original.sub('</dict>', '<key>CFBundleExecutable</key><string>BelugaCore</string></dict>')
      File.write(path, duplicate)
      refresh_core_artifact_manifest
      rejects('malformed or duplicate keys') { Gate.validate_beluga_core_artifacts(@root) }
      File.binwrite(path, original)
      flat_header = File.join(core_artifact, slice, 'Headers/module.modulemap')
      write(flat_header, 'module BelugaCore { header "beluga_core.h" export * }')
      refresh_core_artifact_manifest
      rejects('missing or unbound files') { Gate.validate_beluga_core_artifacts(@root) }
      File.unlink(flat_header)
      flat_archive = File.join(core_artifact, slice, 'libbeluga_core.a')
      write(flat_archive, 'old colliding flat static archive')
      refresh_core_artifact_manifest
      rejects('missing or unbound files') { Gate.validate_beluga_core_artifacts(@root) }
      File.unlink(flat_archive)
    end
    path = File.join(core_artifact, 'Info.plist')
    original = File.binread(path)
    libraries = Gate.beluga_core_plist(original, 'Fixture XCFramework plist').fetch('AvailableLibraries')
    old = libraries.map do |library|
      library.merge('LibraryPath' => 'libbeluga_core.a', 'BinaryPath' => 'libbeluga_core.a', 'HeadersPath' => 'Headers')
    end
    File.write(path, core_plist(old))
    refresh_core_artifact_manifest
    rejects('exact reviewed platform, architecture or ABI slice') { Gate.validate_beluga_core_artifacts(@root) }
    File.binwrite(path, original)
    metadata = File.join(core_artifact, 'BUILD_METADATA.txt')
    original = File.binread(metadata)
    File.binwrite(metadata, original.sub("packaging-profile=static-framework-v1\n", ''))
    refresh_core_artifact_manifest
    rejects('build metadata differs') { Gate.validate_beluga_core_artifacts(@root) }
    File.binwrite(metadata, original)
    refresh_core_artifact_manifest
    assert_nil Gate.validate_beluga_core_artifacts(@root)
  end

  def test_beluga_core_static_framework_executable_refuses_dynamic_or_malformed_fat_payload
    Gate::BELUGA_CORE_SLICES.keys.each do |slice|
      path = File.join(core_artifact, slice, 'BelugaCore.framework/BelugaCore')
      original = File.binread(path)
      File.binwrite(path, "\xcf\xfa\xed\xfe".b + 'dynamic framework fixture')
      refresh_core_artifact_manifest
      rejects(slice == 'ios-arm64_x86_64-simulator' ? 'reviewed universal static archive' : 'not a static archive') { Gate.validate_beluga_core_artifacts(@root) }
      File.binwrite(path, original)
    end
    path = File.join(core_artifact, 'ios-arm64_x86_64-simulator/BelugaCore.framework/BelugaCore')
    original = File.binread(path)
    mutations = [original.byteslice(0, 36), original.dup, original.dup, original.dup, original.dup, original.dup]
    mutations[1][4, 4] = [1].pack('N')
    mutations[2][28, 4] = [0x0100000c].pack('N')
    mutations[3][36, 4] = [48].pack('N')
    mutations[4][16, 4] = [0xffffffff].pack('N')
    mutations[5][48, 8] = 'not-ar!!'
    mutations.each do |changed|
      File.binwrite(path, changed)
      refresh_core_artifact_manifest
      rejects('Beluga core Simulator') { Gate.validate_beluga_core_artifacts(@root) }
    end
    File.binwrite(path, original)
    refresh_core_artifact_manifest
    assert_nil Gate.validate_beluga_core_artifacts(@root)
  end

  def test_beluga_core_all_reviewed_targets_sdks_and_cross_links_are_mandatory
    assert_equal %w[aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios], Gate::BELUGA_CORE_TARGETS
    path = File.join(core_artifact, 'BUILD_METADATA.txt')
    original = File.binread(path)
    mutations = [original + "unexpected-field=true\n", original.sub('simulator-architectures=arm64,x86_64', 'simulator-architectures=arm64'),
                 original.sub('binary: rustc', 'binary: unbound'), original.sub('commit-hash: ' + 'a' * 40, 'commit-hash: unknown')]
    Gate::BELUGA_CORE_TARGETS.each do |target|
      line = 'supported-target=' + target + "\n"
      mutations += [original.sub(line, ''), original.sub(line, line * 2), original.sub(line, "supported-target=wrong\n")]
    end
    %w[macos iphoneos iphonesimulator].each do |sdk|
      line = sdk + "-sdk=26.6\n"
      mutations += [original.sub(line, ''), original.sub(line, line * 2), original.sub(line, sdk + "-sdk=unknown\n")]
    end
    mutations.each do |changed|
      File.binwrite(path, changed)
      refresh_core_artifact_manifest
      rejects('build metadata differs') { Gate.validate_beluga_core_artifacts(@root) }
    end
    File.binwrite(path, original)
    refresh_core_artifact_manifest
    assert_nil Gate.validate_beluga_core_artifacts(@root)
    assert_nil Gate.validate_beluga_core_link(core_link_log)
    core_link_log.lines.each do |marker|
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker, '')) }
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log + marker) }
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker, marker.sub('PASS', 'SKIPPED'))) }
    end
    rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.lines.reverse.join) }
    rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log + "BELUGA_CORE_CROSS_LINK_PASS target=unreviewed\n") }
    value = receipt
    log = File.join(@evidence, 'beluga-core-link.log')
    File.write(log, "BELUGA_CORE_LINK_SMOKE_PASS\n")
    value['phases'].find { |phase| phase['name'] == 'beluga-core-link' }['sha256'] = Gate.sha(log)
    rejects('link oracle is incomplete') { verify(value) }
  end

  def test_beluga_core_transaction_tests_and_each_negative_mutant_are_mandatory
    tests = %w[exhaustive_transaction_state_event_graph_matches_reference host_busy_rejects_replacement_without_revocation
               host_completion_requires_exact_receipt_and_envelope cached_reply_is_idempotent_and_conflicting_reply_rejected
               host_revocation_occurs_on_finish_replacement_and_clear viewer_completion_and_expiry_require_exact_identity
               clear_and_expiry_report_unknown_once_without_pause_effect invalid_transaction_inputs_fail_closed
               transaction_scalar_exports_and_layout_match_core deterministic_transaction_churn_matches_reference]
    assert_equal tests, Gate::BELUGA_CORE_PINNED.first(25).last(tests.length)
    tests.each do |id|
      rejects('missing critical Beluga core') { Gate.beluga_core_inventory((@core_methods - [id]).map { |method| method + ': test' }.join("\n")) }
    end
    mutants = %w[transaction-busy-admission-removed transaction-receipt-match-removed transaction-envelope-match-removed
                 transaction-conflicting-reply-accepted transaction-revocation-removed transaction-timeout-reports-success]
    assert_equal mutants, Gate::BELUGA_CORE_MUTANTS.first(11).last(mutants.length)
    markers = Gate::BELUGA_CORE_MUTANTS.map { |name| "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n" }
    text = core_mutations_log
    assert_nil Gate.validate_beluga_core_mutations(text)
    markers.each do |marker|
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(text.sub(marker, '')) }
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(text.sub(marker, marker.sub('assertion-failed', 'compile-failed'))) }
    end
    value = receipt
    path = File.join(@evidence, 'beluga-core-mutations.log')
    File.write(path, core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(5)))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-mutations' }['sha256'] = Gate.sha(path)
    rejects('mutation oracle is incomplete') { verify(value) }
  end

  def test_beluga_core_offers_source_tests_link_smokes_and_mutants_are_mandatory
    tests = %w[independent_slots_preserve_other_owner rejected_new_sequence_burns_and_retires_before_late_validation
               matching_consumption_cannot_revive_after_late_failure wrong_identity_and_invalid_phone_observation_do_not_consume
               exact_freshness_sample_deadline_and_uncertainty_boundaries clear_preserves_counters_and_send_capacity_cannot_wrap
               source_description_numeric_crosscheck_matches_reference raw_float_bits_preserve_signed_zero_and_extreme_derived_deadline
               bounded_deterministic_original_reference_trace_matches_all_projections
               malformed_abi_state_and_unknown_flags_fail_closed_without_native_authority
               commit_header_and_current_primary_identity_are_independent received_primary_matches_the_incoming_not_the_retired_receipt
               actual_double_adjacent_boundaries_have_expected_decisions maximum_received_sequence_does_not_wrap_or_disable_independent_send
               tentative_scalar_layout_sizes_alignments_and_offsets_are_explicit
               nonfinite_events_preserve_order_but_nonfinite_owned_state_is_invalid
               unknown_operation_is_invalid_unchanged_without_retirement_or_success
               wire_authorization_and_exact_numeric_identity_guard_slots exported_offer_functions_match_safe_reducer]
    assert_equal 139, Gate::BELUGA_CORE_PINNED.length
    assert_equal tests, Gate::BELUGA_CORE_PINNED.first(44).last(tests.length)
    tests.each do |id|
      omitted = @core_methods - [id]
      rejects('missing critical Beluga core') { Gate.beluga_core_inventory(omitted.map { |method| method + ': test' }.join("\n")) }
      rejects('missing, duplicate') { Gate.validate_rust(rust_log(omitted), @core_methods) }
      rejects('ignored') { Gate.validate_rust(rust_log(@core_methods).sub("test #{id} ... ok", "test #{id} ... ignored"), @core_methods) }
    end
    %w[src/handoff_offers.rs tests/handoff_offers.rs].each do |relative|
      assert_includes Gate::BELUGA_CORE_SOURCE_FILES, relative
      path = File.join(core_crate, relative)
      original = File.binread(path)
      File.unlink(path)
      # Even a rehashed, mutually matching pair of manifests cannot delete a
      # required reducer or its independent source tests.
      refresh_core_source_manifest
      refresh_core_artifact_manifest
      rejects('required source files are missing or unbound') { Gate.validate_beluga_core_artifacts(@root) }
      File.binwrite(path, original)
      refresh_core_source_manifest
      refresh_core_artifact_manifest
    end
    mutants = %w[offers-source-identity-bypassed offers-commit-identity-bypassed offers-receive-auth-bypassed
                 offers-receive-sequence-burn-removed offers-receive-old-retirement-removed offers-receive-sequence-replay-admitted
                 offers-sent-consuming-retirement-removed offers-received-consuming-retirement-removed offers-phone-sample-age-widened
                 offers-freshness-inclusive offers-deadline-inclusive offers-timeline-tolerance-widened
                 offers-host-position-tolerance-widened offers-clear-resets-counters offers-sent-sequence-reused
                 offers-unknown-operation-clears-state]
    assert_equal 77, Gate::BELUGA_CORE_MUTANTS.length
    assert_equal mutants, Gate::BELUGA_CORE_MUTANTS.first(27).last(mutants.length)
    assert_nil Gate.validate_beluga_core_mutations(core_mutations_log)
    mutants.each do |name|
      marker = "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, '')) }
      assert_includes tests, Gate::BELUGA_CORE_MUTANT_TESTS.fetch(name)
    end
    rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(11))) }
    [
      'BelugaCore C offers ABI PASS: independent owners, sequence burn, consuming rejection and exact layouts',
      'BelugaCore Swift offers import/link PASS: independent owners, sequence burn, consuming rejection and exact layouts'
    ].each do |marker|
      assert_includes Gate::BELUGA_CORE_RUNTIME_MARKERS, marker
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker + "\n", '')) }
    end
    value = receipt
    path = File.join(@evidence, 'beluga-core-discovery.log')
    without_offers = @core_methods - tests
    File.write(path, without_offers.map { |method| method + ': test' }.join("\n"))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-discovery' }['sha256'] = Gate.sha(path)
    value['coverage']['beluga_core'] = without_offers
    result = File.join(@evidence, 'beluga-core-tests.log')
    File.write(result, rust_log(without_offers))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-tests' }['sha256'] = Gate.sha(result)
    rejects('missing critical Beluga core') { verify(value) }
    rejects('result footer disagrees') do
      Gate.validate_rust(rust_log(@core_methods).sub("#{@core_methods.length} passed", '25 passed'), @core_methods)
    end
  end

  def test_beluga_core_phone_operation_source_tests_link_smokes_and_mutants_are_mandatory
    tests = %w[copied_abi_layout_is_exact_and_pointer_free ready_stationary_paused_and_wrong_position_do_not_confirm
               slow_provider_requires_the_advancing_original_request_timeline
               advancing_exact_visible_playback_confirms_once_without_refreshing_proof
               blocked_provider_requests_play_but_never_claims_confirmation
               hidden_once_visible_and_every_terminal_failure_cannot_revive
               foreign_identity_returns_before_time_but_matching_replay_observes_time
               wrong_video_burns_matching_sequence_before_terminal_failure
               original_proof_age_never_renews_but_completion_uses_latest_sample
               interruption_or_seek_cannot_revive_previously_confirmed_authority
               clock_regression_and_nonfinite_clock_fail_without_rewriting_last_bits
               only_reserved_correlated_completion_moves_and_cannot_be_replayed
               committed_local_controls_past_deadline_never_reopen_authority
               pending_interruption_becomes_unknown_and_late_success_cannot_revive
               successful_native_pause_is_retained_even_when_phone_freshness_fails
               reply_timeout_precedes_offer_timeout_and_never_renews_deadline
               every_pending_failure_retains_proof_but_becomes_unknown_terminal
               rejected_and_unknown_completion_results_retain_their_honest_status
               whole_native_proof_equality_and_scalar_identity_are_separate_guards
               initial_nonfinite_and_signed_zero_bits_are_stored_without_observation
               negative_monotone_times_can_confirm_and_reserve_negative_reply_deadline
               duration_tolerance_can_confirm_evidence_beyond_original_request_duration
               sample_partial_presence_burns_sequence_but_never_processes_partial_sample
               candidate_zero_is_ignored_before_the_genuine_new_proof_mint_point
               eligible_zero_candidate_fails_invalid_bridge_after_clock_and_sequence_burn
               maximum_candidate_is_valid_once_and_later_candidate_zero_cannot_remint
               raw_state_value_copies_are_independent_and_native_fact_blocks_cross_proof
               exact_advance_elapsed_and_original_proof_age_boundaries_match_double_semantics
               is_current_silent_failure_does_not_fabricate_an_emitted_failure_event
               malformed_abi_and_every_structural_state_field_fail_byte_identically
               malformed_opcodes_domains_optional_payloads_and_primitive_fields_fail_closed
               deterministic_independent_traces_compare_every_raw_state_event_and_boolean]
    assert_equal 32, tests.length
    assert_equal 139, Gate::BELUGA_CORE_PINNED.length
    assert_equal Gate::BELUGA_CORE_PINNED.length, Gate::BELUGA_CORE_PINNED.uniq.length
    assert_equal tests, Gate::BELUGA_CORE_PINNED.first(76).last(tests.length)
    tests.each do |id|
      omitted = @core_methods - [id]
      rejects('missing critical Beluga core') { Gate.beluga_core_inventory(omitted.map { |method| method + ': test' }.join("\n")) }
      rejects('missing, duplicate') { Gate.validate_rust(rust_log(omitted), @core_methods) }
      rejects('ignored') { Gate.validate_rust(rust_log(@core_methods).sub("test #{id} ... ok", "test #{id} ... ignored"), @core_methods) }
    end
    %w[src/youtube_handoff_operation.rs tests/youtube_handoff_operation.rs].each do |relative|
      assert_includes Gate::BELUGA_CORE_SOURCE_FILES, relative
      path = File.join(core_crate, relative)
      original = File.binread(path)
      File.unlink(path)
      refresh_core_source_manifest
      refresh_core_artifact_manifest
      rejects('required source files are missing or unbound') { Gate.validate_beluga_core_artifacts(@root) }
      File.binwrite(path, original)
      refresh_core_source_manifest
      refresh_core_artifact_manifest
    end
    mutants = {
      'phone-foreign-clock-before-identity' => 'foreign_identity_returns_before_time_but_matching_replay_observes_time',
      'phone-stale-sequence-before-clock' => 'foreign_identity_returns_before_time_but_matching_replay_observes_time',
      'phone-repeated-begin-reservation' => 'only_reserved_correlated_completion_moves_and_cannot_be_replayed',
      'phone-original-proof-age-refreshed' => 'original_proof_age_never_renews_but_completion_uses_latest_sample',
      'phone-paused-outcome-forgotten' => 'successful_native_pause_is_retained_even_when_phone_freshness_fails',
      'phone-pending-failure-keeps-reservation' => 'every_pending_failure_retains_proof_but_becomes_unknown_terminal'
    }
    assert_equal 77, Gate::BELUGA_CORE_MUTANTS.length
    assert_equal mutants.to_a, Gate::BELUGA_CORE_MUTANT_TESTS.to_a.first(33).last(mutants.length)
    assert_nil Gate.validate_beluga_core_mutations(core_mutations_log)
    mutants.each do |name, test|
      assert_includes tests, test
      marker = "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, '')) }
      rejects('mutation oracle is incomplete') do
        Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, marker.sub('assertion-failed', 'compile-failed')))
      end
      segment = core_mutations_log([name]).sub("BELUGA_CORE_MUTATIONS_PASS cases=1\n", '')
      [segment.sub("test #{test} ... FAILED", "test unrelated_assertion ... FAILED"),
       segment.sub("test #{test} ... FAILED", "test #{test} ... ignored"),
       segment.sub('0 passed; 1 failed; 0 ignored', '0 passed; 1 failed; 1 ignored')].each do |changed|
        rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(segment, changed)) }
      end
    end
    rejects('mutation oracle is incomplete') do
      Gate.validate_beluga_core_mutations(core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(27)))
    end
    [
      'BelugaCore C phone operation ABI PASS: exact layouts, original ordering, immutable proof and honest pause outcomes',
      'BelugaCore Swift phone operation import/link PASS: exact layouts, original ordering, immutable proof and honest pause outcomes'
    ].each do |marker|
      assert_includes Gate::BELUGA_CORE_RUNTIME_MARKERS, marker
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker + "\n", '')) }
    end
    value = receipt
    without_phone = @core_methods - tests
    path = File.join(@evidence, 'beluga-core-discovery.log')
    File.write(path, without_phone.map { |method| method + ': test' }.join("\n"))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-discovery' }['sha256'] = Gate.sha(path)
    value['coverage']['beluga_core'] = without_phone
    result = File.join(@evidence, 'beluga-core-tests.log')
    File.write(result, rust_log(without_phone))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-tests' }['sha256'] = Gate.sha(result)
    rejects('missing critical Beluga core') { verify(value) }
    value = receipt
    path = File.join(@evidence, 'beluga-core-mutations.log')
    File.write(path, core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(27)))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-mutations' }['sha256'] = Gate.sha(path)
    rejects('mutation oracle is incomplete') { verify(value) }
    rejects('result footer disagrees') do
      Gate.validate_rust(rust_log(@core_methods).sub("#{@core_methods.length} passed", '44 passed'), @core_methods)
    end
  end

  def test_beluga_core_invitation_source_tests_link_smokes_and_mutants_are_mandatory
    tests = %w[
      initial_is_canonical_and_owns_nothing
      arm_replaces_optional_callback_and_resets_consumed
      foreign_admission_ignores_phase_before_any_error
      already_consumed_admission_ignores_invalid_phase
      matched_admission_rejects_nonrecoverable_native_phases
      nil_admission_callback_still_consumes_after_accepted_issued
      callback_preparation_never_consumes_before_native_success
      thrown_admission_callback_remains_armed_retryable
      successful_admission_is_consumed_once
      active_completion_does_not_require_admission
      idle_and_foreign_completion_ignore_phase
      matched_completion_checks_active_only_after_owner_guard
      thrown_completion_preserves_every_owned_field
      successful_completion_clears_owner_callbacks_and_consumed
      cancellation_is_exact_and_rearm_cannot_be_cancelled_by_foreign_owner
      stale_callback_ack_rejects_same_flags_rearm_native_owner_mismatch
      copied_states_are_independent_and_do_not_share_consumption
      malformed_inputs_never_invite_callback_or_clear_existing_owner
      forged_callback_ack_without_an_eligible_prepared_shape_is_invalid
      exact_raw_layout_is_copy_only_and_has_no_native_pointer
      all_reachable_original_states_and_events_match_independent_flat_reference
      seeded_original_trace_with_rearm_cancellation_and_value_copies_matches
    ]
    assert_equal 22, tests.length
    assert_equal 139, Gate::BELUGA_CORE_PINNED.length
    assert_equal Gate::BELUGA_CORE_PINNED.length, Gate::BELUGA_CORE_PINNED.uniq.length
    assert_equal tests, Gate::BELUGA_CORE_PINNED.first(98).last(tests.length)
    tests.each do |id|
      omitted = @core_methods - [id]
      rejects('missing critical Beluga core') { Gate.beluga_core_inventory(omitted.map { |method| method + ': test' }.join("\n")) }
      rejects('missing, duplicate') { Gate.validate_rust(rust_log(omitted), @core_methods) }
      rejects('ignored') { Gate.validate_rust(rust_log(@core_methods).sub("test #{id} ... ok", "test #{id} ... ignored"), @core_methods) }
    end
    %w[src/invitation_acceptance.rs tests/invitation_acceptance.rs].each do |relative|
      assert_includes Gate::BELUGA_CORE_SOURCE_FILES, relative
      path = File.join(core_crate, relative)
      original = File.binread(path)
      File.unlink(path)
      refresh_core_source_manifest
      refresh_core_artifact_manifest
      rejects('required source files are missing or unbound') { Gate.validate_beluga_core_artifacts(@root) }
      File.binwrite(path, original)
      refresh_core_source_manifest
      refresh_core_artifact_manifest
    end
    mutants = {
      'invitation-phase-before-owner-and-consumed' => 'foreign_admission_ignores_phase_before_any_error',
      'invitation-nil-admission-not-consumed' => 'nil_admission_callback_still_consumes_after_accepted_issued',
      'invitation-prepared-state-committed-prematurely' => 'callback_preparation_never_consumes_before_native_success',
      'invitation-thrown-callback-consumes' => 'thrown_admission_callback_remains_armed_retryable',
      'invitation-completion-requires-admission' => 'active_completion_does_not_require_admission',
      'invitation-arm-keeps-consumed' => 'arm_replaces_optional_callback_and_resets_consumed',
      'invitation-foreign-cancellation-clears-owner' => 'cancellation_is_exact_and_rearm_cannot_be_cancelled_by_foreign_owner',
      'invitation-native-prepared-owner-ignored' => 'stale_callback_ack_rejects_same_flags_rearm_native_owner_mismatch',
      'invitation-success-callback-not-committed' => 'successful_completion_clears_owner_callbacks_and_consumed'
    }
    assert_equal 77, Gate::BELUGA_CORE_MUTANTS.length
    assert_equal mutants.to_a, Gate::BELUGA_CORE_MUTANT_TESTS.to_a.first(42).last(mutants.length)
    assert_nil Gate.validate_beluga_core_mutations(core_mutations_log)
    mutants.each do |name, test|
      assert_includes tests, test
      marker = "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, '')) }
      rejects('mutation oracle is incomplete') do
        Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, marker.sub('assertion-failed', 'compile-failed')))
      end
      segment = core_mutations_log([name]).sub("BELUGA_CORE_MUTATIONS_PASS cases=1\n", '')
      [segment.sub("test #{test} ... FAILED", "test unrelated_assertion ... FAILED"),
       segment.sub("test #{test} ... FAILED", "test #{test} ... ignored"),
       segment.sub('0 passed; 1 failed; 0 ignored', '0 passed; 1 failed; 1 ignored')].each do |changed|
        rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(segment, changed)) }
      end
    end
    rejects('mutation oracle is incomplete') do
      Gate.validate_beluga_core_mutations(core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(33)))
    end
    [
      'BelugaCore C invitation acceptance ABI PASS: exact layouts, original guard order and one-use callback outcomes',
      'BelugaCore Swift invitation acceptance import/link PASS: exact layouts, original guard order and one-use callback outcomes'
    ].each do |marker|
      assert_includes Gate::BELUGA_CORE_RUNTIME_MARKERS, marker
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker + "\n", '')) }
    end
    value = receipt
    without_invitation = @core_methods - tests
    path = File.join(@evidence, 'beluga-core-discovery.log')
    File.write(path, without_invitation.map { |method| method + ': test' }.join("\n"))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-discovery' }['sha256'] = Gate.sha(path)
    value['coverage']['beluga_core'] = without_invitation
    result = File.join(@evidence, 'beluga-core-tests.log')
    File.write(result, rust_log(without_invitation))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-tests' }['sha256'] = Gate.sha(result)
    rejects('missing critical Beluga core') { verify(value) }
    value = receipt
    path = File.join(@evidence, 'beluga-core-mutations.log')
    File.write(path, core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(33)))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-mutations' }['sha256'] = Gate.sha(path)
    rejects('mutation oracle is incomplete') { verify(value) }
    rejects('result footer disagrees') do
      Gate.validate_rust(rust_log(@core_methods).sub("#{@core_methods.length} passed", '76 passed'), @core_methods)
    end
  end

  def test_beluga_core_replay_source_tests_link_smokes_and_mutants_are_mandatory
    tests = %w[
      zero_is_valid_then_duplicate_is_unchanged
      first_maximum_sequence_is_valid_without_allocation
      age_63_is_admitted_and_age_64_rejects_without_change
      advance_63_retains_only_in_window_history
      advance_64_does_not_shift_by_64_and_retires_history
      advance_above_window_remains_one_bit
      maximum_adjacent_arithmetic_never_wraps
      reordered_packets_accumulate_without_erasing_seen_bits
      value_copies_are_independent_and_reset_is_a_fresh_value
      bounded_event_traces_match_frozen_original_at_every_step
      all_boundary_sequence_pairs_match_reference
      malformed_raw_state_is_unchanged_and_never_accepted
      unknown_abi_rejects_without_canonicalizing_or_resetting
      copied_scalar_layout_is_24_and_32_bytes
      canonical_looking_accepted_duplicate_is_rejected_by_boundary
      canonical_looking_history_clearing_accepted_output_is_rejected
      output_for_different_input_cannot_authorize_current_packet
      rejected_outputs_cannot_mutate_history_or_change_error_class
      unknown_disposition_and_reserved_output_are_never_committed
      initial_output_must_not_invent_populated_or_stale_owner_history
      scalar_call_order_model_opens_first_but_burns_before_post_decode_semantic_validation
    ]
    mutants = {
      'replay-zero-clamped' => 'bounded_event_traces_match_frozen_original_at_every_step',
      'replay-maximum-clamped' => 'bounded_event_traces_match_frozen_original_at_every_step',
      'replay-age63-refused' => 'bounded_event_traces_match_frozen_original_at_every_step',
      'replay-advance63-clears-history' => 'bounded_event_traces_match_frozen_original_at_every_step',
      'replay-duplicate-bit-ignored' => 'bounded_event_traces_match_frozen_original_at_every_step',
      'replay-short-advance-clears-history' => 'bounded_event_traces_match_frozen_original_at_every_step',
      'replay-reorder-clears-history' => 'bounded_event_traces_match_frozen_original_at_every_step',
      'replay-unknown-abi-resets-state' => 'unknown_abi_rejects_without_canonicalizing_or_resetting',
      'replay-malformed-state-resets-history' => 'malformed_raw_state_is_unchanged_and_never_accepted',
      'replay-populated-bit-zero-ignored' => 'malformed_raw_state_is_unchanged_and_never_accepted',
      'replay-impossible-past-bits-ignored' => 'malformed_raw_state_is_unchanged_and_never_accepted'
    }
    assert_equal 21, tests.length
    assert_equal 139, Gate::BELUGA_CORE_PINNED.length
    assert_equal tests, Gate::BELUGA_CORE_PINNED[98, 21]
    assert_equal 77, Gate::BELUGA_CORE_MUTANTS.length
    assert_equal mutants.to_a, Gate::BELUGA_CORE_MUTANT_TESTS.to_a[42, 11]
    assert_equal 32, Gate::BELUGA_CORE_SOURCE_FILES.length
    assert_equal 18, Gate::BELUGA_CORE_RUNTIME_MARKERS.length
    tests.each do |id|
      omitted = @core_methods - [id]
      rejects('missing critical Beluga core') do
        Gate.beluga_core_inventory(omitted.map { |method| method + ': test' }.join("\n"))
      end
      rejects('missing, duplicate') { Gate.validate_rust(rust_log(omitted), @core_methods) }
      rejects('ignored') do
        Gate.validate_rust(rust_log(@core_methods).sub("test #{id} ... ok", "test #{id} ... ignored"), @core_methods)
      end
    end
    %w[src/replay_policy.rs tests/replay_policy.rs].each do |relative|
      assert_includes Gate::BELUGA_CORE_SOURCE_FILES, relative
      path = File.join(core_crate, relative)
      original = File.binread(path)
      File.unlink(path)
      refresh_core_source_manifest
      refresh_core_artifact_manifest
      rejects('required source files are missing or unbound') { Gate.validate_beluga_core_artifacts(@root) }
      File.binwrite(path, original)
      refresh_core_source_manifest
      refresh_core_artifact_manifest
    end
    assert_nil Gate.validate_beluga_core_mutations(core_mutations_log)
    mutants.each do |name, test|
      assert_includes tests, test
      marker = "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, '')) }
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, marker * 2)) }
      segment = core_mutations_log([name]).sub("BELUGA_CORE_MUTATIONS_PASS cases=1\n", '')
      equality = 'assertion ' + 96.chr + 'left == right' + 96.chr + ' failed'
      compiled = '    Finished ' + 96.chr + 'test' + 96.chr + " profile [unoptimized + debuginfo] target(s) in 0.01s\n"
      [segment.sub("test #{test} ... FAILED", "test unrelated_assertion ... FAILED"),
       segment.sub("test #{test} ... FAILED", "test #{test} ... ignored"),
       segment.sub('0 passed; 1 failed; 0 ignored', '0 passed; 1 failed; 1 ignored'),
       segment.sub(equality, 'assertion failed: unrelated predicate'),
       segment.sub(compiled, '')].each do |changed|
        rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(segment, changed)) }
      end
    end
    rejects('mutation oracle is incomplete') do
      Gate.validate_beluga_core_mutations(core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(42)))
    end
    markers = [
      'BelugaCore C signaling replay ABI PASS: exact layouts, zero/MAX, 63/64 window and unchanged rejection',
      'BelugaCore Swift signaling replay import/link PASS: exact layouts, zero/MAX, 63/64 window and unchanged rejection'
    ]
    assert_equal markers, [Gate::BELUGA_CORE_RUNTIME_MARKERS[6], Gate::BELUGA_CORE_RUNTIME_MARKERS[15]]
    markers.each do |marker|
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker + "\n", '')) }
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker + "\n", (marker + "\n") * 2)) }
    end
    assert_nil Gate.validate_beluga_core_link(core_link_log)
    swapped = core_link_log.sub(markers[0], 'TEMP_REPLAY_MARKER').sub(markers[1], markers[0]).sub('TEMP_REPLAY_MARKER', markers[1])
    rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(swapped) }
    value = receipt
    without_replay = @core_methods - tests
    path = File.join(@evidence, 'beluga-core-discovery.log')
    File.write(path, without_replay.map { |method| method + ': test' }.join("\n"))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-discovery' }['sha256'] = Gate.sha(path)
    value['coverage']['beluga_core'] = without_replay
    result = File.join(@evidence, 'beluga-core-tests.log')
    File.write(result, rust_log(without_replay))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-tests' }['sha256'] = Gate.sha(result)
    rejects('missing critical Beluga core') { verify(value) }
    value = receipt
    path = File.join(@evidence, 'beluga-core-mutations.log')
    File.write(path, core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(42)))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-mutations' }['sha256'] = Gate.sha(path)
    rejects('mutation oracle is incomplete') { verify(value) }
  end

  # Parser fixtures only: these methods do not execute Rust or native catalog effects.
  def test_beluga_core_catalog_checkpoint_source_and_named_cases_are_mandatory
    tests = %w[
      checkpoint_initial_and_copied_layout_are_exact
      checkpoint_all_valid_states_and_boolean_facts_match_original
      checkpoint_bounded_committed_and_failed_effect_traces_match_original
      checkpoint_revocation_is_terminal_without_erasing_binding
      checkpoint_readback_ignores_revocation_and_owner_but_requires_snapshot
      checkpoint_rejected_input_preserves_exact_state
      checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed
      checkpoint_raw_value_copies_do_not_share_mutation
    ]
    assert_equal 8, tests.length
    assert_equal 139, Gate::BELUGA_CORE_PINNED.length
    assert_equal Gate::BELUGA_CORE_PINNED.length, Gate::BELUGA_CORE_PINNED.uniq.length
    assert_equal tests, Gate::BELUGA_CORE_PINNED[119, 8]
    assert_equal 32, Gate::BELUGA_CORE_SOURCE_FILES.length
    assert_equal 16, Gate::BELUGA_CORE_ARTIFACT_FILES.length
    assert_equal 42, Gate::PHASES.length
    assert_equal @core_methods, Gate.beluga_core_inventory(@core_methods.map { |id| id + ': test' }.join("\n"))
    tests.each do |id|
      omitted = @core_methods - [id]
      rejects('missing critical Beluga core') { Gate.beluga_core_inventory(omitted.map { |method| method + ': test' }.join("\n")) }
      renamed = @core_methods.map { |method| method == id ? id + '_unrelated' : method }
      rejects('missing critical Beluga core') { Gate.beluga_core_inventory(renamed.map { |method| method + ': test' }.join("\n")) }
      rejects('duplicate Beluga core') { Gate.beluga_core_inventory((@core_methods + [id]).map { |method| method + ': test' }.join("\n")) }
      rejects('missing, duplicate') { Gate.validate_rust(rust_log(omitted), @core_methods) }
      rejects('missing, duplicate') { Gate.validate_rust(rust_log(@core_methods + [id]), @core_methods) }
      ['FAILED', 'ignored'].each do |status|
        rejects('failed or was ignored') { Gate.validate_rust(rust_log(@core_methods).sub("test #{id} ... ok", "test #{id} ... #{status}"), @core_methods) }
      end
      value = receipt
      discovery = File.join(@evidence, 'beluga-core-discovery.log')
      File.write(discovery, omitted.map { |method| method + ': test' }.join("\n"))
      value['phases'].find { |phase| phase['name'] == 'beluga-core-discovery' }['sha256'] = Gate.sha(discovery)
      result = File.join(@evidence, 'beluga-core-tests.log')
      File.write(result, rust_log(omitted))
      value['phases'].find { |phase| phase['name'] == 'beluga-core-tests' }['sha256'] = Gate.sha(result)
      value['coverage']['beluga_core'] = omitted
      rejects('missing critical Beluga core') { verify(value) }
    end
    %w[src/pairing_catalog_checkpoint.rs tests/pairing_catalog_checkpoint.rs].each do |relative|
      assert_includes Gate::BELUGA_CORE_SOURCE_FILES, relative
      path = File.join(core_crate, relative)
      original = File.binread(path)
      begin
        File.write(path, original + "\nchanged source without refreshed manifest\n")
        rejects('checksum differs') { Gate.validate_beluga_core_artifacts(@root) }
        File.unlink(path)
        refresh_core_source_manifest
        refresh_core_artifact_manifest
        rejects('required source files are missing or unbound') { Gate.validate_beluga_core_artifacts(@root) }
      ensure
        File.binwrite(path, original)
        refresh_core_source_manifest
        refresh_core_artifact_manifest
      end
    end
  end

  def test_beluga_core_catalog_checkpoint_link_contract_cannot_be_borrowed
    markers = [
      'BelugaCore C catalog checkpoint ABI PASS: exact layouts, candidate custody, terminal revoke and full readback',
      'BelugaCore Swift catalog checkpoint import/link PASS: exact layouts, candidate custody, terminal revoke and full readback'
    ]
    assert_equal 18, Gate::BELUGA_CORE_RUNTIME_MARKERS.length
    assert_equal markers, [Gate::BELUGA_CORE_RUNTIME_MARKERS[7], Gate::BELUGA_CORE_RUNTIME_MARKERS[16]]
    assert_nil Gate.validate_beluga_core_link(core_link_log)
    markers.each do |marker|
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker + "\n", '')) }
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker + "\n", (marker + "\n") * 2)) }
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker, marker + ' unverified')) }
      value = receipt
      path = File.join(@evidence, 'beluga-core-link.log')
      File.write(path, core_link_log.sub(marker + "\n", ''))
      value['phases'].find { |phase| phase['name'] == 'beluga-core-link' }['sha256'] = Gate.sha(path)
      rejects('link oracle is incomplete') { verify(value) }
    end
    swapped = core_link_log.sub(markers[0], 'TEMP_CHECKPOINT_MARKER').sub(markers[1], markers[0]).sub('TEMP_CHECKPOINT_MARKER', markers[1])
    rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(swapped) }
  end

  def test_beluga_core_catalog_checkpoint_each_compiled_assertion_mutant_is_mandatory
    mutants = {
      'checkpoint-revoked-add-admitted' => 'checkpoint_revocation_is_terminal_without_erasing_binding',
      'checkpoint-add-owner-bypassed' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
      'checkpoint-update-owner-bypassed' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
      'checkpoint-second-add-admitted' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
      'checkpoint-update-tuple-bypassed' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
      'checkpoint-readback-snapshot-bypassed' => 'checkpoint_readback_ignores_revocation_and_owner_but_requires_snapshot',
      'checkpoint-revoke-erases-binding' => 'checkpoint_revocation_is_terminal_without_erasing_binding',
      'checkpoint-unknown-opcode-admitted' => 'checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed',
      'checkpoint-unknown-flags-admitted' => 'checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed',
      'checkpoint-unknown-abi-admitted' => 'checkpoint_unknown_abi_opcode_flags_and_booleans_fail_closed',
      'checkpoint-unbound-update-admitted' => 'checkpoint_all_valid_states_and_boolean_facts_match_original',
      'checkpoint-revoked-readback-denied' => 'checkpoint_readback_ignores_revocation_and_owner_but_requires_snapshot'
    }
    assert_equal 12, mutants.length
    assert_equal 77, Gate::BELUGA_CORE_MUTANTS.length
    assert_equal mutants.to_a, Gate::BELUGA_CORE_MUTANT_TESTS.to_a[53, 12]
    assert_nil Gate.validate_beluga_core_mutations(core_mutations_log)
    mutants.each do |name, test|
      assert_includes Gate::BELUGA_CORE_PINNED[119, 8], test
      marker = "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, '')) }
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, marker * 2)) }
      segment = core_mutations_log([name]).sub("BELUGA_CORE_MUTATIONS_PASS cases=1\n", '')
      equality = 'assertion ' + 96.chr + 'left == right' + 96.chr + ' failed'
      compiled = '    Finished ' + 96.chr + 'test' + 96.chr + " profile [unoptimized + debuginfo] target(s) in 0.01s\n"
      [
        segment.sub("test #{test} ... FAILED", "test unrelated_assertion ... FAILED"),
        segment.sub("test #{test} ... FAILED", "test #{test} ... ignored"),
        segment.sub("thread '#{test}'", "thread 'unrelated_assertion'"),
        segment.sub('0 passed; 1 failed; 0 ignored', '0 passed; 1 failed; 1 ignored'),
        segment.sub(equality, 'assertion failed: unrelated predicate'),
        segment.sub(compiled, ''),
        segment + "error: could not compile mutation fixture\n"
      ].each do |changed|
        rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(segment, changed)) }
      end
    end
    rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(53))) }
    value = receipt
    path = File.join(@evidence, 'beluga-core-mutations.log')
    File.write(path, core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(53)))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-mutations' }['sha256'] = Gate.sha(path)
    rejects('mutation oracle is incomplete') { verify(value) }
  end

  def catalog_checkpoint_native_pins
    klass = 'CaptureServerTests.BelugaRustPairingCatalogCheckpointTests'
    %w[
      testRevokedCheckpointNeverCallsOwnerOrCatalog
      testInvalidProcessOwnerRefusesAllCatalogAccess
      testCheckpointAddsExactlyOnceEvenForDifferentValidPhone
      testDeviceUUIDMismatchRefusesAllCatalogAccess
      testPairUUIDMismatchRefusesAllCatalogAccess
      testCommitUUIDMismatchRefusesAllCatalogAccess
      testThrowingAddAndUpdatePreserveActualCheckpointState
      testRevocationRetainsExactPairForInterruptedReadback
      testEqualRevisionDifferentSnapshotCannotPassReadback
      testMalformedAllowedCandidateCannotAuthorizeNativeWrite
      testReadbackAfterRevokeAndOwnerLossStillReturnsExactPair
      testReadbackLoadErrorPrecedesSnapshotPolicyOrBridgeFault
      testWriteThenThrowDoesNotInventRollbackOrBindingSuccess
      testNativeAliasesShareRevocationWithoutAffectingAnotherAttempt
      testCatalogGenerationRevisionRecordAndLegacyReceiptAllFenceReadback
      testMalformedRevokeIsStickyWithoutErasingKnownSnapshotOrBinding
      testMalformedInitialCannotInvokeOwnerOrStore
      testActualCopiedBoundaryAndLayoutsPreserveAllValidCases
    ].map { |name| klass + '/' + name }
  end

  def test_native_catalog_checkpoint_class_and_every_critical_case_are_mandatory
    klass = 'CaptureServerTests.BelugaRustPairingCatalogCheckpointTests'
    pins = catalog_checkpoint_native_pins
    assert_equal 18, pins.length
    assert_includes Gate::MAC_CLASSES, klass
    assert_equal pins, Gate::MAC_PINNED.select { |id| id.start_with?(klass + '/') }
    assert_equal @mac_methods, Gate.mac_inventory(@mac_methods.join("\n"))
    rejects('missing Mac test class') { Gate.mac_inventory(@mac_methods.reject { |id| id.start_with?(klass + '/') }.join("\n")) }
    pins.each do |id|
      rejects('missing critical Mac test') { Gate.mac_inventory((@mac_methods - [id]).join("\n")) }
      rejects('duplicate Mac discovery') { Gate.mac_inventory((@mac_methods + [id]).join("\n")) }
    end
    assert_includes @mac_methods, klass + '/testFixture'
    value = receipt
    argv = Gate.commands(@root, @evidence, value['invocation'], @tools, SIMULATOR, @mac_methods, @handoff_methods).fetch('mac-tests')
    filter = Regexp.new(argv.fetch(argv.index('--filter') + 1))
    pins.each { |id| assert_match filter, id }
    refute_match filter, klass + '/testUnreviewedMissingDiscovery'
    refute_match filter, 'CaptureServerTests.OtherClass/' + pins.first.split('/').last
  end

  def test_native_catalog_checkpoint_results_and_rehashed_coverage_cannot_be_borrowed
    klass = 'CaptureServerTests.BelugaRustPairingCatalogCheckpointTests'
    pins = catalog_checkpoint_native_pins
    discovered = @mac_methods.select { |id| id.start_with?(klass + '/') }
    # Future discovered methods in the enrolled class must execute, not only pins.
    assert_includes discovered, klass + '/testFixture'
    assert_equal @mac_methods, Gate.validate_mac_log(mac_log, @mac_methods)
    discovered.each do |id|
      rejects('missing Mac result') { Gate.validate_mac_log(mac_log(@mac_methods - [id]), @mac_methods) }
      rejects('duplicate') { Gate.validate_mac_log(mac_log(@mac_methods + [id]), @mac_methods) }
      ruby_class, method = id.split('/')
      passed = "Test Case '-[#{ruby_class} #{method}]' passed (0.001 seconds)."
      ['failed', 'skipped'].each do |status|
        rejects('failed, skipped') { Gate.validate_mac_log(mac_log.sub(passed, passed.sub('passed', status)), @mac_methods) }
      end
    end
    rejects('footer has missing') do
      Gate.validate_mac_log(mac_log.sub("Executed #{@mac_methods.length} tests", "Executed #{@mac_methods.length - 1} tests"), @mac_methods)
    end
    pins.each do |id|
      value = receipt
      omitted = @mac_methods - [id]
      discovery = File.join(@evidence, 'mac-discovery.log')
      File.write(discovery, (omitted + @shared_methods + @shared_replay_methods.values.flatten + @shared_reconnect_counter_methods + @handoff_methods).join("\n"))
      value['phases'].find { |phase| phase['name'] == 'mac-discovery' }['sha256'] = Gate.sha(discovery)
      result = File.join(@evidence, 'mac-tests.log')
      File.write(result, mac_log(omitted))
      value['phases'].find { |phase| phase['name'] == 'mac-tests' }['sha256'] = Gate.sha(result)
      value['coverage']['mac'] = omitted
      rejects('missing critical Mac test') { verify(value) }
    end
  end

  def test_shared_replay_source_discovery_and_every_critical_case_are_exact
    assert_equal [19, 3, 6], Gate::SHARED_REPLAY_PINNED.values.map(&:length)
    assert_equal @shared_replay_methods, Gate.shared_replay_source_inventory(@root)
    discovery = (@mac_methods + @shared_methods + @shared_replay_methods.values.flatten).join("\n")
    assert_equal @shared_replay_methods, Gate.shared_replay_inventory(@root, discovery)
    Gate::SHARED_REPLAY_FILES.each do |suite, relative|
      methods = @shared_replay_methods.fetch(suite)
      methods.each do |id|
        rejects('shared replay discovery differs') { Gate.shared_replay_inventory(@root, discovery.lines.reject { |line| line.strip == id }.join) }
        rejects('shared replay discovery differs') { Gate.shared_replay_inventory(@root, discovery + "\n" + id) }
      end
      rejects('shared replay discovery differs') { Gate.shared_replay_inventory(@root, discovery + "\n" + suite + '/malformed') }
      path = File.join(@root, relative)
      original = File.binread(path)
      first = methods.first.split('/').last.delete_suffix('()')
      File.write(path, original.sub("@Test func #{first}() {}", ''))
      rejects('source inventory is incomplete') { Gate.shared_replay_source_inventory(@root) }
      File.write(path, original + "\n@Test func #{first}() {}\n")
      rejects('source inventory is incomplete') { Gate.shared_replay_source_inventory(@root) }
      File.write(path, original + "\n@Test func additionalUnpinnedReplayFixture() {}\n")
      rejects('shared replay discovery differs') { Gate.shared_replay_inventory(@root, discovery) }
      File.binwrite(path, original + "\xFF".b)
      rejects('not valid UTF-8') { Gate.shared_replay_source_inventory(@root) }
      File.binwrite(path, original)
    end
    rejects('not valid UTF-8') { Gate.shared_replay_inventory(@root, discovery.b + "\xFF".b) }
  end

  def test_shared_replay_named_results_reject_missing_duplicate_skip_failure_and_wrong_suite
    @shared_replay_methods.each do |suite, methods|
      log = replay_log(suite, methods)
      assert_equal methods, Gate.validate_shared_replay(log, methods, suite)
      methods.each do |id|
        name = id.split('/').last
        start = "◇ Test #{name} started.\n"
        pass = "✔ Test #{name} passed after 0.001 seconds.\n"
        rejects('cases are missing') { Gate.validate_shared_replay(log.sub(start, '').sub(pass, ''), methods, suite) }
        rejects('start is unexpected or duplicated') { Gate.validate_shared_replay(log.sub(start, start * 2), methods, suite) }
        rejects('pass is unexpected, duplicated') { Gate.validate_shared_replay(log.sub(pass, pass * 2), methods, suite) }
        rejects('matching start') { Gate.validate_shared_replay(log.sub(start, pass + start), methods, suite) }
        rejects('malformed, failed, skipped') { Gate.validate_shared_replay(log.sub(pass, pass.sub('✔', '✘')), methods, suite) }
        rejects('malformed, failed, skipped') { Gate.validate_shared_replay(log.sub(pass, "↷ Test #{name} skipped.\n"), methods, suite) }
      end
      wrong = log.sub("◇ Suite #{suite.split('.').last} started.", '◇ Suite OtherTests started.')
      rejects('malformed, failed, skipped') { Gate.validate_shared_replay(wrong, methods, suite) }
      rejects('malformed, failed, skipped') { Gate.validate_shared_replay(log + "◇ Suite OtherTests started.\n", methods, suite) }
      rejects('not valid UTF-8') { Gate.validate_shared_replay(log.b + "\xFF".b, methods, suite) }
    end
    rejects('unreviewed suite') { Gate.validate_shared_replay('', [], 'RemoteSessionCoreTests.OtherTests') }
  end

  def test_shared_replay_suite_boundaries_counts_order_and_concurrency_are_exact
    @shared_replay_methods.each do |suite, methods|
      name = suite.split('.').last
      log = replay_log(suite, methods)
      start = "◇ Suite #{name} started.\n"
      pass = "✔ Suite #{name} passed after 0.003 seconds.\n"
      footer = log.lines.last
      [log.sub(start, ''), log.sub(start, start * 2), log.sub(pass, ''),
       log.sub(pass, pass * 2), log.sub('◇ Test run started.', ''),
       log + "◇ Test run started.\n", log.sub(footer, ''), log + footer,
       footer + log.sub(footer, ''), log.sub("#{methods.length} tests in 1 suite", '0 tests in 1 suite'),
       log.sub('tests in 1 suite', 'tests in 2 suite')].each do |bad|
        rejects('suite/run footer') { Gate.validate_shared_replay(bad, methods, suite) }
      end
      first = methods.first.split('/').last
      case_start = "◇ Test #{first} started.\n"
      case_pass = "✔ Test #{first} passed after 0.001 seconds.\n"
      rejects('outside the exact suite') { Gate.validate_shared_replay(case_start + log.sub(case_start, ''), methods, suite) }
      rejects('outside the exact suite') { Gate.validate_shared_replay(log.sub(case_pass, '') + case_pass, methods, suite) }
      rejects('bounds') { Gate.validate_shared_replay('x' * (2 * 1024 * 1024 + 1), methods, suite) }
      lines = log.lines
      lines.delete(case_pass)
      lines.insert(lines.index(case_start) + 1, case_pass)
      assert_equal methods, Gate.validate_shared_replay(lines.join, methods, suite)
    end
  end

  def test_shared_replay_phases_and_coverage_cannot_be_removed_or_rehashed
    assert_equal 42, Gate::PHASES.length
    assert_equal Gate::SHARED_REPLAY_PHASES.keys,
                 Gate::PHASES[Gate::PHASES.index('shared-signaling-tests') + 1, 3]
    assert_equal 27, Gate::SHARED_SIGNALING_PINNED.length
    assert_equal @shared_methods, Gate.shared_signaling_inventory((@shared_methods + @shared_replay_methods.values.flatten).join("\n"))
    value = receipt
    value['coverage'].delete('shared_replay')
    rejects('coverage has an unrecognized field set') { verify(value) }
    value = receipt
    value['coverage']['shared_replay'] = { 'RemoteSessionCoreTests.BelugaRustSignalingReplayTests' => @shared_methods }
    rejects('shared replay coverage differs') { verify(value) }
    Gate::SHARED_REPLAY_PHASES.each do |phase, suite|
      value = receipt
      value['phases'].reject! { |entry| entry['name'] == phase }
      rejects('absent, duplicate') { verify(value) }
      %w[--skip-build --disable-xctest].each do |option|
        value = receipt
        value['phases'].find { |entry| entry['name'] == phase }['argv'].delete(option)
        rejects('canonical offline invocation') { verify(value) }
      end
      value = receipt
      argv = value['phases'].find { |entry| entry['name'] == phase }['argv']
      argv[argv.index('--filter') + 1] = suite
      rejects('canonical offline invocation') { verify(value) }
      methods = @shared_replay_methods.fetch(suite)
      value = receipt
      path = File.join(@evidence, phase + '.log')
      File.write(path, replay_log(suite, methods).lines.reject { |line| line.include?('Test ' + methods.first.split('/').last + ' ') }.join)
      value['phases'].find { |entry| entry['name'] == phase }['sha256'] = Gate.sha(path)
      rejects('cases are missing') { verify(value) }
      value = receipt
      id = methods.first
      discovery = File.join(@evidence, 'mac-discovery.log')
      File.write(discovery, File.readlines(discovery).reject { |line| line.strip == id }.join)
      value['phases'].find { |entry| entry['name'] == 'mac-discovery' }['sha256'] = Gate.sha(discovery)
      result = File.join(@evidence, phase + '.log')
      File.write(result, replay_log(suite, methods - [id]))
      value['phases'].find { |entry| entry['name'] == phase }['sha256'] = Gate.sha(result)
      value['coverage']['shared_replay'][suite] = methods - [id]
      rejects('shared replay discovery differs') { verify(value) }
    end
  end

  def test_shared_replay_observer_execution_cannot_be_borrowed_from_other_suites
    phase = 'shared-replay-durable-tests'
    suite = Gate::SHARED_REPLAY_PHASES.fetch(phase)
    expected = @shared_replay_methods.fetch(suite)
    Gate::SHARED_REPLAY_PHASES.reject { |name, _| name == phase }.each do |_, foreign|
      borrowed = replay_log(foreign, @shared_replay_methods.fetch(foreign))
      rejects('malformed, failed, skipped') { Gate.validate_shared_replay(borrowed, expected, suite) }
      value = receipt
      path = File.join(@evidence, phase + '.log')
      File.write(path, borrowed)
      value['phases'].find { |entry| entry['name'] == phase }['sha256'] = Gate.sha(path)
      rejects('malformed, failed, skipped') { verify(value) }
    end
  end

  def test_beluga_core_reconnect_counters_source_and_named_cases_are_mandatory
    tests = %w[
      reconnect_copied_layout_and_export_are_exact
      reconnect_all_bounded_numeric_inputs_match_original
      reconnect_outbound_zero_and_maximum_preserve_native_ordering
      reconnect_inbound_strict_newer_includes_authenticated_maximum
      reconnect_opposite_counters_never_change
      reconnect_large_u64_values_never_round_through_float
      reconnect_rejected_events_preserve_exact_snapshot
      reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed
      reconnect_outbound_unused_request_sequence_is_rejected
      reconnect_candidate_is_committed_only_after_modeled_constructor_success
      reconnect_bounded_effect_success_and_failure_traces_match_original
      reconnect_raw_value_copies_remain_independent
    ]
    assert_equal 12, tests.length
    assert_equal 139, Gate::BELUGA_CORE_PINNED.length
    assert_equal Gate::BELUGA_CORE_PINNED.length, Gate::BELUGA_CORE_PINNED.uniq.length
    assert_equal tests, Gate::BELUGA_CORE_PINNED[127, 12]
    assert_equal 32, Gate::BELUGA_CORE_SOURCE_FILES.length
    assert_equal 16, Gate::BELUGA_CORE_ARTIFACT_FILES.length
    assert_equal 42, Gate::PHASES.length
    assert_equal @core_methods, Gate.beluga_core_inventory(@core_methods.map { |id| id + ': test' }.join("\n"))
    tests.each do |id|
      omitted = @core_methods - [id]
      rejects('missing critical Beluga core') { Gate.beluga_core_inventory(omitted.map { |method| method + ': test' }.join("\n")) }
      renamed = @core_methods.map { |method| method == id ? id + '_unrelated' : method }
      rejects('missing critical Beluga core') { Gate.beluga_core_inventory(renamed.map { |method| method + ': test' }.join("\n")) }
      rejects('duplicate Beluga core') { Gate.beluga_core_inventory((@core_methods + [id]).map { |method| method + ': test' }.join("\n")) }
      rejects('missing, duplicate') { Gate.validate_rust(rust_log(omitted), @core_methods) }
      rejects('missing, duplicate') { Gate.validate_rust(rust_log(@core_methods + [id]), @core_methods) }
      ['FAILED', 'ignored'].each do |status|
        rejects('failed or was ignored') { Gate.validate_rust(rust_log(@core_methods).sub("test #{id} ... ok", "test #{id} ... #{status}"), @core_methods) }
      end
      value = receipt
      discovery = File.join(@evidence, 'beluga-core-discovery.log')
      File.write(discovery, omitted.map { |method| method + ': test' }.join("\n"))
      value['phases'].find { |phase| phase['name'] == 'beluga-core-discovery' }['sha256'] = Gate.sha(discovery)
      result = File.join(@evidence, 'beluga-core-tests.log')
      File.write(result, rust_log(omitted))
      value['phases'].find { |phase| phase['name'] == 'beluga-core-tests' }['sha256'] = Gate.sha(result)
      value['coverage']['beluga_core'] = omitted
      rejects('missing critical Beluga core') { verify(value) }
    end
    %w[src/reconnect_counters.rs tests/reconnect_counters.rs].each do |relative|
      assert_includes Gate::BELUGA_CORE_SOURCE_FILES, relative
      path = File.join(core_crate, relative)
      original = File.binread(path)
      begin
        File.write(path, original + "\nchanged source without refreshed manifest\n")
        rejects('checksum differs') { Gate.validate_beluga_core_artifacts(@root) }
        File.unlink(path)
        refresh_core_source_manifest
        refresh_core_artifact_manifest
        rejects('required source files are missing or unbound') { Gate.validate_beluga_core_artifacts(@root) }
      ensure
        File.binwrite(path, original)
        refresh_core_source_manifest
        refresh_core_artifact_manifest
      end
    end
  end

  def test_beluga_core_reconnect_counters_link_contract_cannot_be_borrowed
    markers = [
      'BelugaCore C reconnect counters ABI PASS: exact layouts, zero/MAX, strict admission and unchanged refusal',
      'BelugaCore Swift reconnect counters import/link PASS: exact layouts, zero/MAX, strict admission and unchanged refusal'
    ]
    assert_equal 18, Gate::BELUGA_CORE_RUNTIME_MARKERS.length
    assert_equal markers, [Gate::BELUGA_CORE_RUNTIME_MARKERS[8], Gate::BELUGA_CORE_RUNTIME_MARKERS[17]]
    assert_nil Gate.validate_beluga_core_link(core_link_log)
    markers.each do |marker|
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker + "\n", '')) }
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker + "\n", (marker + "\n") * 2)) }
      rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(core_link_log.sub(marker, marker + ' unverified')) }
      value = receipt
      path = File.join(@evidence, 'beluga-core-link.log')
      File.write(path, core_link_log.sub(marker + "\n", ''))
      value['phases'].find { |phase| phase['name'] == 'beluga-core-link' }['sha256'] = Gate.sha(path)
      rejects('link oracle is incomplete') { verify(value) }
    end
    swapped = core_link_log.sub(markers[0], 'TEMP_RECONNECT_MARKER').sub(markers[1], markers[0]).sub('TEMP_RECONNECT_MARKER', markers[1])
    rejects('link oracle is incomplete') { Gate.validate_beluga_core_link(swapped) }
  end

  def test_beluga_core_reconnect_counters_each_compiled_assertion_mutant_is_mandatory
    mutants = {
      'reconnect-outbound-zero-refused' => 'reconnect_outbound_zero_and_maximum_preserve_native_ordering',
      'reconnect-outbound-maximum-wraps' => 'reconnect_outbound_zero_and_maximum_preserve_native_ordering',
      'reconnect-outbound-increment-removed' => 'reconnect_all_bounded_numeric_inputs_match_original',
      'reconnect-equal-inbound-admitted' => 'reconnect_inbound_strict_newer_includes_authenticated_maximum',
      'reconnect-inbound-highwater-removed' => 'reconnect_inbound_strict_newer_includes_authenticated_maximum',
      'reconnect-outbound-resets-inbound' => 'reconnect_opposite_counters_never_change',
      'reconnect-inbound-resets-outbound' => 'reconnect_opposite_counters_never_change',
      'reconnect-unknown-abi-admitted' => 'reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed',
      'reconnect-state-reserved-ignored' => 'reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed',
      'reconnect-event-reserved-ignored' => 'reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed',
      'reconnect-unknown-opcode-admitted' => 'reconnect_unknown_abi_opcode_and_reserved_fields_fail_closed',
      'reconnect-unused-outbound-sequence-admitted' => 'reconnect_outbound_unused_request_sequence_is_rejected'
    }
    assert_equal 12, mutants.length
    assert_equal 77, Gate::BELUGA_CORE_MUTANTS.length
    assert_equal mutants.to_a, Gate::BELUGA_CORE_MUTANT_TESTS.to_a[65, 12]
    assert_nil Gate.validate_beluga_core_mutations(core_mutations_log)
    mutants.each do |name, test|
      assert_includes Gate::BELUGA_CORE_PINNED[127, 12], test
      marker = "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n"
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, '')) }
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(marker, marker * 2)) }
      segment = core_mutations_log([name]).sub("BELUGA_CORE_MUTATIONS_PASS cases=1\n", '')
      equality = 'assertion ' + 96.chr + 'left == right' + 96.chr + ' failed'
      compiled = '    Finished ' + 96.chr + 'test' + 96.chr + " profile [unoptimized + debuginfo] target(s) in 0.01s\n"
      [
        segment.sub("test #{test} ... FAILED", "test unrelated_assertion ... FAILED"),
        segment.sub("test #{test} ... FAILED", "test #{test} ... ignored"),
        segment.sub("thread '#{test}'", "thread 'unrelated_assertion'"),
        segment.sub('0 passed; 1 failed; 0 ignored', '0 passed; 1 failed; 1 ignored'),
        segment.sub(equality, 'assertion failed: unrelated predicate'),
        segment.sub(compiled, ''),
        segment + "error: could not compile mutation fixture\n"
      ].each do |changed|
        rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log.sub(segment, changed)) }
      end
    end
    rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(65))) }
    value = receipt
    path = File.join(@evidence, 'beluga-core-mutations.log')
    File.write(path, core_mutations_log(Gate::BELUGA_CORE_MUTANTS.first(65)))
    value['phases'].find { |phase| phase['name'] == 'beluga-core-mutations' }['sha256'] = Gate.sha(path)
    rejects('mutation oracle is incomplete') { verify(value) }
  end


  # Source/result fixtures only; the actual Swift Testing suite separately runs
  # the default linked C producer and genuine signed reconnect constructors.
  def test_shared_reconnect_counters_source_discovery_and_every_critical_case_are_exact
    suite = Gate::SHARED_RECONNECT_COUNTER_SUITE
    assert_equal 27, Gate::SHARED_RECONNECT_COUNTER_PINNED.length
    assert_equal @shared_reconnect_counter_methods, Gate.shared_reconnect_counter_source_inventory(@root)
    discovery = (@mac_methods + @shared_methods + @shared_replay_methods.values.flatten + @shared_reconnect_counter_methods).join("\n")
    assert_equal @shared_reconnect_counter_methods, Gate.shared_reconnect_counter_inventory(@root, discovery)
    @shared_reconnect_counter_methods.each do |id|
      rejects('shared reconnect counter discovery differs') do
        Gate.shared_reconnect_counter_inventory(@root, discovery.lines.reject { |line| line.strip == id }.join)
      end
      rejects('shared reconnect counter discovery differs') { Gate.shared_reconnect_counter_inventory(@root, discovery + "\n" + id) }
    end
    [suite + '/malformed', suite + '/unexpectedCounterMethod()', suite + '/wrongArgument(1)',
     suite + '/method()/Unbound.swift:1:1'].each do |id|
      rejects('shared reconnect counter discovery differs') { Gate.shared_reconnect_counter_inventory(@root, discovery + "\n" + id) }
    end
    path = File.join(@root, Gate::SHARED_RECONNECT_COUNTER_FILE)
    original = File.binread(path)
    first = Gate::SHARED_RECONNECT_COUNTER_PINNED.first.split('/').last.delete_suffix('()')
    begin
      File.write(path, original.sub("@Test func #{first}() {}", ''))
      rejects('source inventory is incomplete') { Gate.shared_reconnect_counter_source_inventory(@root) }
      File.write(path, original + "\n@Test func #{first}() {}\n")
      rejects('source inventory is incomplete') { Gate.shared_reconnect_counter_source_inventory(@root) }
      File.write(path, original.sub("@Test func #{first}() {}", "@Test\nfunc #{first}() {}"))
      rejects('source inventory is incomplete') { Gate.shared_reconnect_counter_source_inventory(@root) }
      File.write(path, original.sub("struct #{suite.split('.').last}", 'struct WrongCounterSuite'))
      rejects('source inventory is incomplete') { Gate.shared_reconnect_counter_source_inventory(@root) }
      File.write(path, original + "\n@Test func anotherFutureCounterFixture() {}\n")
      rejects('shared reconnect counter discovery differs') { Gate.shared_reconnect_counter_inventory(@root, discovery) }
      File.binwrite(path, original + "\xFF".b)
      rejects('not valid UTF-8') { Gate.shared_reconnect_counter_source_inventory(@root) }
    ensure
      File.binwrite(path, original)
    end
    rejects('not valid UTF-8') { Gate.shared_reconnect_counter_inventory(@root, discovery.b + "\xFF".b) }
  end

  def test_shared_reconnect_counters_named_results_reject_missing_duplicate_skip_failure_and_wrong_suite
    suite = Gate::SHARED_RECONNECT_COUNTER_SUITE
    methods = @shared_reconnect_counter_methods
    log = replay_log(suite, methods)
    assert_equal methods, Gate.validate_shared_reconnect_counter(log, methods)
    methods.each do |id|
      name = id.split('/').last
      start = "◇ Test #{name} started.\n"
      pass = "✔ Test #{name} passed after 0.001 seconds.\n"
      rejects('cases are missing') { Gate.validate_shared_reconnect_counter(log.sub(start, '').sub(pass, ''), methods) }
      rejects('start is unexpected or duplicated') { Gate.validate_shared_reconnect_counter(log.sub(start, start * 2), methods) }
      rejects('pass is unexpected, duplicated') { Gate.validate_shared_reconnect_counter(log.sub(pass, pass * 2), methods) }
      rejects('matching start') { Gate.validate_shared_reconnect_counter(log.sub(start, pass + start), methods) }
      rejects('malformed, failed, skipped') { Gate.validate_shared_reconnect_counter(log.sub(pass, pass.sub('✔', '✘')), methods) }
      rejects('malformed, failed, skipped') { Gate.validate_shared_reconnect_counter(log.sub(pass, "↷ Test #{name} skipped.\n"), methods) }
    end
    wrong = log.sub("◇ Suite #{suite.split('.').last} started.", '◇ Suite OtherTests started.')
    rejects('malformed, failed, skipped') { Gate.validate_shared_reconnect_counter(wrong, methods) }
    rejects('malformed, failed, skipped') { Gate.validate_shared_reconnect_counter(log + "◇ Suite OtherTests started.\n", methods) }
    rejects('not valid UTF-8') { Gate.validate_shared_reconnect_counter(log.b + "\xFF".b, methods) }
    [[], methods + [methods.first], methods - [Gate::SHARED_RECONNECT_COUNTER_PINNED.first],
     methods.map { |id| id.sub(suite, 'RemoteSessionCoreTests.OtherTests') }].each do |expected|
      rejects('bounds or expected inventory') { Gate.validate_shared_reconnect_counter(log, expected) }
    end
  end

  def test_shared_reconnect_counters_suite_boundaries_counts_order_and_concurrency_are_exact
    methods = @shared_reconnect_counter_methods
    name = Gate::SHARED_RECONNECT_COUNTER_SUITE.split('.').last
    log = replay_log(Gate::SHARED_RECONNECT_COUNTER_SUITE, methods)
    start = "◇ Suite #{name} started.\n"
    pass = "✔ Suite #{name} passed after 0.003 seconds.\n"
    footer = log.lines.last
    [log.sub(start, ''), log.sub(start, start * 2), log.sub(pass, ''),
     log.sub(pass, pass * 2), log.sub('◇ Test run started.', ''),
     log + "◇ Test run started.\n", log.sub(footer, ''), log + footer,
     footer + log.sub(footer, ''), log.sub("#{methods.length} tests in 1 suite", '0 tests in 1 suite'),
     log.sub('tests in 1 suite', 'tests in 2 suite')].each do |bad|
      rejects('suite/run footer') { Gate.validate_shared_reconnect_counter(bad, methods) }
    end
    first = methods.first.split('/').last
    case_start = "◇ Test #{first} started.\n"
    case_pass = "✔ Test #{first} passed after 0.001 seconds.\n"
    rejects('outside the exact suite') { Gate.validate_shared_reconnect_counter(case_start + log.sub(case_start, ''), methods) }
    rejects('outside the exact suite') { Gate.validate_shared_reconnect_counter(log.sub(case_pass, '') + case_pass, methods) }
    rejects('bounds') { Gate.validate_shared_reconnect_counter('x' * (2 * 1024 * 1024 + 1), methods) }
    rejects('line bound') { Gate.validate_shared_reconnect_counter(log + "\n" * 4097, methods) }
    lines = log.lines
    lines.delete(case_pass)
    lines.insert(lines.index(case_start) + 1, case_pass)
    assert_equal methods, Gate.validate_shared_reconnect_counter(lines.join, methods)
  end

  def test_shared_reconnect_counters_phase_and_coverage_cannot_be_removed_or_rehashed
    phase = Gate::SHARED_RECONNECT_COUNTER_PHASE
    suite = Gate::SHARED_RECONNECT_COUNTER_SUITE
    assert_equal 'shared-reconnect-counter-tests', phase
    assert_equal 42, Gate::PHASES.length
    assert_equal phase, Gate::PHASES[Gate::PHASES.index('shared-replay-durable-tests') + 1]
    assert_equal 'shared-handoff-tests', Gate::PHASES[Gate::PHASES.index(phase) + 1]
    assert_equal [19, 3, 6], Gate::SHARED_REPLAY_PINNED.values.map(&:length)
    assert_equal @shared_reconnect_counter_methods, Gate.validate_shared_reconnect_counter(replay_log(suite, @shared_reconnect_counter_methods), @shared_reconnect_counter_methods)
    value = receipt
    value['coverage'].delete('shared_reconnect_counters')
    rejects('coverage has an unrecognized field set') { verify(value) }
    value = receipt
    value['coverage']['shared_reconnect_counters'] = @shared_replay_methods.values.flatten
    rejects('shared reconnect counter coverage differs') { verify(value) }
    value = receipt
    value['phases'].reject! { |entry| entry['name'] == phase }
    rejects('absent, duplicate') { verify(value) }
    value = receipt
    index = value['phases'].index { |entry| entry['name'] == phase }
    value['phases'][index], value['phases'][index + 1] = value['phases'][index + 1], value['phases'][index]
    rejects('absent, duplicate') { verify(value) }
    %w[--skip-build --disable-xctest].each do |option|
      value = receipt
      value['phases'].find { |entry| entry['name'] == phase }['argv'].delete(option)
      rejects('canonical offline invocation') { verify(value) }
    end
    value = receipt
    argv = value['phases'].find { |entry| entry['name'] == phase }['argv']
    argv[argv.index('--filter') + 1] = suite
    rejects('canonical offline invocation') { verify(value) }
    Gate::SHARED_RECONNECT_COUNTER_PINNED.each do |id|
      value = receipt
      path = File.join(@evidence, phase + '.log')
      omitted = @shared_reconnect_counter_methods - [id]
      File.write(path, replay_log(suite, @shared_reconnect_counter_methods).lines.reject { |line| line.include?('Test ' + id.split('/').last + ' ') }.join)
      value['phases'].find { |entry| entry['name'] == phase }['sha256'] = Gate.sha(path)
      rejects('cases are missing') { verify(value) }
      value = receipt
      discovery = File.join(@evidence, 'mac-discovery.log')
      File.write(discovery, File.readlines(discovery).reject { |line| line.strip == id }.join)
      value['phases'].find { |entry| entry['name'] == 'mac-discovery' }['sha256'] = Gate.sha(discovery)
      path = File.join(@evidence, phase + '.log')
      File.write(path, replay_log(suite, omitted))
      value['phases'].find { |entry| entry['name'] == phase }['sha256'] = Gate.sha(path)
      value['coverage']['shared_reconnect_counters'] = omitted
      rejects('shared reconnect counter discovery differs') { verify(value) }
    end
  end

  def test_shared_reconnect_counters_actual_suite_execution_cannot_be_borrowed
    phase = Gate::SHARED_RECONNECT_COUNTER_PHASE
    expected = @shared_reconnect_counter_methods
    Gate::SHARED_REPLAY_PHASES.each do |_, foreign|
      borrowed = replay_log(foreign, @shared_replay_methods.fetch(foreign))
      rejects('malformed, failed, skipped') { Gate.validate_shared_reconnect_counter(borrowed, expected) }
      value = receipt
      path = File.join(@evidence, phase + '.log')
      File.write(path, borrowed)
      value['phases'].find { |entry| entry['name'] == phase }['sha256'] = Gate.sha(path)
      rejects('malformed, failed, skipped') { verify(value) }
    end
    value = receipt
    path = File.join(@evidence, phase + '.log')
    File.write(path, "fixture executor exited successfully\n")
    value['phases'].find { |entry| entry['name'] == phase }['sha256'] = Gate.sha(path)
    rejects('suite/run footer') { verify(value) }
  end

  def test_beluga_core_compiled_mutation_assertions_reject_uncompiled_wrong_case_and_bad_footer
    assert_nil Gate.validate_beluga_core_mutations(core_mutations_log)
    original = core_mutations_log
    first_test = Gate::BELUGA_CORE_MUTANT_TESTS.values.first
    mutations = [
      original.sub(/^\s*Finished `test` profile .*\n/, ''),
      original.sub('Finished `test` profile', 'Checking `test` profile'),
      original.sub('running 1 test', 'running 0 tests'),
      original.sub("test #{first_test} ... FAILED", "test unrelated_assertion ... FAILED"),
      original.sub("test #{first_test} ... FAILED", "test #{first_test} ... ignored"),
      original.sub("thread '#{first_test}'", "thread 'unrelated_assertion'"),
      original.sub(/^thread '[^\n]+\n/, ''),
      original.sub(/^assertion [^\n]+\n/, ''),
      original.sub('assertion `left == right` failed', 'assertion `left != right` failed'),
      original.sub('0 passed; 1 failed; 0 ignored', '1 passed; 0 failed; 0 ignored'),
      original.sub('0 passed; 1 failed; 0 ignored', '0 passed; 2 failed; 0 ignored'),
      original.sub('0 passed; 1 failed; 0 ignored', '0 passed; 1 failed; 1 ignored'),
      original.sub('0 measured;', '1 measured;'),
      original.sub('test result: FAILED.', 'test result: ok.'),
      original.sub(/^test result:[^\n]+\n/, ''),
      original.sub("test #{first_test} ... FAILED\n", "test #{first_test} ... FAILED\n" * 2),
      original.sub("    Finished `test` profile [unoptimized + debuginfo] target(s) in 0.01s\n",
                   "    Finished `test` profile [unoptimized + debuginfo] target(s) in 0.01s\n" * 2),
      original.sub('Behavioral mutation rejected:', "error[E0308]: deliberately uncompiled\nBehavioral mutation rejected:"),
      original.sub('Behavioral mutation rejected:', "could not compile beluga-core\nBehavioral mutation rejected:"),
      original + "test #{first_test} ... FAILED\n",
      original + "test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 6 filtered out; finished in 0.00s\n"
    ]
    mutations.each { |text| rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(text) } }
    # The offer and phone mutations must carry compiled failure proof too, not only
    # the original policy or transaction mutants at the beginning of the log.
    Gate::BELUGA_CORE_MUTANTS.drop(11).each do |name|
      single = core_mutations_log([name]).sub("BELUGA_CORE_MUTATIONS_PASS cases=1\n", '')
      without_compile = single.sub(/^\s*Finished `test` profile .*\n/, '')
      rejects('mutation oracle is incomplete') { Gate.validate_beluga_core_mutations(original.sub(single, without_compile)) }
    end
    value = receipt
    path = File.join(@evidence, 'beluga-core-mutations.log')
    File.write(path, mutations.first)
    value['phases'].find { |phase| phase['name'] == 'beluga-core-mutations' }['sha256'] = Gate.sha(path)
    rejects('mutation oracle is incomplete') { verify(value) }
  end

  def test_shared_handoff_offers_full_discovered_and_pinned_coverage_cannot_be_removed
    klass = 'WebRTCTransportTests.BelugaRustHandoffOffersTests'
    names = %w[testAllBoundedSmallEventTracesMatchOriginalReference
               testSeededLongChurnKeepsBothSlotsAndReceiptIdentityInParity
               testSnapshotAgeBoundariesAndFiniteNegativeClockMatchOriginalReference
               testTimelineClockPositionAndStrictDeadlineBoundariesMatchReference
               testTimelineDriftScalesWithRateAndKeepsInclusiveBoundary
               testHostPhoneDriftUsesItsDistinctInclusiveBound
               testPlaybackSamplePreflightPreservesReceiptUntilConsumption
               testOriginalRevisionFloorDoesNotBecomeLatestRevisionHighWater
               testHigherRejectedSequenceBurnsFloorAndRetiresPreviousReceipt
               testMatchingConsumptionBurnsBeforeLateValidation
               testMismatchAndCounterfeitInputsPreserveExactPendingAuthority
               testFailedPreparationDoesNotBurnButFailedSendDoesBurnSequence
               testNativeSourceKeepsFractionalOriginalDeadlineAndBounds
               testSentAndReceivedSlotsRemainIndependentAcrossSingleSlotFailures
               testClearRetainsCountersButNewNegotiationResetsThem
               testCanonicalNativeEqualityPreservesOriginalBytesAndValueCopies
               testCanonicalAliasCannotBypassUTF8BoundOrBurnSequenceOnPreparationFailure
               testCommitHeaderAndCurrentPrimaryIdentityAreIndependent
               testReceivePrimaryIsBoundToIncomingEnvelopeNotRetiredReceipt
               testNonfiniteReceiveClockDoesNotMoveEarlyGuardsAheadOfSequenceBurn
               testSignedZeroStorageAndRoundedLargeClockDeadlineMatchOriginalReference
               testNativeSourceSnapshotAgeAndScaledDriftKeepOriginalBounds
               testActualSuppliedCommitUnicodeAndNaNPreservePreconsumeValidityOrdering
               testSeededSendCounterExhaustionRefusesMaxAndClearCannotResetIt
               testSeededReceiverMaxBurnAndIndependentSenderRemainInOriginalParity
               testTokenMaxIssuesOnceAndExhaustionCannotReuseOrResetMintCapacity
               testTokenExhaustionStillExpiresSentAndRetiresReplacedReceived
               testZeroCounterSeedIsTerminalButZeroTokenOnlyRefusesNewMint
               testCopiedOfferBoundaryAcceptsAllLegitimateCustodyTransitions
               testCopiedOfferBoundaryRejectsForgedMintConsumptionRetirementAndCounterReset]
    pins = names.map { |name| klass + '/' + name }
    assert_equal 30, pins.length
    assert_includes Gate::SHARED_HANDOFF_CLASSES, klass
    assert_equal pins, Gate::SHARED_HANDOFF_PINNED.select { |id| id.start_with?(klass + '/') }
    assert_equal @handoff_methods, Gate.shared_handoff_inventory(@handoff_methods.join("\n"))
    pins.each do |id|
      rejects('missing critical shared handoff test') { Gate.shared_handoff_inventory((@handoff_methods - [id]).join("\n")) }
    end
    offers = @handoff_methods.select { |id| id.start_with?(klass + '/') }
    # Discovered methods outside the fixed critical inventory must execute too;
    # pinning the class is not a license to filter away future non-pinned cases.
    assert_includes offers, klass + '/testFixture'
    offers.each do |id|
      rejects('missing Mac result') { Gate.validate_mac_log(mac_log(@handoff_methods - [id]), @handoff_methods) }
      ruby_class, method = id.split('/')
      passed = "Test Case '-[#{ruby_class} #{method}]' passed (0.001 seconds)."
      rejects('failed, skipped') do
        Gate.validate_mac_log(mac_log(@handoff_methods).sub(passed, passed.sub('passed', 'skipped')), @handoff_methods)
      end
    end
    rejects('footer has missing') do
      Gate.validate_mac_log(mac_log(@handoff_methods).sub("Executed #{@handoff_methods.length} tests", 'Executed 54 tests'), @handoff_methods)
    end
    value = receipt
    without_offers = @handoff_methods - offers
    discovery = File.join(@evidence, 'mac-discovery.log')
    File.write(discovery, (@mac_methods + @shared_methods + @shared_replay_methods.values.flatten + @shared_reconnect_counter_methods + without_offers).join("\n"))
    value['phases'].find { |phase| phase['name'] == 'mac-discovery' }['sha256'] = Gate.sha(discovery)
    value['coverage']['shared_handoff'] = without_offers
    result = File.join(@evidence, 'shared-handoff-tests.log')
    File.write(result, mac_log(without_offers))
    value['phases'].find { |phase| phase['name'] == 'shared-handoff-tests' }['sha256'] = Gate.sha(result)
    rejects('missing shared handoff class') { verify(value) }
  end

  def test_handoff_menu_and_rust_policy_classes_and_critical_cases_are_mandatory
    %w[BelugaMediaHandoffMenuTests WorldwidePreparedMediaMenuIntegrationTests BelugaRustHandoffPolicyTests BelugaRustHostLifecycleTests WorldwideHostLifecycleTests].each do |name|
      prefix = 'CaptureServerTests.' + name + '/'
      rejects('missing Mac test class') { Gate.mac_inventory(@mac_methods.reject { |id| id.start_with?(prefix) }.join("\n")) }
      pins = Gate::MAC_PINNED.select { |id| id.start_with?(prefix) }
      refute_empty pins
      pins.each { |id| rejects('missing critical Mac test') { Gate.mac_inventory((@mac_methods - [id]).join("\n")) } }
    end
  end

  def test_shared_handoff_classes_and_every_critical_source_case_are_mandatory
    %w[testCopiedScalarBoundaryRejectsMissingRetirementEffectsAndReplay
       testCopiedScalarBoundaryAcceptsLegitimateCustodyTransitions].each do |method|
      assert_includes Gate::SHARED_HANDOFF_PINNED, 'WebRTCTransportTests.BelugaRustHandoffTransactionTests/' + method
    end
    discovery = @handoff_methods.join("\n")
    assert_equal @handoff_methods, Gate.shared_handoff_inventory(discovery)
    Gate::SHARED_HANDOFF_CLASSES.each do |name|
      rejects('missing shared handoff class') { Gate.shared_handoff_inventory(@handoff_methods.reject { |id| id.start_with?(name + '/') }.join("\n")) }
    end
    Gate::SHARED_HANDOFF_PINNED.each do |id|
      rejects('missing critical shared handoff test') { Gate.shared_handoff_inventory((@handoff_methods - [id]).join("\n")) }
    end
    rejects('malformed or duplicated') { Gate.shared_handoff_inventory(discovery + "\n" + @handoff_methods.first) }
    rejects('malformed or duplicated') { Gate.shared_handoff_inventory(discovery + "\n" + Gate::SHARED_HANDOFF_CLASSES.first + '/testMalformed()') }
    rejects('malformed or duplicated') { Gate.shared_handoff_inventory('') }
  end

  def test_shared_handoff_phase_cannot_skip_cases_weaken_filter_or_borrow_old_coverage
    value = receipt
    value['phases'].reject! { |phase| phase['name'] == 'shared-handoff-tests' }
    rejects('absent, duplicate') { verify(value) }
    value = receipt
    value['coverage'].delete('shared_handoff')
    rejects('unrecognized field set') { verify(value) }
    value = receipt
    argv = value['phases'].find { |phase| phase['name'] == 'shared-handoff-tests' }['argv']
    argv[argv.index('--filter') + 1] = 'MediaHandoff'
    rejects('canonical offline invocation') { verify(value) }
    [mac_log(@handoff_methods.drop(1)), mac_log(@handoff_methods).sub('passed (0.001 seconds)', 'skipped (0.001 seconds)')].each do |text|
      value = receipt
      path = File.join(@evidence, 'shared-handoff-tests.log')
      File.write(path, text)
      value['phases'].find { |phase| phase['name'] == 'shared-handoff-tests' }['sha256'] = Gate.sha(path)
      rejects(text.include?('skipped') ? 'failed, skipped' : 'missing Mac result') { verify(value) }
    end
    value = receipt
    value['coverage']['shared_handoff'] = @mac_methods
    rejects('shared handoff coverage differs') { verify(value) }
  end

  def test_simulator_handoff_completion_cleanup_and_audio_leases_cannot_be_omitted_or_skipped
    classes = %w[YouTubeHandoffOperationTests YouTubeHandoffWebViewTests
                 YouTubeHandoffCoordinatorTests BelugaRustYouTubeHandoffOperationTests]
    classes.each do |name|
      assert_includes Gate::SIMULATOR_CLASSES, name
      pins = Gate::SIMULATOR_PINNED.select { |id| id.start_with?(name + '/') }
      refute_empty pins
    end
    additions = {
      'YouTubeHandoffCoordinatorTests' => %w[
        testExactOfferDispatchesOnceAndFastCompletionKeepsLocalPlayer
        testDismissRevokesImmediatelyButCannotUnmuteUntilExactStopAcknowledgement
        testOwnerInvalidationBeforePlaybackClosesWithoutSendingPause
        testPresentationSelectsTopmostOnceAndRejectsAmbiguityOrReplacement
        testNativeWebKitStopAcknowledgesBeforeReleaseAndOnlyOnce
        testUnpresentedOfferTimesOutWithoutHoldingAudioForever
        testSwiftUIPresenterActuallyMountsOnePlayerAboveRootAndFullScreen
        testAcquisitionRevocationCannotCreateAPlayerOrLeakSuppression
        testStaleConnectionAndRegressingClockCannotAcquireAudio
      ],
      'BelugaRustYouTubeHandoffOperationTests' => %w[
        testFrozenOriginalConfirmationAndAllCompletionOutcomesMatch
        testNativeMessageDomainsAndSequenceObservationOrderingMatch
        testWholeNativeProofEqualityRejectsEveryPublicFieldMutation
        testSignedZeroProofAliasUsesSwiftEqualityAndRetainsOriginalBits
        testArbitraryConstructorClockBitsPreserveOriginalObservationSemantics
        testAdjacentThresholdsAndUnrenewedProofAgeMatchFrozenArithmetic
        testCopiesBeforeMintProduceNonSubstitutablePrivateEvidenceUUIDs
        testCopiesWithExistingProofRevokeIndependentlyWithoutReminting
        testInterruptedOrStalePhonePlaybackPreservesTruthfulMacOutcome
        testBooleanClockFailureIsSilentButRevokesAndRepeatBeginIsEarlyNoop
        testZeroCandidateDoesNotChangeBranchesThatCannotMint
        testMaximumTokenMintsOnceAndExistingProofPendingAndLocalBranchesRemainUsable
        testZeroCandidateOnlyEligibleMintFailsClosedAfterClockAndSequenceBurn
        testLocalPlaybackNeverReopensHandoffAuthorityAndRetainsPausedOutcome
        testBoundedReachableTraceParityChecksEveryCopiedScalarAndPublicEffect
        testSeededLongTraceParityUsesFrozenOriginalWithoutDelegatingPolicy
        testCopiedBoundaryAcceptsLegitimateMintFailureClearAndSilentBooleanResults
        testCopiedBoundaryRejectsForgedMintRetainedProofRewriteAndCleanup
        testCopiedBoundaryRejectsMissingRevocationFictionalOutcomesAndReplay
        testMalformedCopiedOutputFailsClosedWithHonestStatusAndSilentBoolFallback
      ]
    }
    new_pins = additions.flat_map do |name, methods|
      expected = methods.map { |method| name + '/' + method }.sort
      assert_equal expected, Gate::SIMULATOR_PINNED.select { |id| id.start_with?(name + '/') }.sort
      expected
    end
    assert_equal 29, new_pins.length
    assert_equal 29, new_pins.uniq.length
    assert_equal 76, Gate::SIMULATOR_PINNED.length
    assert_equal 76, Gate::SIMULATOR_PINNED.uniq.length
    assert_empty new_pins & Gate::SIMULATOR_SKIPS
    path = File.join(@root, 'iOS/opensteamer/Tests/AudioTests.swift')
    original = File.binread(path)
    new_pins.each do |id|
      declaration = "func #{id.split('/').last}() {}\n"
      assert_equal 1, original.scan(Regexp.new(Regexp.escape(declaration))).length
      begin
        File.binwrite(path, original.sub(declaration, ''))
        rejects('missing critical Simulator test') { Gate.simulator_inventory(@root) }
      ensure
        File.binwrite(path, original)
      end
    end
    pins = Gate::SIMULATOR_PINNED.select do |id|
      classes.any? { |name| id.start_with?(name + '/') } || id.start_with?('WorldwideAudioLifecycleTests/testMediaHandoff') ||
        id.start_with?('WorldwideAudioLifecycleTests/testComposedHandoff')
    end
    refute_empty pins
    assert_empty pins & Gate::SIMULATOR_SKIPS
    pins.each do |id|
      value = results
      value['testNodes'].reject! { |node| node['nodeIdentifier'] == id + '()' }
      rejects('missing or duplicate') { Gate.validate_simulator(summary, value, @sim_methods, SIMULATOR) }
      value = results
      value['testNodes'].find { |node| node['nodeIdentifier'] == id + '()' }['result'] = 'Skipped'
      rejects('unexpected failure, skip') { Gate.validate_simulator(summary, value, @sim_methods, SIMULATOR) }
    end
  end

  def test_c_missing_test_and_sanitizer_only_one_round_fail
    assert_equal @c_methods, Gate.validate_c(c_log, @c_methods)
    rejects('incomplete') { Gate.validate_c(c_log.lines.drop(1).join, @c_methods) }
    rejects('incomplete') { Gate.validate_c(c_log, @c_methods, 2) }
  end

  def test_phase_absence_duplicate_or_reordering_fail
    value = receipt
    value['phases'].pop
    rejects('absent, duplicate') { verify(value) }
    value = receipt
    value['phases'][0], value['phases'][1] = value['phases'][1], value['phases'][0]
    rejects('reordered phases') { verify(value) }
  end

  def test_host_release_behavioral_phase_cannot_be_omitted_or_substituted
    name = 'host-release-hook-self-tests'
    value = receipt
    value['phases'].reject! { |phase| phase['name'] == name }
    rejects('absent, duplicate') { verify(value) }
    value = receipt
    path = File.join(@evidence, name + '.log')
    File.write(path, "microphone release gate behavior tests passed\n")
    value['phases'].find { |phase| phase['name'] == name }['sha256'] = Gate.sha(path)
    rejects('host release hook behavioral harness') { verify(value) }
    value = receipt
    value['phases'].find { |phase| phase['name'] == name }['argv'] = ['/usr/bin/ruby', File.join(@root, 'scripts/test-microphone-release-gate.rb')]
    rejects('canonical offline invocation') { verify(value) }
    marker = "microphone host release gate behavior tests passed\n"
    rejects('host release hook behavioral harness') { Gate.validate_host_release_harness(marker * 2) }
  end

  def test_simulator_signing_phase_cannot_be_omitted_or_substituted
    name = 'simulator-signing-self-tests'
    value = receipt
    value['phases'].reject! { |phase| phase['name'] == name }
    rejects('absent, duplicate') { verify(value) }
    value = receipt
    value['phases'].find { |phase| phase['name'] == name }['argv'].delete('--verbose')
    rejects('canonical offline invocation') { verify(value) }
    rejects('behavioral results') { Gate.validate_simulator_signing_harness(signing_log.lines.drop(1).join, @signing_methods) }
    rejects('behavioral results') { Gate.validate_simulator_signing_harness(signing_log + signing_log.lines.first, @signing_methods) }
    rejects('behavioral results') { Gate.validate_simulator_signing_harness(signing_log.sub(' s = .', ' s = S'), @signing_methods) }
    rejects('terminal marker') { Gate.validate_simulator_signing_harness(signing_log.sub('behavior tests passed', 'behavior tests absent'), @signing_methods) }
  end

  def test_mac_producer_phase_is_mandatory_named_and_canonical
    name = 'mac-producer-contract-tests'
    value = receipt
    value['phases'].reject! { |phase| phase['name'] == name }
    rejects('absent, duplicate') { verify(value) }
    value = receipt
    value['phases'].find { |phase| phase['name'] == name }['argv'].delete('--verbose')
    rejects('canonical offline invocation') { verify(value) }
    value = receipt
    path = File.join(@evidence, name + '.log')
    File.write(path, producer_log.lines.drop(1).join)
    value['phases'].find { |phase| phase['name'] == name }['sha256'] = Gate.sha(path)
    rejects('behavioral results') { verify(value) }
  end

  def test_utf8_text_boundaries_preserve_valid_bytes_and_reject_malformed_bytes
    [Encoding::US_ASCII, Encoding::ASCII_8BIT].each do |encoding|
      bytes = "◇ π ✔".dup.force_encoding(encoding).freeze
      assert_equal "◇ π ✔", Gate.utf8_text(bytes, 'fixture')
      assert_equal "◇ π ✔".bytes, bytes.bytes
      assert_equal encoding, bytes.encoding
      result = shared_log.dup.force_encoding(encoding).freeze
      assert_equal @shared_methods, Gate.validate_shared_signaling(result, @shared_methods)
      assert_equal encoding, result.encoding
      mac = (mac_log + "◇ Test run started.\n✔ Test run with 0 tests passed after 0.001 seconds.\n").force_encoding(encoding).freeze
      assert_equal @mac_methods, Gate.validate_mac_log(mac, @mac_methods)
      assert_equal encoding, mac.encoding
      mac_discovery = ("# π\n" + @mac_methods.join("\n")).force_encoding(encoding)
      assert_equal @mac_methods, Gate.mac_inventory(mac_discovery)
      discovery = ("# π\n" + @shared_methods.join("\n")).force_encoding(encoding)
      assert_equal @shared_methods, Gate.shared_signaling_inventory(discovery)
      producer = ("# π\n" + producer_log).force_encoding(encoding)
      assert_nil Gate.validate_mac_producer_harness(producer, @producer_methods)
    end
    rejects('is not text') { Gate.utf8_text(nil, 'fixture') }
    invalid = "\xFF".b
    rejects('not valid UTF-8') { Gate.mac_inventory(invalid) }
    rejects('not valid UTF-8') { Gate.validate_mac_log(mac_log.b + invalid, @mac_methods) }
    rejects('not valid UTF-8') { Gate.shared_signaling_inventory(invalid) }
    rejects('not valid UTF-8') { Gate.validate_shared_signaling(shared_log.b + invalid, @shared_methods) }
    rejects('not valid UTF-8') { Gate.validate_mac_producer_harness(producer_log.b + invalid, @producer_methods) }
  end

  def test_simulator_source_inventory_requires_valid_utf8_without_locale_transcoding
    path = File.join(@root, 'iOS/opensteamer/Tests/AudioTests.swift')
    source = "// π 🦈\n".b + File.binread(path)
    File.binwrite(path, source)
    assert_equal @sim_methods, Gate.simulator_inventory(@root)
    assert_equal source, File.binread(path)
    File.binwrite(path, source + "\xFF".b)
    rejects('not valid UTF-8') { Gate.simulator_inventory(@root) }
  end

  def test_mac_producer_source_inventory_requires_valid_utf8_without_locale_transcoding
    path = File.join(@root, 'macOS/scripts/verify-beluga-mac-client-tests.rb')
    source = File.binread(path) + "# π\n".b
    File.binwrite(path, source)
    assert_equal @producer_methods, Gate.mac_producer_inventory(@root)
    assert_equal source, File.binread(path)
    File.binwrite(path, source + "\xFF".b)
    rejects('not valid UTF-8') { Gate.mac_producer_inventory(@root) }
  end

  def test_mac_producer_inventory_requires_each_critical_case_and_no_duplicates
    path = File.join(@root, 'macOS/scripts/verify-beluga-mac-client-tests.rb')
    original = File.read(path)
    Gate::MAC_PRODUCER_PINNED.each do |method|
      File.write(path, original.sub("def #{method}\nend\n", ''))
      rejects('harness inventory') { Gate.mac_producer_inventory(@root) }
    end
    File.write(path, original + "def #{@producer_methods.first}\nend\n")
    rejects('harness inventory') { Gate.mac_producer_inventory(@root) }
  end

  def test_mac_producer_named_results_reject_missing_extra_duplicate_failed_or_skipped
    [producer_log.lines.drop(1).join, producer_log + producer_log.lines.first,
     producer_log.sub(@producer_methods.first, 'testUnexpected'),
     producer_log.sub(' s = .', ' s = ?')].each do |text|
      rejects('behavioral results') { Gate.validate_mac_producer_harness(text, @producer_methods) }
    end
    %w[S E F].each do |status|
      rejects('behavioral results') { Gate.validate_mac_producer_harness(producer_log.sub(' s = .', ' s = ' + status), @producer_methods) }
    end
  end

  def test_mac_producer_footer_must_be_one_exact_complete_footer_after_results
    footer = producer_log.lines.last
    [producer_log.sub(footer, ''), producer_log + footer, footer + producer_log.sub(footer, ''),
     producer_log.sub('0 skips', '1 skips'), producer_log.sub('602 assertions', '0 assertions'),
     producer_log.sub("#{@producer_methods.length} runs", '0 runs')].each do |text|
      rejects('harness footer') { Gate.validate_mac_producer_harness(text, @producer_methods) }
    end
  end

  def test_shared_signaling_inventory_requires_unique_canonical_methods_and_close_pins
    assert_equal 27, Gate::SHARED_SIGNALING_PINNED.length
    assert_equal @shared_methods, Gate.shared_signaling_inventory((@mac_methods + @shared_methods).join("\n"))
    ['', (@shared_methods + [@shared_methods.first]).join("\n"),
     @shared_methods.join("\n") + "\n" + Gate::SHARED_SIGNALING_SUITE + '/malformed'].each do |text|
      rejects('shared signaling discovery') { Gate.shared_signaling_inventory(text) }
    end
    Gate::SHARED_SIGNALING_PINNED.each do |id|
      rejects('shared signaling discovery') { Gate.shared_signaling_inventory((@shared_methods - [id]).join("\n")) }
    end
  end

  def test_shared_signaling_concurrent_interleaving_is_accepted
    assert_equal @shared_methods, Gate.validate_shared_signaling(shared_log, @shared_methods)
    # A pass may precede another method's start; only its own start must precede it.
    lines = shared_log.lines
    pass = lines.find { |line| line.start_with?('✔ Test ' + @shared_methods.first.split('/').last + ' ') }
    lines.delete(pass)
    first_start = lines.index { |line| line.start_with?('◇ Test ' + @shared_methods.first.split('/').last + ' ') }
    lines.insert(first_start + 1, pass)
    assert_equal @shared_methods, Gate.validate_shared_signaling(lines.join, @shared_methods)
  end

  def test_shared_signaling_cases_cannot_be_missing_duplicated_unexpected_or_pass_before_start
    first = @shared_methods.first.split('/').last
    start = "◇ Test #{first} started.\n"
    pass = "✔ Test #{first} passed after 0.001 seconds.\n"
    rejects('cases are missing') { Gate.validate_shared_signaling(shared_log.sub(start, '').sub(pass, ''), @shared_methods) }
    rejects('start is unexpected or duplicated') { Gate.validate_shared_signaling(shared_log.sub(start, start * 2), @shared_methods) }
    rejects('pass is unexpected, duplicated') { Gate.validate_shared_signaling(shared_log.sub(pass, pass * 2), @shared_methods) }
    rejects('start is unexpected') { Gate.validate_shared_signaling(shared_log.sub(first, 'unexpectedFixture()'), @shared_methods) }
    rejects('matching start') { Gate.validate_shared_signaling(shared_log.sub(start, pass + start), @shared_methods) }
  end

  def test_shared_signaling_failed_skipped_malformed_or_extra_suite_results_are_refused
    [shared_log.sub('✔ Test ', '✘ Test '), shared_log.sub(' passed after 0.001 seconds.', ' skipped.'),
     shared_log.sub('DurableSignalingClientTests started.', 'UnexpectedSuite started.'),
     shared_log + "◇ Suite OtherTests started.\n", shared_log + "Test Case '-[Other testFixture]' started.\n"].each do |text|
      rejects('malformed, failed, skipped') { Gate.validate_shared_signaling(text, @shared_methods) }
    end
  end

  def test_shared_signaling_suite_run_counts_order_and_case_bounds_are_exact
    suite_start = "◇ Suite DurableSignalingClientTests started.\n"
    suite_pass = "✔ Suite DurableSignalingClientTests passed after 0.003 seconds.\n"
    footer = shared_log.lines.last
    [shared_log.sub(suite_start, ''), shared_log.sub(suite_start, suite_start * 2),
     shared_log.sub(suite_pass, ''), shared_log.sub(suite_pass, suite_pass * 2),
     shared_log.sub('◇ Test run started.', ''), shared_log + "◇ Test run started.\n",
     shared_log.sub(footer, ''), shared_log + footer, footer + shared_log.sub(footer, ''),
     shared_log.sub("#{@shared_methods.length} tests in 1 suite", '0 tests in 1 suite'),
     shared_log.sub('tests in 1 suite', 'tests in 2 suite')].each do |text|
      rejects('suite/run footer') { Gate.validate_shared_signaling(text, @shared_methods) }
    end
    start = shared_log.lines.find { |line| line.start_with?('◇ Test ' + @shared_methods.first.split('/').last + ' ') }
    rejects('outside the exact suite') { Gate.validate_shared_signaling(start + shared_log.sub(start, ''), @shared_methods) }
    pass = shared_log.lines.find { |line| line.start_with?('✔ Test ' + @shared_methods.first.split('/').last + ' ') }
    rejects('outside the exact suite') { Gate.validate_shared_signaling(shared_log.sub(pass, '') + pass, @shared_methods) }
    rejects('bounds') { Gate.validate_shared_signaling('x' * (2 * 1024 * 1024 + 1), @shared_methods) }
  end

  def test_shared_signaling_phase_cannot_be_omitted_or_change_filter_or_test_framework
    name = 'shared-signaling-tests'
    value = receipt
    value['phases'].reject! { |phase| phase['name'] == name }
    rejects('absent, duplicate') { verify(value) }
    %w[--disable-xctest --skip-build].each do |option|
      value = receipt
      value['phases'].find { |phase| phase['name'] == name }['argv'].delete(option)
      rejects('canonical offline invocation') { verify(value) }
    end
    value = receipt
    argv = value['phases'].find { |phase| phase['name'] == name }['argv']
    argv[argv.index('--filter') + 1] = 'DurableSignalingClientTests'
    rejects('canonical offline invocation') { verify(value) }
    value = receipt
    path = File.join(@evidence, name + '.log')
    id = @shared_methods.first.split('/').last
    File.write(path, shared_log.lines.reject { |line| line.include?('Test ' + id + ' ') }.join)
    value['phases'].find { |phase| phase['name'] == name }['sha256'] = Gate.sha(path)
    rejects('cases are missing') { verify(value) }
  end

  def test_shared_signaling_joint_discovery_and_result_omission_cannot_remove_an_existing_case
    value = receipt
    id = Gate::SHARED_SIGNALING_SUITE + '/availabilityRejectsLegacyWaitingAndUsesExactAvailabilityMode()'
    discovery = File.join(@evidence, 'mac-discovery.log')
    File.write(discovery, File.readlines(discovery).reject { |line| line.strip == id }.join)
    value['phases'].find { |phase| phase['name'] == 'mac-discovery' }['sha256'] = Gate.sha(discovery)
    result = File.join(@evidence, 'shared-signaling-tests.log')
    File.write(result, shared_log(@shared_methods - [id]))
    value['phases'].find { |phase| phase['name'] == 'shared-signaling-tests' }['sha256'] = Gate.sha(result)
    rejects('shared signaling discovery') { verify(value) }
  end

  def test_each_critical_simulator_signing_parser_case_is_mandatory
    path = File.join(@root, 'scripts/test-microphone-simulator-signing.rb')
    original = File.read(path)
    Gate::SIMULATOR_SIGNING_PINNED.each do |method|
      File.write(path, original.sub("def #{method}\nend\n", ''))
      rejects('harness inventory') { Gate.simulator_signing_inventory(@root) }
    end
  end

  def test_retained_simulator_app_is_required_and_immutable
    value = receipt
    value['artifacts'].reject! { |artifact| artifact['name'] == 'simulator-app' }
    rejects('artifacts are incomplete') { verify(value) }
    value = receipt
    File.write(@collected_signing_record['appPath'] + '/Beluga', 'different executable')
    rejects('artifact bytes changed') { verify(value) }
    value = receipt
    retained_app = value['artifacts'].find { |artifact| artifact['name'] == 'simulator-app' }
    retained_app['path'] = 'driver-bundle-1-artifact'
    retained_app['sha256'] = value['artifacts'].find { |artifact| artifact['name'] == 'driver-bundle-1' }['sha256']
    rejects('retained app artifact') { verify(value) }
  end

  def test_signing_record_cannot_borrow_group_or_unsigned_coverage
    [lambda { |record| record['applicationGroups'] = ['group.wrong'] },
     lambda { |record| record['executable']['coveredCodePagesVerified'] = false },
     lambda { |record| record['signature']['after'] = false }].each do |mutate|
      value = receipt
      record = Marshal.load(Marshal.dump(@collected_signing_record))
      mutate.call(record)
      path = File.join(@evidence, 'simulator-entitlements.log')
      File.write(path, JSON.generate(record))
      value['phases'].find { |phase| phase['name'] == 'simulator-entitlements' }['sha256'] = Gate.sha(path)
      error = assert_raises(Signing::Refusal) { verify(value) }
      assert_includes error.message, 'signing record'
    end
  end

  def test_simulator_signing_requires_exact_read_only_tool_paths
    Signing::DEPENDENCIES.each do |tool|
      value = receipt
      value['tools'] = value['tools'].dup
      digest = value['tools'].delete(tool)
      fake = File.join(@temporary, 'fixture-tools', File.basename(tool))
      write(fake, 'not the fixed collector dependency')
      value['tools'][fake] = digest
      rejects('exact Simulator signing tool identities') { verify(value) }
    end
  end

  def test_fresh_simulator_collection_must_equal_the_retained_record
    value = receipt
    @collected_signing_record = Marshal.load(Marshal.dump(@collected_signing_record))
    @collected_signing_record['executable']['sha256'] = 'f' * 64
    rejects('signed identity changed') { verify(value) }
  end

  def test_terminal_receipt_fence_rejects_mutation_during_recollection
    tool = @tools.keys.find { |path| File.basename(path) == 'rustc' }
    tool_bytes = File.read(tool)
    mutations = [
      ['source identity changed', lambda { write(File.join(@root, 'late-source.swift'), 'changed during collection') }],
      ['tool identity drifted', lambda { File.write(@tools.keys.find { |tool| File.basename(tool) == 'rustc' }, 'replaced during collection') }],
      ['artifact bytes changed', lambda { write(@collected_signing_record['appPath'] + '/late-resource', 'changed during collection') }],
      ['artifact bytes changed', lambda { File.write(File.join(@evidence, 'driver-bundle-1-artifact/bytes'), 'changed during collection') }],
      ['phase log was changed', lambda { File.write(File.join(@evidence, 'rust-tests.log'), 'changed during collection') }],
      ['receipt bytes', lambda { File.open(File.join(@evidence, 'receipt.json'), 'a') { |file| file.write(' ') } }]
    ]
    mutations.each do |message, mutate|
      value = receipt
      begin
        rejects(message) { verify(value, during_collection: mutate) }
      ensure
        File.write(tool, tool_bytes)
      end
    end
  end

  def test_future_and_expired_receipts_fail
    value = receipt
    value['created_at'] = Time.now.to_i + 60
    rejects('future or expired') { verify(value) }
    value['created_at'] = Time.now.to_i - 7 * 86400 - 60
    rejects('future or expired') { verify(value) }
  end

  def test_source_mutation_rejects_otherwise_complete_receipt
    value = receipt
    write(File.join(@root, 'new-feature.swift'), 'a feature edit requires a new offline run')
    rejects('source identity') { verify(value) }
  end

  def test_source_executable_mode_and_artifact_empty_directory_are_bound
    value = receipt
    File.chmod(0755, File.join(@root, 'iOS/opensteamer/Tests/AudioTests.swift'))
    rejects('source identity') { verify(value) }
    value = receipt
    Dir.mkdir(File.join(@evidence, 'driver-bundle-1-artifact/unexpected-empty-directory'), 0700)
    rejects('artifact bytes changed') { verify(value) }
  end

  def test_artifact_mode_and_receipt_parent_privacy_are_bound
    value = receipt
    File.chmod(0755, File.join(@evidence, 'driver-bundle-1-artifact'))
    rejects('artifact bytes changed') { verify(value) }
    value = receipt
    File.chmod(0755, @evidence)
    rejects('receipt parent') { verify(value) }
  end

  def test_sensitive_malformed_json_contents_are_redacted
    secret_like_text = 'secret-like-fixture-never-print-9da84b'
    error = assert_raises(RuntimeError) { Gate.parse_json('{"token":"' + secret_like_text + '",', 'Result') }
    assert_includes error.message, 'contents redacted'
    refute_includes error.message, secret_like_text
    path = File.join(@evidence, 'receipt.json')
    File.write(path, '{"token":"' + secret_like_text + '",')
    File.chmod(0600, path)
    error = assert_raises(RuntimeError) { Gate.verify_receipt(path, Gate.sha(path), @root) }
    refute_includes error.message, secret_like_text
  end

  def test_deleting_each_new_native_regression_is_refused
    path = File.join(@root, 'macOS/VirtualAudioDriver/tests/OpensteamerVirtualMicrophoneDriverTests.c')
    original = File.read(path)
    names = ['idle dual-endpoint registrations do not starve new reader', 'active client capacity remains bounded and recovers',
             'diagnostic v2 matches representable frozen v1 state', 'registration allocation failure preserves writer and allows retry']
    names.each do |name|
      File.write(path, original.sub("{\"#{name}\", test_behavior},\n", ''))
      rejects('missing critical native C') { Gate.c_inventory(@root) }
    end
  end

  def test_tool_identity_drift_rejects_complete_receipt
    value = receipt
    tool = @tools.keys.find { |path| File.basename(path) == 'rustc' }
    File.write(tool, 'replaced compiler')
    rejects('tool identity drifted') { verify(value) }
  end

  def test_missing_tool_identity_fails
    value = receipt
    value['tools'].delete(@tools.keys.find { |path| File.basename(path) == 'cargo' })
    rejects('reviewed tool identities') { verify(value) }
  end

  def test_missing_or_drifted_node_is_refused
    rejects('required existing Node') { Gate.resolve_node(File.join(@temporary, 'absent-node')) }
    value = receipt
    node = @tools.keys.find { |path| File.basename(path) == 'node' }
    value['tools'] = value['tools'].dup
    value['tools'].delete(node)
    rejects('reviewed tool identities') { verify(value) }
    value = receipt
    File.write(node, 'changed Node executable fixture')
    rejects('tool identity drifted') { verify(value) }
  end

  def test_epoch_recovery_class_and_fail_closed_pins_are_mandatory
    prefix = 'CaptureServerTests.WorldwideSharedClockEpochRecoveryTests/'
    without_class = @mac_methods.reject { |id| id.start_with?(prefix) }
    rejects('missing Mac test class') { Gate.mac_inventory(without_class.join("\n")) }
    pins = Gate::MAC_PINNED.select { |id| id.start_with?(prefix) }
    assert_equal 3, pins.length
    pins.each do |id|
      rejects('missing critical Mac test') { Gate.mac_inventory((@mac_methods - [id]).join("\n")) }
    end
  end

  def test_v2_idle_decoder_pins_are_mandatory
    prefix = 'CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/'
    pins = Gate::MAC_PINNED.select { |id| id.start_with?(prefix) }
    assert_equal 8, pins.length
    pins.each do |id|
      rejects('missing critical Mac test') { Gate.mac_inventory((@mac_methods - [id]).join("\n")) }
    end
  end

  def test_catalog_and_update_contract_classes_and_fail_closed_pins_are_mandatory
    classes = %w[WorldwidePairedPhoneCatalogTests WorldwideHostCoordinatorTests WorldwidePairingCatalogBootstrapTests
                 BelugaPhoneCatalogMenuTests WorldwidePairingStoreTests WorldwideHostProcessLockTests BelugaMenuBarTests
                 BelugaUpdateCandidateMetadataTests BelugaUpdateInstalledArtifactTests BelugaUpdateSparkleSessionTests]
    prefixes = classes.map { |name| 'CaptureServerTests.' + name + '/' }
    prefixes.each do |prefix|
      rejects('missing Mac test class') { Gate.mac_inventory(@mac_methods.reject { |id| id.start_with?(prefix) }.join("\n")) }
    end
    pins = Gate::MAC_PINNED.select { |id| prefixes.any? { |prefix| id.start_with?(prefix) } }
    assert_equal 21, pins.length
    pins.each do |id|
      rejects('missing critical Mac test') { Gate.mac_inventory((@mac_methods - [id]).join("\n")) }
    end
  end

  def test_receipt_bytes_log_and_result_tree_tampering_fail
    value = receipt
    path, digest = save_receipt(value)
    File.open(path, 'a') { |file| file.write(' ') }
    rejects('receipt bytes') { Gate.verify_receipt(path, digest, @root) }
    path, digest = save_receipt(value)
    File.write(File.join(@evidence, 'rust-tests.log'), 'PASS')
    rejects('phase log was changed') { Gate.verify_receipt(path, digest, @root) }
    value = receipt
    path, digest = save_receipt(value)
    File.write(File.join(@evidence, 'simulator-result-artifact/bytes'), 'different xcresult bytes')
    rejects('artifact bytes changed') { Gate.verify_receipt(path, digest, @root) }
  end

  def test_rehashed_bad_result_cannot_borrow_pass_receipt
    value = receipt
    path = File.join(@evidence, 'simulator-results.log')
    broken = results
    broken['testNodes'].pop
    File.write(path, JSON.generate(broken))
    value['phases'].find { |phase| phase['name'] == 'simulator-results' }['sha256'] = Gate.sha(path)
    rejects('missing or duplicate') { verify(value) }
  end

  def test_receipt_without_whole_signed_simulator_invocation_fails
    value = receipt
    value['phases'].find { |phase| phase['name'] == 'simulator-tests' }['argv'].delete('CODE_SIGNING_ALLOWED=YES')
    rejects('canonical offline invocation') { verify(value) }
  end

  def test_arbitrary_or_physical_phase_commands_cannot_renew_receipt
    value = receipt
    value['phases'].find { |phase| phase['name'] == 'driver-tests' }['argv'] = ['/usr/bin/true']
    rejects('canonical offline invocation') { verify(value) }
    value = receipt
    phase = value['phases'].find { |entry| entry['name'] == 'simulator-tests' }
    phase['argv'][phase['argv'].index('-destination') + 1] = 'platform=iOS,id=' + SIMULATOR
    rejects('canonical offline invocation') { verify(value) }
  end

  def test_zero_skipped_or_missing_behavioral_harness_cannot_pass
    rejects('behavioral harness') { Gate.validate_harness('0 runs, 0 assertions, 0 failures, 0 errors, 0 skips') }
    rejects('behavioral harness') { Gate.validate_harness('34 runs, 259 assertions, 0 failures, 0 errors, 0 skips') }
    rejects('behavioral harness') { Gate.validate_harness('34 runs, 259 assertions, 0 failures, 0 errors, 1 skips') }
    rejects('behavioral harness') { Gate.validate_harness('PASS') }
  end

  def test_receipt_symlink_and_digest_without_external_value_fail
    value = receipt
    path, digest = save_receipt(value)
    link = File.join(@evidence, 'receipt-link.json')
    File.symlink(path, link)
    rejects('non-symlink') { Gate.verify_receipt(link, digest, @root) }
    rejects('independently retained') { Gate.verify_receipt(path, 'not-a-digest', @root) }
  end

  def test_executor_rejects_nonzero_and_deadline_and_reaps_owned_child
    executor = Gate::Executor.new
    log = File.join(@evidence, 'executor.log')
    environment = { 'PATH' => '/usr/bin:/bin' }
    rejects('unsuccessfully') { executor.run(['/usr/bin/ruby', '-e', 'exit 7'], environment, @root, log, 1) }
    rejects('exceeded deadline') { executor.run(['/usr/bin/ruby', '-e', 'sleep 5'], environment, @root, log, 0.1) }
  end

  def test_loaded_production_pressure_marker_is_mandatory
    value = receipt
    path = File.join(@evidence, 'driver-load.log')
    File.write(path, "VERIFIED_BUILT_DRIVER_BUNDLE_LOAD\n")
    value['phases'].find { |phase| phase['name'] == 'driver-load' }['sha256'] = Gate.sha(path)
    rejects('pressure and exact PCM') { verify(value) }
    rejects('pressure and exact PCM') { Gate.validate_driver_load("PASS: loaded production driver idle-registration pressure and exact PCM\n") }
    markers = ['VERIFIED_BUILT_DRIVER_BUNDLE_LOAD',
               'PASS: loaded production driver idle-registration pressure and exact PCM',
               'PASS: loaded driver pristine and retired idle contract mutations']
    markers.each do |marker|
      rejects('pressure and exact PCM') { Gate.validate_driver_load((markers - [marker]).join("\n") + "\n") }
      rejects('pressure and exact PCM') { Gate.validate_driver_load((markers + [marker]).join("\n") + "\n") }
    end
    retirement_missing = markers.reject { |marker| marker.include?('retired idle') }.join("\n") + "\n"
    File.write(path, retirement_missing)
    value['phases'].find { |phase| phase['name'] == 'driver-load' }['sha256'] = Gate.sha(path)
    rejects('pressure and exact PCM') { verify(value) }
  end

  def test_term_interrupt_reaps_owned_executor_child
    log = File.join(@evidence, 'interrupt-executor.log')
    child = fork do
      Gate.install_interrupt_handlers
      begin
        Gate::Executor.new.run(['/usr/bin/ruby', '-e', 'puts Process.pid; STDOUT.flush; sleep 5'], { 'PATH' => '/usr/bin:/bin' }, @root, log, 5)
        exit! 1
      rescue Interrupt
        exit! 130
      end
    end
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    until File.file?(log) && !File.read(log).strip.empty?
      raise 'fixture executor did not start within deadline' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.01
    end
    owned = Integer(File.read(log).strip)
    Process.kill('TERM', child)
    _pid, status = Process.waitpid2(child)
    child = nil
    assert_equal 130, status.exitstatus
    assert_raises(Errno::ESRCH) { Process.kill(0, owned) }
  ensure
    if child
      begin
        Process.kill('TERM', child)
      rescue Errno::ESRCH
      end
      Process.waitpid(child)
    end
  end

  def test_cache_is_not_deleted_by_receipt_verification
    value = receipt
    cache = File.join(@temporary, 'cache-marker')
    File.write(cache, 'retain existing build cache')
    verify(value)
    assert_equal 'retain existing build cache', File.read(cache)
  end
end
