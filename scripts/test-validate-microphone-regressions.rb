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
    write(File.join(core_artifact, 'Info.plist'), <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict>
      <key>AvailableLibraries</key><array><dict>
      <key>BinaryPath</key><string>libbeluga_core.a</string>
      <key>HeadersPath</key><string>Headers</string>
      <key>LibraryIdentifier</key><string>macos-arm64</string>
      <key>LibraryPath</key><string>libbeluga_core.a</string>
      <key>SupportedArchitectures</key><array><string>arm64</string></array>
      <key>SupportedPlatform</key><string>macos</string>
      </dict></array>
      <key>CFBundlePackageType</key><string>XFWK</string>
      <key>XCFrameworkFormatVersion</key><string>1.0</string>
      </dict></plist>
    XML
    write(File.join(core_artifact, 'BUILD_METADATA.txt'),
          "rust-toolchain=1.97.1\nsupported-target=aarch64-apple-darwin\nsupported-architecture=arm64\nabi-version=1\n" +
          "rustc 1.97.1 (fixture 2026-09-30)\nrelease: 1.97.1\nhost: aarch64-apple-darwin\n" + Gate::XCODE_VERSION + "macos-sdk=26.6\n")
    write(File.join(core_artifact, 'macos-arm64/libbeluga_core.a'), 'inert core archive fixture')
    { 'include/beluga_core.h' => 'macos-arm64/Headers/beluga_core.h',
      'include/module.modulemap' => 'macos-arm64/Headers/module.modulemap',
      'THIRD_PARTY_NOTICES.html' => 'THIRD_PARTY_NOTICES.html' }.each do |source, published|
      write(File.join(core_artifact, published), File.binread(File.join(core_crate, source)))
    end
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
    @rust_methods = Gate::RUST_PINNED.sort
    @core_methods = (Gate::BELUGA_CORE_PINNED + ['additional_core_behavior_fixture']).sort
    @c_methods = Gate.c_inventory(@root)
    @developer = File.join(@temporary, 'fixture-Xcode.app/Contents/Developer')
    @tools = %w[xcodebuild swift swiftc clang make ruby xcrun cargo rustc node].map do |name|
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

  def signing_record_fixture
    # Structural receipt fixture, deliberately not a signed executable. The
    # collector's actual byte/signature parser has its own mandatory test phase.
    app = File.join(@evidence, 'simulator-app/Beluga.app')
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
    log_texts = {
      'gate-self-tests' => gate_log,
      'simulator-signing-self-tests' => signing_log,
      'release-hook-self-tests' => "microphone release gate behavior tests passed\n",
      'host-release-hook-self-tests' => "microphone host release gate behavior tests passed\n",
      'mac-producer-contract-tests' => producer_log,
      'product-identity' => "Beluga product identity check passed\n",
      'product-identity-mutations' => "opensteamer product identity regression tests passed\n",
      'mac-discovery' => (@mac_methods + @shared_methods).join("\n") + "\n", 'mac-tests' => mac_log,
      'shared-signaling-tests' => shared_log,
      'simulator-summary' => JSON.generate(summary), 'simulator-results' => JSON.generate(results),
      'simulator-entitlements' => JSON.generate(@collected_signing_record),
      'rust-discovery' => @rust_methods.map { |method| method + ': test' }.join("\n") + "\n",
      'beluga-core-discovery' => @core_methods.map { |method| method + ': test' }.join("\n") + "\n",
      'beluga-core-tests' => rust_log(@core_methods),
      'beluga-core-link' => "BELUGA_CORE_LINK_SMOKE_PASS\n",
      'beluga-core-mutations' => Gate::BELUGA_CORE_MUTANTS.map { |name| "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed\n" }.join +
                               "BELUGA_CORE_MUTATIONS_PASS cases=#{Gate::BELUGA_CORE_MUTANTS.length}\n",
      'rust-tests' => rust_log, 'driver-tests' => c_log, 'driver-sanitizers' => c_log * 2,
      'driver-load' => "VERIFIED_BUILT_DRIVER_BUNDLE_LOAD\nPASS: loaded production driver idle-registration pressure and exact PCM\nPASS: loaded driver pristine and retired idle contract mutations\n",
      'driver-malformed-bundles' => "ALL_DRIVER_BUNDLE_VERIFIER_MUTATIONS_REJECTED\n",
      'driver-diagnostic-reader' => "DIAGNOSTIC_SNAPSHOT_READER_TESTS_PASSED_WITHOUT_CORE_AUDIO_IO\n"
    }
    invocation = { 'developer_directory' => @developer, 'scratch' => @scratch, 'swift_scratch' => File.join(@scratch, 'SwiftPM'), 'timeout_seconds' => 1800 }
    commands = Gate.commands(@root, @evidence, invocation, @tools, SIMULATOR, @mac_methods)
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
    { 'schema' => Gate::SCHEMA, 'status' => 'passed', 'scope' => 'offline-source-only', 'root' => @root,
      'created_at' => Time.now.to_i, 'source' => Gate.source_identity(@root), 'tools' => @tools, 'simulator' => SIMULATOR,
      'invocation' => invocation, 'mac_format' => 'darwin-xctest-log', 'phases' => phases, 'artifacts' => artifacts,
      'coverage' => { 'mac' => @mac_methods, 'simulator' => @sim_methods, 'intentional_simulator_skips' => Gate::SIMULATOR_SKIPS,
                      'rust' => @rust_methods, 'beluga_core' => @core_methods, 'c' => @c_methods } }
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
      raise Signing::Refusal, 'fixture app binding differs' unless app == @collected_signing_record['appPath']
      during_collection.call if during_collection
      Marshal.load(Marshal.dump(@collected_signing_record))
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
    File.write(File.join(core_artifact, 'macos-arm64/libbeluga_core.a'), 'changed ignored archive')
    rejects('source identity') { verify(value) }
    rejects('checksum differs') { Gate.validate_beluga_core_artifacts(@root) }
  end

  def test_beluga_core_rejects_missing_unbound_symlinked_or_empty_artifact
    path = File.join(core_artifact, 'macos-arm64/libbeluga_core.a')
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
    rejects('missing, duplicate or unbound files') { Gate.validate_beluga_core_artifacts(@root) }
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
    [File.join(@developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'), '/usr/bin/lipo'].each do |tool|
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
      rejects('recorded Beluga core tools') { verify(value) }
    end
  end

  def test_beluga_core_rehashed_header_slice_or_tool_metadata_drift_is_rejected
    path = File.join(core_artifact, 'macos-arm64/Headers/beluga_core.h')
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

  def test_handoff_menu_and_rust_policy_classes_and_critical_cases_are_mandatory
    %w[BelugaMediaHandoffMenuTests BelugaRustHandoffPolicyTests BelugaRustHostLifecycleTests WorldwideHostLifecycleTests].each do |name|
      prefix = 'CaptureServerTests.' + name + '/'
      rejects('missing Mac test class') { Gate.mac_inventory(@mac_methods.reject { |id| id.start_with?(prefix) }.join("\n")) }
      pins = Gate::MAC_PINNED.select { |id| id.start_with?(prefix) }
      refute_empty pins
      pins.each { |id| rejects('missing critical Mac test') { Gate.mac_inventory((@mac_methods - [id]).join("\n")) } }
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
    value['artifacts'].find { |artifact| artifact['name'] == 'simulator-app' }['path'] = 'driver-bundle-1-artifact'
    value['artifacts'].last['sha256'] = value['artifacts'][1]['sha256']
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
