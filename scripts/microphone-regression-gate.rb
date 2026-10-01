#!/usr/bin/ruby
# Offline contributor evidence only. No physical destination or installed HAL probe is used.
require 'digest'
require 'fileutils'
require 'find'
require 'json'
require 'open3'
require 'rexml/document'
require 'set'
require 'tmpdir'
require_relative 'microphone-simulator-signing'

module MicrophoneRegressionGate
  SCHEMA = 'beluga.microphone-regressions.offline.v1'.freeze
  XCODE_VERSION = "Xcode 26.6\nBuild version 17F113\n".freeze
  XCODEBUILD_SHA256 = 'd508f0e1901151843804e4af512d4587ad0e422039e43e14abf22792360ad3d4'.freeze
  RUST_VERSION = '1.97.1'.freeze
  RUSTUP_HOME = '/Volumes/t7/opensteamer-rustup-1.97.1'.freeze
  CARGO_HOME = '/Volumes/t7/opensteamer-cargo-1.97.1'.freeze
  NODE_ENTRYPOINT = '/opt/homebrew/bin/node'.freeze
  RUST_SOURCE_FILES = %w[Cargo.toml Cargo.lock rust-toolchain.toml .gitignore src/lib.rs
                       include/opensteamer_audio_transaction_authority.h include/module.modulemap
                       scripts/build-xcframework.sh scripts/verify-xcframework.sh tests/reducer.rs tests/ffi.rs
                       tests/c_abi_smoke.c tests/swift_import_smoke.swift THIRD_PARTY_NOTICES.html].freeze
  C_PINNED = {
    'core invariant' => ['visible-first/writer-first joins and leaves', '1000 fresh epochs', 'concurrent lifecycle and timeline stress'],
    'driver interface' => ['shared timeline both start orders and restart seed',
                           'idle dual-endpoint registrations do not starve new reader',
                           'active client capacity remains bounded and recovers',
                           'diagnostic v2 matches representable frozen v1 state',
                           'registration allocation failure preserves writer and allows retry',
                           'zero timestamp publication keeps returned lifecycle',
                           'diagnostic snapshot concurrent coherency and progress']
  }.freeze
  SIMULATOR_CLASSES = %w[WorldwideAudioLifecycleTests WebRTCAudioPlaybackSessionTests IOSAudioDiagnosticsJournalTests].freeze
  SIMULATOR_SKIPS = %w[
    WorldwideAudioLifecycleTests/testPhysicalDeviceCanConfigureLegacyBackgroundPlaybackSession
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioOriginalOrder
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioInitialIdle
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioPostInputRead
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioColdDuplexFirst
    WebRTCAudioPlaybackSessionTests/testPhysicalPolicyScenarioProductionOrder
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterRemoteCommandCenterShared
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterDisabledPlayCommandTarget
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterNowPlayingInfoCenterDefault
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterClearingNowPlayingInfo
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterStoppedPlaybackState
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterPlayCommandTargetOnly
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterDisablingPlayCommandOnly
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterDisabledPlayTargetRemoval
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyRestoresCapturedDefaultAfterTargetRemoval
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyRegistersTargetAfterInactiveDuplexSetter
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicySetsInactiveDuplexWhileTargetIsRegistered
    WebRTCAudioPlaybackSessionTests/testPhysicalInertPolicyAfterBeginReceivingRemoteControlEvents
    WebRTCAudioPlaybackSessionTests/testPhysicalInertDevelopmentHostMicrophonePermissionSetup
    WebRTCAudioPlaybackSessionTests/testPhysicalInertInputTapCharacterizesRegisteredMediaCommandPolicy
    WebRTCAudioPlaybackSessionTests/testPhysicalSoleViewerRemoteIOCapturesMicrophoneAcrossPublicAdmissionCycles
    WebRTCAudioPlaybackSessionTests/testPeerUsesStereoRemoteIOAndReceivesNativePlayoutCallbacks
  ].freeze
  SIMULATOR_PINNED = %w[
    WorldwideAudioLifecycleTests/testOrdinaryRawMicrophoneProfileRequiresExactTupleAndSupportedEffectivePolicy
    WorldwideAudioLifecycleTests/testTransportUncertaintyClosesMicrophonePrivacyBeforeOutputOnlyOwnerReturns
    WorldwideAudioLifecycleTests/testPublicOutputOnlyDisableClosesMicrophonePrivacyBeforeNativeAttemptForSuccessAndFailure
    WorldwideAudioLifecycleTests/testSuspendedRawMicrophoneStatisticsReadCannotRepublishAcrossEveryRevocationBoundary
    WorldwideAudioLifecycleTests/testWiredMicrophoneOracleRequiresFreshExclusiveRouteAndPrivacyAuthority
    WorldwideAudioLifecycleTests/testManualMicrophoneOffCancelsPendingAutomaticAttemptAndPersistsAcrossRecovery
    WorldwideAudioLifecycleTests/testNewAuthenticatedSessionMayRetryAutomaticMicrophoneAfterDenial
    WorldwideAudioLifecycleTests/testReplacementConnectionWaitsForRetiredPeerCloseBeforeAudioActivation
    WorldwideAudioLifecycleTests/testReconnectNoOutboundRTPLifecycleCompositionRecoversOnceAcrossDelayedSameTargetNotification
    WorldwideAudioLifecycleTests/testTransportUncertaintyRetiresEstablishedMicrophoneBeforeHealthyReAdmission
    WorldwideAudioLifecycleTests/testFreshPreparationWaitsForExactRetiredPeerClose
    WorldwideAudioLifecycleTests/testDeferredMicrophonePermissionCannotCrossRevocationBoundaries
    WorldwideAudioLifecycleTests/testRetiredPollingProofCannotApplyHealthyDiagnosticsToReplacementAudio
    WorldwideAudioLifecycleTests/testRetiredRecoveryAuthorizationBlocksDelayedNativeSideEffect
    WebRTCAudioPlaybackSessionTests/testFrameworkMicrophoneStopClosesCaptureWithoutStealingOutputOnlyTransaction
    WebRTCAudioPlaybackSessionTests/testPendingCategoryRouteCursorRequiresExactChainedTransactionEvidence
    WebRTCAudioPlaybackSessionTests/testMicrophoneApprovalRejectsZeroWrongStaleRevokedAndRetiredGenerations
    WebRTCAudioPlaybackSessionTests/testWiredMicrophoneNativeSelectionAndEveryTransactionBoundary
  ].freeze
  MAC_CLASSES = %w[
    CaptureCoreTests.CoreAudioProcessTapAggregateConfigurationTests
    CaptureCoreTests.CoreAudioProcessTapStartupDiagnosticsTests
    CaptureCoreTests.BlackHoleDefaultInputLeaseTests
    CaptureCoreTests.WorldwideSafeOutputInvariantTests
    CaptureCoreTests.BlackHoleRouteHealthTests
    CaptureServerTests.WorldwideIPhoneMicrophoneForwardingDriverTests
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests
    CaptureServerTests.WorldwideIPhoneMicrophoneForwardingWebRTCIntegrationTests
    CaptureServerTests.BlackHoleMicrophoneOutputTests
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests
    CaptureServerTests.WorldwideSharedClockEpochRecoveryTests
  ].freeze
  MAC_PINNED = %w[
    CaptureCoreTests.CoreAudioProcessTapAggregateConfigurationTests/testEveryFreshAggregateStartsWithoutWaitingForTappedPlayback
    CaptureServerTests.WorldwideBlackHoleDefaultInputCoordinatorTests/testDeviceBeforeConnectionSelectsAtHealthyBoundaryWithoutTrack
    CaptureServerTests.WorldwideIPhoneMicrophoneForwardingDriverTests/testLANCoexistencePolicySuppressesEveryHealthyInput
    CaptureServerTests.WorldwideIPhoneMicrophoneForwardingWebRTCIntegrationTests/testLateRealInboundRTPRevivesExhaustedForwardingOnSamePeerAndTrack
    CaptureServerTests.WorldwideSharedClockEpochRecoveryTests/testPublicIdleCannotOverrideAnActiveOrChangedDriverEpoch
    CaptureServerTests.WorldwideSharedClockEpochRecoveryTests/testDriverDiagnosticReadFailureKeepsPublicIdleUnproved
    CaptureServerTests.WorldwideSharedClockEpochRecoveryTests/testSystemWidePropertyFailureDoesNotFallBackToProcessLocalIdle
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testCompleteV2IdleOverflowInventoryProvesMirroredIdle
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testActiveV2OverflowLeaseCannotProveIdle
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testV2DecoderRejectsMalformedDuplicateStaleAndIncompleteInventories
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testV2MirroredProofRejectsRegistryChurnAndMixedFormats
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testReaderFallsBackToFrozenV1OnlyWhenV2PropertyIsAbsent
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testReaderRejectsUnavailableOrMalformedV2WithoutV1Fallback
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testV2PropertyBoundaryRejectsOversizedAndStaleObservations
    CaptureServerTests.WorldwideVirtualMicrophoneDriverIdleTests/testV2FailureCountersDoNotInvalidateTruthfulIdleInventory
  ].freeze
  RUST_PINNED = %w[
    ordinary_raw_microphone_effective_sharing_preserves_requested_and_observed_values
    ordinary_raw_microphone_profile_rejects_other_policies_and_all_tuple_or_owner_changes
    ordinary_microphone_sharing_profile_does_not_expand_other_targets
  ].freeze
  PHASES = %w[gate-self-tests simulator-signing-self-tests release-hook-self-tests host-release-hook-self-tests product-identity product-identity-mutations rust-artifact-validation mac-discovery mac-tests simulator-tests simulator-summary simulator-results simulator-signature
              simulator-entitlements rust-discovery rust-tests driver-tests driver-sanitizers driver-diagnostic-reader driver-build-1
              driver-build-2 driver-verifier driver-load driver-malformed-bundles].freeze
  PROTECTED_ROOTS = ['/Applications', '/Library', '/System', '/Users/ahmed/Library/Application Support/opensteamer'].freeze

  def self.require!(condition, message)
    raise RuntimeError, message unless condition
  end

  def self.exact_keys!(value, keys, label)
    require!(value.is_a?(Hash) && value.keys.sort == keys.sort, "#{label} has an unrecognized field set")
  end

  def self.sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def self.parse_json(text, label)
    JSON.parse(text)
  rescue JSON::ParserError
    raise RuntimeError, label + ' JSON is malformed (contents redacted)'
  end

  def self.regular!(path)
    stat = File.lstat(path)
    require!(stat.file? && !stat.symlink?, "not a regular non-symlink file: #{path}")
    stat
  end

  def self.resolve_node(path = NODE_ENTRYPOINT)
    require!(File.exist?(path), 'required existing Node executable is unavailable; do not install or upgrade tools')
    resolved = File.realpath(path)
    require!(regular!(resolved).file? && File.executable?(resolved), 'required existing Node executable is not executable')
    resolved
  end

  def self.source_identity(root)
    output, status = Open3.capture2('/usr/bin/git', '-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z')
    require!(status.success?, 'could not inventory source')
    paths = output.split("\0")
    # These ignored binary inputs are consumed by Xcode and must match the tested bytes.
    paths << 'shared/Vendor/LiveKitWebRTC/LiveKitWebRTC.xcframework.zip'
    artifact = File.join(root, 'iOS/opensteamer/Frameworks/OpensteamerAudioTransactionAuthority.xcframework')
    require!(File.directory?(artifact) && !File.symlink?(artifact), 'Rust XCFramework is absent or symlinked')
    Find.find(artifact) do |path|
      require!(!File.symlink?(path), 'Rust XCFramework contains a symlink')
      paths << path.delete_prefix(root + '/') if File.file?(path)
    end
    entries = paths.uniq.sort.map do |relative|
      require!(!relative.start_with?('/') && !relative.split('/').include?('..'), 'unsafe source path')
      path = File.join(root, relative)
      stat = regular!(path)
      [relative, 'file', stat.mode & 0777, sha(path)]
    end
    { 'sha256' => Digest::SHA256.hexdigest(JSON.generate(entries)), 'files' => entries }
  end

  def self.simulator_inventory(root)
    methods = []
    Dir.glob(File.join(root, 'iOS/opensteamer/Tests/**/*.swift')).sort.each do |path|
      text = File.read(path)
      matches = []
      text.to_enum(:scan, /\b(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b/).each do
        match = Regexp.last_match
        matches << [match[1], match.end(0)]
      end
      matches.each_with_index do |(name, offset), index|
        next unless SIMULATOR_CLASSES.include?(name)
        ending = index + 1 < matches.length ? matches[index + 1][1] : text.length
        text[offset...ending].scan(/\bfunc\s+(test\w+)\s*\(/).each { |entry| methods << name + '/' + entry.first }
      end
    end
    require!(!methods.empty? && methods.uniq.length == methods.length, 'empty or duplicate Simulator source inventory')
    SIMULATOR_CLASSES.each { |name| require!(methods.any? { |id| id.start_with?(name + '/') }, "missing Simulator class: #{name}") }
    (SIMULATOR_PINNED + SIMULATOR_SKIPS).each { |id| require!(methods.include?(id), "missing critical Simulator test: #{id}") }
    methods.sort
  end

  def self.validate_simulator(summary, results, expected, simulator)
    require!(summary.is_a?(Hash) && summary['result'] == 'Passed', 'Simulator result did not pass')
    require!(summary['totalTestCount'] == expected.length && summary['passedTests'] == expected.length - SIMULATOR_SKIPS.length &&
             summary['skippedTests'] == SIMULATOR_SKIPS.length && summary['failedTests'] == 0 &&
             summary['expectedFailures'] == 0 && summary['testFailures'] == [], 'Simulator summary counts are incomplete or disagree')
    configurations = summary['devicesAndConfigurations']
    require!(configurations.is_a?(Array) && configurations.length == 1, 'Simulator result has multiple or missing configurations')
    configuration = configurations.first
    device = configuration['device'] || {}
    require!(device['deviceId'].to_s.casecmp?(simulator) && device['platform'].to_s.include?('Simulator'), 'result belongs to a physical or different destination')
    %w[passedTests skippedTests failedTests expectedFailures].each do |key|
      require!(configuration[key] == summary[key], 'Simulator per-configuration count disagrees')
    end
    cases = []
    walk = lambda do |node|
      if node.is_a?(Hash)
        cases << node if node['nodeType'] == 'Test Case'
        node.each_value { |value| walk.call(value) }
      elsif node.is_a?(Array)
        node.each { |value| walk.call(value) }
      end
    end
    walk.call(results)
    require!(!cases.empty?, 'zero Simulator tests executed')
    observed = cases.map do |node|
      id = node.fetch('nodeIdentifier', '').sub(/\(\)\z/, '').sub(/\AopensteamerTests\//, '')
      require!(expected.include?(id), 'unexpected Simulator test identity')
      wanted = SIMULATOR_SKIPS.include?(id) ? 'Skipped' : 'Passed'
      require!(node['result'] == wanted, "unexpected failure, skip or status for #{id}")
      id
    end
    require!(observed.uniq.length == observed.length && observed.sort == expected.sort, 'missing or duplicate Simulator test results')
    expected - SIMULATOR_SKIPS
  end

  def self.validate_xunit(text, expected)
    cases = REXML::XPath.match(REXML::Document.new(text), '//testcase')
    require!(!cases.empty?, 'zero Mac tests executed')
    observed = cases.map do |entry|
      id = entry.attributes['classname'].to_s + '/' + entry.attributes['name'].to_s
      short = id.split('.').last
      aliases = expected.select { |candidate| candidate.split('.').last == short }
      id = aliases.first if !expected.include?(id) && aliases.length == 1
      require!(expected.include?(id), "unexpected Mac result: #{id}")
      require!(!entry.elements['skipped'] && !entry.elements['failure'] && !entry.elements['error'], "Mac test failed or skipped: #{id}")
      require!(['', 'run', 'passed', 'success'].include?(entry.attributes['status'].to_s.downcase), 'unrecognized Mac test status')
      id
    end
    require!(observed.uniq.length == observed.length && observed.sort == expected.sort, 'missing or duplicate Mac test results')
    expected
  rescue REXML::ParseException
    raise RuntimeError, 'Mac xUnit is malformed (contents redacted)'
  end

  def self.validate_mac_log(text, expected)
    lines = text.lines.map(&:chomp)
    starts = lines.each_index.select { |index| lines[index].match?(/\ATest Suite 'Selected tests' started at .+\.\z/) }
    ends = lines.each_index.select { |index| lines[index].match?(/\ATest Suite 'Selected tests' passed at .+\.\z/) }
    require!(starts.length == 1 && ends.length == 1 && starts.first < ends.first, 'missing or duplicate Selected tests suite')
    active = nil
    started = []
    passed = []
    lines.each_with_index do |line, index|
      require!(!line.match?(/\ATest Suite '.+' (failed|skipped) at /), 'Mac suite failed or skipped')
      next unless line.start_with?('Test Case ')
      match = /\ATest Case '-\[([\w.]+) (test\w+)\]' (started\.|(passed|failed|skipped) \([\d.]+ seconds\)\.)\z/.match(line)
      require!(match && index > starts.first && index < ends.first, 'malformed or out-of-suite Mac result')
      id = match[1] + '/' + match[2]
      require!(expected.include?(id), "unexpected Mac test: #{id}")
      if match[3] == 'started.'
        require!(!active && !started.include?(id), 'duplicate or interleaved Mac start')
        started << id
        active = id
      else
        require!(match[4] == 'passed' && active == id && !passed.include?(id), 'Mac test failed, skipped or lacked a matching start')
        passed << id
        active = nil
      end
    end
    require!(!active && !passed.empty? && passed.sort == expected.sort, 'missing Mac result or zero executed tests')
    footer = /\A\s*Executed (\d+) tests?, with (?:(\d+) (?:tests? )?skipped and )?(\d+) failures? \((\d+) unexpected\) in [\d.]+ \([\d.]+\) seconds\z/.match(lines[ends.first + 1].to_s)
    require!(footer && footer[1].to_i == expected.length && footer[2].to_i == 0 && footer[3].to_i == 0 && footer[4].to_i == 0, 'Mac footer has missing, skipped or failed coverage')
    expected
  end

  def self.mac_inventory(text)
    methods = text.lines.map(&:strip).select { |line| line.match?(/\A\w+\.\w+\/test\w+\z/) }
    require!(!methods.empty? && methods.uniq.length == methods.length, 'empty or duplicate Mac discovery')
    MAC_CLASSES.each { |name| require!(methods.any? { |id| id.start_with?(name + '/') }, "missing Mac test class: #{name}") }
    MAC_PINNED.each { |id| require!(methods.include?(id), "missing critical Mac test: #{id}") }
    methods.select { |id| MAC_CLASSES.include?(id.split('/').first) }.sort
  end

  def self.rust_inventory(text)
    methods = text.lines.map { |line| /\A([\w:]+): test\s*\z/.match(line)&.[](1) }.compact
    require!(!methods.empty? && methods.uniq.length == methods.length, 'empty or duplicate Rust discovery')
    RUST_PINNED.each { |id| require!(methods.include?(id), "missing critical Rust test: #{id}") }
    methods.sort
  end

  def self.validate_rust(text, expected)
    matches = text.lines.map { |line| /\A\s*test ([\w:]+) \.\.\. (ok|FAILED|ignored)\s*\z/.match(line) }.compact
    require!(matches.all? { |match| match[2] == 'ok' }, 'Rust test failed or was ignored')
    observed = matches.map { |match| match[1] }
    require!(!observed.empty? && observed.uniq.length == observed.length && observed.sort == expected.sort, 'missing, duplicate or zero Rust results')
    summaries = text.scan(/test result: ok\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;/)
    require!(!summaries.empty? && summaries.all? { |entry| entry.drop(1).all? { |number| number.to_i == 0 } } &&
             summaries.sum { |entry| entry[0].to_i } == expected.length, 'Rust result footer disagrees or contains ignored coverage')
    expected
  end

  def self.c_inventory(root)
    %w[Core Driver].map do |kind|
      name = kind == 'Core' ? 'OpensteamerVirtualAudioCoreTests.c' : 'OpensteamerVirtualMicrophoneDriverTests.c'
      text = File.read(File.join(root, 'macOS/VirtualAudioDriver/tests', name))
      array = text[/\}\s*tests\[\]\s*=\s*\{(.*?)\n\s*\};/m, 1]
      require!(array, 'missing native C behavioral inventory')
      names = array.scan(/\{\s*"([^"]+)"\s*,/).flatten
      require!(!names.empty? && names.uniq.length == names.length, 'empty or duplicate C behavioral inventory')
      label = kind == 'Core' ? 'core invariant' : 'driver interface'
      C_PINNED.fetch(label).each { |name| require!(names.include?(name), 'missing critical native C test: ' + name) }
      { 'kind' => label, 'names' => names }
    end
  end

  def self.validate_c(text, inventories, repetitions = 1)
    expected = inventories.flat_map do |inventory|
      names = inventory.fetch('names')
      names.map { |name| 'PASS: ' + name } + ["PASS: #{names.length}/#{names.length} production #{inventory.fetch('kind')} tests"]
    end * repetitions
    observed = text.lines.map(&:chomp).select { |line| line.start_with?('PASS: ') }
    require!(observed == expected, 'C behavioral results are missing, duplicated or incomplete')
    inventories
  end

  def self.tree_identity(path)
    entries = []
    Find.find(path) do |entry|
      stat = File.lstat(entry)
      require!(!stat.symlink? && (stat.file? || stat.directory?), 'artifact tree contains an unsupported node')
      relative = entry == path ? '.' : entry.delete_prefix(path + '/')
      entries << [relative, stat.directory? ? 'directory' : 'file', stat.mode & 0777, stat.file? ? sha(entry) : nil]
    end
    require!(entries.any? { |entry| entry[1] == 'file' }, 'artifact tree is empty')
    Digest::SHA256.hexdigest(JSON.generate(entries.sort))
  end

  def self.commands(root, directory, invocation, tools, simulator, mac_methods)
    exact_keys!(invocation, %w[developer_directory scratch swift_scratch timeout_seconds], 'invocation')
    developer = invocation.fetch('developer_directory')
    scratch = invocation.fetch('scratch')
    require!(developer.is_a?(String) && developer.start_with?('/') && scratch.is_a?(String) && scratch.start_with?('/') &&
             invocation['timeout_seconds'].is_a?(Integer) && (1..3600).cover?(invocation['timeout_seconds']), 'invalid invocation context')
    require!(directory.start_with?(scratch + '/validation-runs/microphone-'), 'receipt is outside its fresh invocation directory')
    swift_scratch = invocation.fetch('swift_scratch')
    require!([File.join(scratch, 'swift-build'), File.join(scratch, 'SwiftPM')].include?(swift_scratch), 'Swift cache escapes the dedicated scratch root')
    swift = File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swift')
    xcodebuild = File.join(developer, 'usr/bin/xcodebuild')
    require!(tools.key?(swift) && tools.key?(xcodebuild), 'recorded Xcode tools do not match invocation')
    cargo_candidates = tools.keys.select { |path| File.basename(path) == 'cargo' }
    require!(cargo_candidates.length == 1, 'ambiguous Cargo identity')
    cargo = cargo_candidates.first
    swift_base = [swift, 'test', '--package-path', root, '--scratch-path', swift_scratch, '--jobs', '2']
    filter = '^(?:' + mac_methods.map { |id| Regexp.escape(id) }.join('|') + ')$'
    result = File.join(directory, 'simulator.xcresult')
    app = File.join(directory, 'simulator-app/Beluga.app')
    sim = [xcodebuild, 'test', '-project', File.join(root, 'iOS/opensteamer/opensteamer.xcodeproj'), '-scheme', 'opensteamer', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + simulator, '-derivedDataPath', File.join(scratch, 'DerivedData'), '-resultBundlePath', result,
           '-parallel-testing-enabled', 'NO', '-jobs', '2', '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '90',
           '-maximum-test-execution-time-allowance', '90']
    sim += SIMULATOR_CLASSES.map { |name| '-only-testing:opensteamerTests/' + name }
    sim += ['DEVELOPMENT_TEAM=MSMG8CJLB3', 'CODE_SIGNING_ALLOWED=YES']
    driver = File.join(root, 'macOS/VirtualAudioDriver')
    make = ['/usr/bin/make', '-B', '-C', driver, 'BUILD_DIR=' + File.join(scratch, 'DriverBuild'), 'DEVELOPER_DIR=' + developer]
    bundles = [1, 2].map { |number| File.join(directory, 'driver-build-' + number.to_s, 'OpensteamerVirtualMicrophone.driver') }
    {
      'gate-self-tests' => ['/usr/bin/ruby', File.join(root, 'scripts/test-validate-microphone-regressions.rb')],
      'simulator-signing-self-tests' => ['/usr/bin/ruby', File.join(root, 'scripts/test-microphone-simulator-signing.rb'), '--verbose'],
      'release-hook-self-tests' => ['/usr/bin/ruby', File.join(root, 'scripts/test-microphone-release-gate.rb')],
      'host-release-hook-self-tests' => ['/usr/bin/ruby', File.join(root, 'scripts/test-microphone-host-release-gate.rb')],
      'product-identity' => ['/bin/zsh', File.join(root, 'scripts/check-product-identity.sh'), root],
      'product-identity-mutations' => ['/bin/zsh', File.join(root, 'scripts/test-product-identity.sh')],
      'rust-artifact-validation' => ['/usr/bin/ruby', File.join(root, 'scripts/microphone-regression-gate.rb'), '--verify-rust-artifact'],
      'mac-discovery' => swift_base + ['--list-tests'],
      'mac-tests' => swift_base + ['--skip-build', '--filter', filter, '--xunit-output', File.join(directory, 'mac-results.xml')],
      'simulator-tests' => sim,
      'simulator-summary' => ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', result, '--compact'],
      'simulator-results' => ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', result, '--compact'],
      'simulator-signature' => ['/usr/bin/codesign', '--verify', '--strict', app],
      'simulator-entitlements' => ['/usr/bin/ruby', File.join(root, 'scripts/microphone-simulator-signing.rb'), app],
      'rust-discovery' => [cargo, 'test', '--offline', '--locked', '--', '--list'],
      'rust-tests' => [cargo, 'test', '--offline', '--locked', '--', '--test-threads=1'],
      'driver-tests' => make + %w[test-core test-driver],
      'driver-sanitizers' => make + %w[test-sanitizers],
      'driver-diagnostic-reader' => make + %w[test-diagnostic-snapshot-reader],
      'driver-build-1' => [File.join(driver, 'scripts/build-driver.sh'), bundles[0]],
      'driver-build-2' => [File.join(driver, 'scripts/build-driver.sh'), bundles[1]],
      'driver-verifier' => [File.join(driver, 'scripts/verify-driver-bundle.sh'), bundles[0]],
      'driver-load' => [File.join(driver, 'scripts/test-built-driver-bundle.sh'), bundles[0]],
      'driver-malformed-bundles' => [File.join(driver, 'scripts/test-driver-bundle-verifier.sh'), bundles[0]]
    }
  end

  def self.validate_harness(text)
    summaries = text.lines.map { |line| /\A(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips\s*\z/.match(line) }.compact
    require!(summaries.length == 1 && summaries.first[1].to_i >= 41 && summaries.first[2].to_i >= summaries.first[1].to_i &&
             summaries.first.captures.drop(2).all? { |number| number.to_i == 0 }, 'gate behavioral harness has missing, failed or skipped coverage')
  end

  def self.validate_host_release_harness(text)
    require!(text.lines.map(&:chomp).count('microphone host release gate behavior tests passed') == 1, 'host release hook behavioral harness is incomplete')
  end

  SIMULATOR_SIGNING_PINNED = %w[
    test_wrong_thin_architecture_filetype_and_physical_platform_refuse
    test_missing_duplicate_and_malformed_load_commands_refuse
    test_duplicate_xml_keys_wrong_identifier_and_group_refuse
    test_canonical_der_changes_or_noncanonical_encoding_refuse
    test_code_directory_page_hash_and_unsigned_bytes_refuse
    test_collector_first_or_final_signature_failure_never_returns_record
    test_collector_detects_executable_or_info_mutation_at_every_tool_boundary
    test_collector_same_bytes_file_replacement_and_symlink_refuse
    test_collector_digest_pin_refuses_same_size_bytes_with_stat_times_masked
    test_collector_stat_pin_refuses_mode_change_with_unchanged_bytes
    test_replay_rejects_false_green_unknown_fields_paths_and_bounds
    test_production_api_has_no_executor_or_signature_skip_option
  ].freeze

  def self.simulator_signing_inventory(root)
    source = File.read(File.join(root, 'scripts/test-microphone-simulator-signing.rb'))
    methods = source.scan(/^\s*def (test\w+)(?:\(|\s|$)/).flatten
    require!(methods.uniq.length == methods.length && (SIMULATOR_SIGNING_PINNED - methods).empty?,
             'Simulator signing harness inventory is incomplete or duplicated')
    methods.sort
  end

  def self.validate_simulator_signing_harness(text, expected)
    cases = text.lines.map do |line|
      /\AMicrophoneSimulatorSigningTests#(test\w+) = [\d.]+ s = ([.SEF])\s*\z/.match(line)
    end.compact
    require!(cases.all? { |entry| entry[2] == '.' } && cases.map { |entry| entry[1] }.sort == expected,
             'Simulator signing behavioral results are absent, duplicated, failed or skipped')
    summaries = text.lines.map { |line| /\A(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips\s*\z/.match(line) }.compact
    require!(summaries.length == 1 && summaries.first[1].to_i == expected.length &&
             summaries.first[2].to_i >= expected.length && summaries.first.captures.drop(2).all? { |value| value.to_i == 0 } &&
             text.lines.map(&:chomp).count('microphone Simulator signing behavior tests passed') == 1,
             'Simulator signing harness footer or terminal marker is incomplete')
  end

  def self.validate_driver_load(text)
    lines = text.lines.map(&:chomp)
    required = ['VERIFIED_BUILT_DRIVER_BUNDLE_LOAD',
                'PASS: loaded production driver idle-registration pressure and exact PCM',
                'PASS: loaded driver pristine and retired idle contract mutations']
    require!(required.all? { |marker| lines.count(marker) == 1 }, 'driver load pressure and exact PCM oracle is incomplete')
  end

  def self.install_interrupt_handlers
    %w[INT TERM].each { |signal| Signal.trap(signal) { raise Interrupt } }
  end

  def self.validate_checksum_manifest(directory, manifest_path, required_paths)
    entries = File.readlines(manifest_path).map do |line|
      match = /\A([0-9a-f]{64}) [ *](.+)\n?\z/.match(line)
      require!(match, 'checksum manifest contains an invalid record')
      relative = match[2].sub(/\A\.\//, '')
      require!(!relative.start_with?('/') && !relative.split('/').include?('..'), 'checksum manifest escapes its source root')
      path = File.join(directory, relative)
      regular!(path)
      require!(sha(path) == match[1], 'Rust source or artifact checksum differs: ' + relative)
      relative
    end
    require!(entries.uniq.length == entries.length && entries.sort == required_paths.sort, 'Rust source or artifact manifest has missing, duplicate or unbound files')
  end

  def self.validate_rust_artifacts(root)
    crate = File.join(root, 'iOS/opensteamer/Rust/AudioTransactionAuthority')
    artifact = File.join(root, 'iOS/opensteamer/Frameworks/OpensteamerAudioTransactionAuthority.xcframework')
    source_manifest = File.join(crate, 'SOURCE_MANIFEST.sha256')
    # The checked-in build workflow must enroll additions in the source manifest
    # and rebuild the published artifact; never repair the manifest here.
    additional = %w[src include scripts tests].flat_map do |directory|
      Dir.glob(File.join(crate, directory, '**', '*')).select { |path| File.file?(path) }.map { |path| path.delete_prefix(crate + '/') }
    end
    validate_checksum_manifest(crate, source_manifest, (RUST_SOURCE_FILES + additional).uniq)
    require!(File.binread(source_manifest) == File.binread(File.join(artifact, 'SOURCE_MANIFEST.sha256')), 'Rust published source manifest is stale')
    paths = []
    Find.find(artifact) do |path|
      require!(!File.symlink?(path), 'Rust artifact contains a symlink')
      paths << path.delete_prefix(artifact + '/') if File.file?(path) && File.basename(path) != 'ARTIFACT_MANIFEST.sha256'
    end
    validate_checksum_manifest(artifact, File.join(artifact, 'ARTIFACT_MANIFEST.sha256'), paths)
    require!(paths.include?('ios-arm64/libopensteamer_audio_transaction_authority.a') &&
             paths.include?('ios-arm64_x86_64-simulator/libopensteamer_audio_transaction_authority-simulator.a'), 'Rust device or Simulator slice is missing')
  end

  class Executor
    def run(argv, environment, root, log, timeout)
      pid = Process.spawn(environment, *argv, chdir: root, out: log, err: [:child, :out], pgroup: true, unsetenv_others: true)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        result = Process.waitpid2(pid, Process::WNOHANG)
        if result
          pid = nil
          MicrophoneRegressionGate.require!(result[1].success?, "command exited unsuccessfully: #{argv.first}; inspect #{log}")
          return File.read(log)
        end
        MicrophoneRegressionGate.require!(Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline, "command exceeded deadline; inspect #{log}")
        sleep 0.05
      end
    ensure
      if pid
        begin
          Process.kill('TERM', -pid)
          sleep 0.15
          Process.kill('KILL', -pid)
        rescue Errno::ESRCH
        rescue Errno::EPERM
          # Darwin can leave only the exited group leader's zombie. Accept that
          # case only after reaping this exact owned child.
          reaped = Process.waitpid(pid, Process::WNOHANG)
          raise unless reaped == pid
        ensure
          begin
            Process.waitpid(pid)
          rescue Errno::ECHILD
          end
        end
      end
    end
  end

  class Runner
    attr_reader :evidence

    def initialize(root, options, executor = Executor.new)
      @root = File.realpath(root)
      @options = options
      @executor = executor
      @phases = []
    end

    def check_source
      MicrophoneRegressionGate.require!(MicrophoneRegressionGate.source_identity(@root) == @source, 'source changed during the invocation; use a fresh run')
    end

    def check_tools
      @tools.each { |path, digest| MicrophoneRegressionGate.require!(MicrophoneRegressionGate.sha(path) == digest, "tool identity changed: #{path}") }
    end

    def phase(name, argv, environment = @environment, root = @root)
      check_source
      check_tools
      log = File.join(@evidence, name + '.log')
      puts "microphone-regressions: #{name}; deadline #{@options.fetch(:timeout)}s; log #{log}"
      text = @executor.run(argv, environment, root, log, @options.fetch(:timeout))
      check_source
      check_tools
      @phases << { 'name' => name, 'argv' => argv, 'log' => File.basename(log), 'sha256' => MicrophoneRegressionGate.sha(log) }
      text
    end

    def artifact(name, path)
      { 'name' => name, 'path' => path.delete_prefix(@evidence + '/'), 'sha256' => File.directory?(path) ? MicrophoneRegressionGate.tree_identity(path) : MicrophoneRegressionGate.sha(path), 'tree' => File.directory?(path) }
    end

    def run
      MicrophoneRegressionGate.require!(RUBY_PLATFORM.include?('darwin'), 'this gate requires Darwin/macOS')
      simulator = @options.fetch(:simulator)
      MicrophoneRegressionGate.require!(simulator.match?(/\A[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\z/), 'select one explicit Simulator UUID')
      developer = ENV['DEVELOPER_DIR']
      MicrophoneRegressionGate.require!(developer && developer.start_with?('/') && File.directory?(developer), 'set DEVELOPER_DIR to the reviewed Xcode developer directory')
      developer = File.realpath(developer)
      xcodebuild = File.join(developer, 'usr/bin/xcodebuild')
      swift = File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swift')
      MicrophoneRegressionGate.require!(MicrophoneRegressionGate.sha(xcodebuild) == XCODEBUILD_SHA256, 'Xcode executable differs from reviewed pin')
      scratch = @options.fetch(:scratch)
      MicrophoneRegressionGate.require!(scratch.start_with?('/') && File.directory?(scratch) && !File.symlink?(scratch), 'scratch must be an existing absolute dedicated non-symlink cache')
      scratch = File.realpath(scratch)
      MicrophoneRegressionGate.require!(![Dir.home, '/', @root, developer].include?(scratch) && !@root.start_with?(scratch + '/') && !scratch.start_with?(@root + '/') &&
                                       PROTECTED_ROOTS.none? { |path| scratch == path || scratch.start_with?(path + '/') }, 'scratch overlaps a broad, source or protected runtime root')
      stat = File.stat(scratch)
      MicrophoneRegressionGate.require!(stat.uid == Process.uid && (stat.mode & 0777) == 0700, 'scratch must be owner-owned mode 0700')
      lock_path = File.join(scratch, '.microphone-regressions.lock')
      MicrophoneRegressionGate.require!(!File.symlink?(lock_path), 'scratch lock is a symlink')
      @lock = File.open(lock_path, File::RDWR | File::CREAT, 0600)
      MicrophoneRegressionGate.require!(@lock.stat.uid == Process.uid && @lock.stat.nlink == 1 && (@lock.stat.mode & 0777) == 0600 && @lock.flock(File::LOCK_EX | File::LOCK_NB), 'scratch lock is unsafe or held by another invocation')
      swift_child = File.exist?(File.join(scratch, 'swift-build')) ? 'swift-build' : 'SwiftPM'
      @swift_scratch = File.join(scratch, swift_child)
      ['validation-runs', 'DerivedData', swift_child, 'RustTarget', 'DriverBuild'].each do |child|
        path = File.join(scratch, child)
        MicrophoneRegressionGate.require!(!File.symlink?(path), 'cache child is a symlink')
        FileUtils.mkdir_p(path, mode: 0700)
        child_stat = File.stat(path)
        MicrophoneRegressionGate.require!(child_stat.directory? && child_stat.uid == Process.uid && [0700, 0755].include?(child_stat.mode & 0777), 'cache child is unsafe')
      end
      @evidence = Dir.mktmpdir('microphone-', File.join(scratch, 'validation-runs'))
      File.chmod(0700, @evidence)
      @source = MicrophoneRegressionGate.source_identity(@root)
      @environment = { 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME' => Dir.home, 'DEVELOPER_DIR' => developer,
                       'TMPDIR' => @evidence, 'LC_ALL' => 'C', 'CARGO_NET_OFFLINE' => 'true', 'RUSTUP_HOME' => RUSTUP_HOME, 'CARGO_HOME' => CARGO_HOME }
      clang = File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/clang')
      @tools = ([xcodebuild, swift, clang, '/usr/bin/make', '/usr/bin/ruby', '/usr/bin/xcrun'] +
                MicrophoneSimulatorSigning::DEPENDENCIES).uniq.map { |path| [path, MicrophoneRegressionGate.sha(path)] }.to_h
      node = MicrophoneRegressionGate.resolve_node
      @tools[node] = MicrophoneRegressionGate.sha(node)
      @environment['PATH'] = File.dirname(node) + ':' + @environment.fetch('PATH')
      version_log = File.join(@evidence, 'xcode-version.log')
      version = @executor.run([xcodebuild, '-version'], @environment, @root, version_log, 30)
      MicrophoneRegressionGate.require!(version == XCODE_VERSION, 'reviewed Xcode version/build changed')
      devices_log = File.join(@evidence, 'simulator-devices.json')
      devices_text = @executor.run(['/usr/bin/xcrun', 'simctl', 'list', 'devices', '--json'], @environment, @root, devices_log, 30)
      devices = MicrophoneRegressionGate.parse_json(devices_text, 'Simulator device inventory').fetch('devices').values.flatten
      matching = devices.select { |entry| entry['udid'].to_s.casecmp?(simulator) && entry['isAvailable'] == true }
      MicrophoneRegressionGate.require!(matching.length == 1, 'selected destination is not one available Simulator')
      rustup = File.join(CARGO_HOME, 'bin/rustup')
      rust_log = File.join(@evidence, 'rust-toolchain.log')
      cargo_path = @executor.run([rustup, 'which', '--toolchain', RUST_VERSION, 'cargo'], @environment, @root, rust_log, 30).strip
      MicrophoneRegressionGate.require!(cargo_path.start_with?('/') && File.executable?(cargo_path), 'pinned installed Rust toolchain is absent; do not install or upgrade it')
      cargo = File.realpath(cargo_path)
      rustc = File.join(File.dirname(cargo), 'rustc')
      @tools[cargo] = MicrophoneRegressionGate.sha(cargo)
      @tools[rustc] = MicrophoneRegressionGate.sha(rustc)
      rust_version_log = File.join(@evidence, 'rust-version.log')
      rust_version = @executor.run([rustc, '--version'], @environment, @root, rust_version_log, 30)
      MicrophoneRegressionGate.require!(rust_version.start_with?('rustc ' + RUST_VERSION + ' '), 'Rust compiler is not the pinned version')
      @environment['PATH'] = File.dirname(cargo) + ':' + @environment.fetch('PATH')
      @environment['RUSTUP_TOOLCHAIN'] = RUST_VERSION
      @environment['CARGO_TARGET_DIR'] = File.join(scratch, 'RustTarget')
      MicrophoneRegressionGate.validate_harness(phase('gate-self-tests', ['/usr/bin/ruby', File.join(@root, 'scripts/test-validate-microphone-regressions.rb')]))
      signing_tests = phase('simulator-signing-self-tests', ['/usr/bin/ruby', File.join(@root, 'scripts/test-microphone-simulator-signing.rb'), '--verbose'])
      MicrophoneRegressionGate.validate_simulator_signing_harness(signing_tests, MicrophoneRegressionGate.simulator_signing_inventory(@root))
      release_tests = phase('release-hook-self-tests', ['/usr/bin/ruby', File.join(@root, 'scripts/test-microphone-release-gate.rb')])
      MicrophoneRegressionGate.require!(release_tests.lines.map(&:chomp).count('microphone release gate behavior tests passed') == 1, 'release hook behavioral harness did not complete')
      host_release_tests = phase('host-release-hook-self-tests', ['/usr/bin/ruby', File.join(@root, 'scripts/test-microphone-host-release-gate.rb')])
      MicrophoneRegressionGate.validate_host_release_harness(host_release_tests)
      identity = phase('product-identity', ['/bin/zsh', File.join(@root, 'scripts/check-product-identity.sh'), @root])
      MicrophoneRegressionGate.require!(identity.lines.map(&:chomp).count('Beluga product identity check passed') == 1, 'product identity checker did not complete')
      identity_mutations = phase('product-identity-mutations', ['/bin/zsh', File.join(@root, 'scripts/test-product-identity.sh')])
      MicrophoneRegressionGate.require!(identity_mutations.lines.map(&:chomp).count('opensteamer product identity regression tests passed') == 1, 'product identity mutations did not complete')
      phase('rust-artifact-validation', ['/usr/bin/ruby', File.join(@root, 'scripts/microphone-regression-gate.rb'), '--verify-rust-artifact'])
      MicrophoneRegressionGate.validate_rust_artifacts(@root)
      swift_base = [swift, 'test', '--package-path', @root, '--scratch-path', @swift_scratch, '--jobs', '2']
      mac_methods = MicrophoneRegressionGate.mac_inventory(phase('mac-discovery', swift_base + ['--list-tests']))
      filter = '^(?:' + mac_methods.map { |id| Regexp.escape(id) }.join('|') + ')$'
      mac_xml = File.join(@evidence, 'mac-results.xml')
      mac_log = phase('mac-tests', swift_base + ['--skip-build', '--filter', filter, '--xunit-output', mac_xml])
      mac_format = File.file?(mac_xml) ? 'xunit' : 'darwin-xctest-log'
      if mac_format == 'xunit'
        MicrophoneRegressionGate.validate_xunit(File.read(mac_xml), mac_methods)
      else
        MicrophoneRegressionGate.validate_mac_log(mac_log, mac_methods)
      end
      sim_methods = MicrophoneRegressionGate.simulator_inventory(@root)
      result = File.join(@evidence, 'simulator.xcresult')
      sim_args = [xcodebuild, 'test', '-project', File.join(@root, 'iOS/opensteamer/opensteamer.xcodeproj'), '-scheme', 'opensteamer', '-configuration', 'Debug',
                  '-destination', 'platform=iOS Simulator,id=' + simulator, '-derivedDataPath', File.join(scratch, 'DerivedData'), '-resultBundlePath', result,
                  '-parallel-testing-enabled', 'NO', '-jobs', '2', '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '90',
                  '-maximum-test-execution-time-allowance', '90']
      sim_args.concat(SIMULATOR_CLASSES.map { |name| '-only-testing:opensteamerTests/' + name })
      sim_args.concat(['DEVELOPMENT_TEAM=MSMG8CJLB3', 'CODE_SIGNING_ALLOWED=YES'])
      phase('simulator-tests', sim_args)
      summary_text = phase('simulator-summary', ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', result, '--compact'])
      results_text = phase('simulator-results', ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', result, '--compact'])
      MicrophoneRegressionGate.validate_simulator(MicrophoneRegressionGate.parse_json(summary_text, 'Simulator summary'), MicrophoneRegressionGate.parse_json(results_text, 'Simulator results'), sim_methods, simulator)
      source_app = File.join(scratch, 'DerivedData/Build/Products/Debug-iphonesimulator/Beluga.app')
      app_identity = MicrophoneRegressionGate.tree_identity(source_app)
      retained_app_parent = File.join(@evidence, 'simulator-app')
      Dir.mkdir(retained_app_parent, 0700)
      FileUtils.cp_r(source_app, retained_app_parent, preserve: true)
      app = File.join(retained_app_parent, 'Beluga.app')
      MicrophoneRegressionGate.require!(MicrophoneRegressionGate.tree_identity(app) == app_identity &&
                                       MicrophoneRegressionGate.tree_identity(source_app) == app_identity,
                                       'signed Simulator app changed during its retained artifact copy')
      phase('simulator-signature', ['/usr/bin/codesign', '--verify', '--strict', app])
      entitlements = phase('simulator-entitlements', ['/usr/bin/ruby', File.join(@root, 'scripts/microphone-simulator-signing.rb'), app])
      MicrophoneSimulatorSigning.validate_record(MicrophoneRegressionGate.parse_json(entitlements, 'Simulator signed identity'), expected_app: app)
      crate = File.join(@root, 'iOS/opensteamer/Rust/AudioTransactionAuthority')
      rust_methods = MicrophoneRegressionGate.rust_inventory(phase('rust-discovery', [cargo, 'test', '--offline', '--locked', '--', '--list'], @environment, crate))
      MicrophoneRegressionGate.validate_rust(phase('rust-tests', [cargo, 'test', '--offline', '--locked', '--', '--test-threads=1'], @environment, crate), rust_methods)
      driver = File.join(@root, 'macOS/VirtualAudioDriver')
      c_methods = MicrophoneRegressionGate.c_inventory(@root)
      make_base = ['/usr/bin/make', '-B', '-C', driver, 'BUILD_DIR=' + File.join(scratch, 'DriverBuild'), 'DEVELOPER_DIR=' + developer]
      MicrophoneRegressionGate.validate_c(phase('driver-tests', make_base + %w[test-core test-driver]), c_methods)
      MicrophoneRegressionGate.validate_c(phase('driver-sanitizers', make_base + %w[test-sanitizers]), c_methods, 2)
      diagnostic = phase('driver-diagnostic-reader', make_base + %w[test-diagnostic-snapshot-reader])
      MicrophoneRegressionGate.require!(diagnostic.lines.map(&:chomp).include?('DIAGNOSTIC_SNAPSHOT_READER_TESTS_PASSED_WITHOUT_CORE_AUDIO_IO'), 'diagnostic reader self-test did not complete without Core Audio I/O')
      bundles = [1, 2].map do |number|
        parent = File.join(@evidence, 'driver-build-' + number.to_s)
        Dir.mkdir(parent, 0700)
        bundle = File.join(parent, 'OpensteamerVirtualMicrophone.driver')
        phase('driver-build-' + number.to_s, [File.join(driver, 'scripts/build-driver.sh'), bundle])
        bundle
      end
      MicrophoneRegressionGate.require!(MicrophoneRegressionGate.tree_identity(bundles[0]) == MicrophoneRegressionGate.tree_identity(bundles[1]), 'fresh universal driver builds differ')
      phase('driver-verifier', [File.join(driver, 'scripts/verify-driver-bundle.sh'), bundles[0]])
      load = phase('driver-load', [File.join(driver, 'scripts/test-built-driver-bundle.sh'), bundles[0]])
      MicrophoneRegressionGate.validate_driver_load(load)
      phase('driver-malformed-bundles', [File.join(driver, 'scripts/test-driver-bundle-verifier.sh'), bundles[0]])
      check_source
      check_tools
      artifacts = [artifact('simulator-result', result), artifact('driver-bundle-1', bundles[0]), artifact('driver-bundle-2', bundles[1])]
      artifacts << artifact('simulator-app', app)
      artifacts << artifact('mac-xunit', mac_xml) if File.file?(mac_xml)
      receipt = { 'schema' => SCHEMA, 'status' => 'passed', 'scope' => 'offline-source-only', 'root' => @root,
                  'created_at' => Time.now.to_i, 'source' => @source, 'tools' => @tools, 'simulator' => simulator,
                  'invocation' => { 'developer_directory' => developer, 'scratch' => scratch, 'swift_scratch' => @swift_scratch, 'timeout_seconds' => @options.fetch(:timeout) },
                  'mac_format' => mac_format, 'phases' => @phases, 'artifacts' => artifacts,
                  'coverage' => { 'mac' => mac_methods, 'simulator' => sim_methods, 'intentional_simulator_skips' => SIMULATOR_SKIPS,
                                  'rust' => rust_methods, 'c' => c_methods } }
      path = File.join(@evidence, 'receipt.json')
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(JSON.pretty_generate(receipt) + "\n"); file.flush; file.fsync }
      digest = MicrophoneRegressionGate.sha(path)
      MicrophoneRegressionGate.verify_receipt(path, digest, @root)
      puts "microphone-regressions: PASS (offline source evidence only); receipt #{path}; sha256 #{digest}"
      path
    ensure
      @lock.close if @lock
    end
  end

  def self.verify_receipt(path, expected_digest, root, now = Time.now.to_i)
    require!(path.start_with?('/') && expected_digest.match?(/\A[0-9a-f]{64}\z/), 'receipt requires an absolute path and independently retained SHA-256')
    stat = regular!(path)
    require!(stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0777) == 0600 && stat.size <= 8 * 1024 * 1024, 'receipt has unsafe owner, mode, links or size')
    parent = File.lstat(File.dirname(path))
    require!(parent.directory? && !parent.symlink? && parent.uid == Process.uid && (parent.mode & 0777) == 0700 &&
             File.realpath(File.dirname(path)) == File.dirname(path), 'receipt parent must be canonical, owner-owned and private mode 0700')
    require!(File.realpath(path) == path && sha(path) == expected_digest, 'receipt bytes or canonical path changed')
    receipt = parse_json(File.read(path), 'Receipt')
    exact_keys!(receipt, %w[schema status scope root created_at source tools simulator invocation mac_format phases artifacts coverage], 'receipt')
    require!(receipt['schema'] == SCHEMA && receipt['status'] == 'passed' && receipt['scope'] == 'offline-source-only' && receipt['root'] == File.realpath(root), 'wrong receipt identity or scope')
    require!(receipt['created_at'].is_a?(Integer) && receipt['created_at'] <= now && now - receipt['created_at'] <= 7 * 86400, 'future or expired receipt')
    require!(receipt['source'] == source_identity(root), 'receipt source identity is stale or changed')
    tools = receipt['tools']
    require!(tools.is_a?(Hash) && !tools.empty? && tools.any? { |tool, digest| tool.end_with?('/usr/bin/xcodebuild') && digest == XCODEBUILD_SHA256 } &&
             %w[swift clang make ruby xcrun codesign cargo rustc node].all? { |name| tools.keys.any? { |tool| File.basename(tool) == name } } &&
             tools.keys.count { |tool| File.basename(tool) == 'node' } == 1, 'receipt lacks reviewed tool identities')
    require!(MicrophoneSimulatorSigning::DEPENDENCIES.all? { |tool| tools.key?(tool) }, 'receipt lacks exact Simulator signing tool identities')
    tools.each { |tool, digest| require!(tool.start_with?('/') && sha(tool) == digest, 'receipt tool identity drifted') }
    phases = receipt['phases']
    require!(phases.is_a?(Array) && phases.map { |entry| entry['name'] } == PHASES, 'receipt has absent, duplicate or reordered phases')
    directory = File.dirname(path)
    read_phase = lambda do |name|
      entry = phases.find { |candidate| candidate['name'] == name }
      exact_keys!(entry, %w[name argv log sha256], 'phase')
      require!(entry['log'] == name + '.log' && entry['argv'].is_a?(Array) && !entry['argv'].empty? && entry['argv'].all? { |arg| arg.is_a?(String) }, 'invalid phase invocation')
      log = File.join(directory, entry['log'])
      regular!(log)
      require!(sha(log) == entry['sha256'], 'phase log was changed')
      File.read(log)
    end
    PHASES.each { |name| read_phase.call(name) }
    validate_harness(read_phase.call('gate-self-tests'))
    validate_simulator_signing_harness(read_phase.call('simulator-signing-self-tests'), simulator_signing_inventory(root))
    require!(read_phase.call('release-hook-self-tests').lines.map(&:chomp).count('microphone release gate behavior tests passed') == 1, 'release hook behavioral harness is incomplete')
    validate_host_release_harness(read_phase.call('host-release-hook-self-tests'))
    require!(read_phase.call('product-identity').lines.map(&:chomp).count('Beluga product identity check passed') == 1, 'product identity checker is incomplete')
    require!(read_phase.call('product-identity-mutations').lines.map(&:chomp).count('opensteamer product identity regression tests passed') == 1, 'product identity mutations are incomplete')
    validate_rust_artifacts(root)
    artifacts = receipt['artifacts']
    required_artifacts = %w[simulator-result driver-bundle-1 driver-bundle-2 simulator-app]
    required_artifacts << 'mac-xunit' if receipt['mac_format'] == 'xunit'
    require!(artifacts.is_a?(Array) && artifacts.map { |entry| entry['name'] } == required_artifacts, 'receipt artifacts are incomplete or duplicated')
    check_artifacts = lambda do
      artifacts.each do |entry|
        exact_keys!(entry, %w[name path sha256 tree], 'artifact')
        relative = entry['path']
        require!(relative.is_a?(String) && !relative.start_with?('/') && !relative.split('/').include?('..'), 'artifact escapes receipt directory')
        artifact_path = File.join(directory, relative)
        require!(File.realpath(artifact_path) == artifact_path, 'artifact path is not canonical')
        observed = entry['tree'] == true ? tree_identity(artifact_path) : sha(artifact_path)
        require!(observed == entry['sha256'], 'artifact bytes changed')
      end
    end
    check_artifacts.call
    coverage = receipt['coverage']
    exact_keys!(coverage, %w[mac simulator intentional_simulator_skips rust c], 'coverage')
    mac = mac_inventory(read_phase.call('mac-discovery'))
    require!(coverage['mac'] == mac, 'Mac coverage differs from discovery')
    expected_commands = commands(root, directory, receipt['invocation'], tools, receipt['simulator'], mac)
    phases.each { |entry| require!(entry['argv'] == expected_commands.fetch(entry['name']), 'phase command does not match canonical offline invocation: ' + entry['name']) }
    if receipt['mac_format'] == 'xunit'
      xml = artifacts.find { |entry| entry['name'] == 'mac-xunit' }
      validate_xunit(File.read(File.join(directory, xml['path'])), mac)
    else
      require!(receipt['mac_format'] == 'darwin-xctest-log', 'unrecognized Mac result format')
      validate_mac_log(read_phase.call('mac-tests'), mac)
    end
    sim = simulator_inventory(root)
    require!(coverage['simulator'] == sim && coverage['intentional_simulator_skips'] == SIMULATOR_SKIPS, 'Simulator coverage or skip contract changed')
    validate_simulator(parse_json(read_phase.call('simulator-summary'), 'Simulator summary'), parse_json(read_phase.call('simulator-results'), 'Simulator results'), sim, receipt['simulator'])
    rust = rust_inventory(read_phase.call('rust-discovery'))
    require!(coverage['rust'] == rust, 'Rust coverage differs from discovery')
    validate_rust(read_phase.call('rust-tests'), rust)
    native = c_inventory(root)
    require!(coverage['c'] == native, 'native inventory differs from source')
    validate_c(read_phase.call('driver-tests'), native)
    validate_c(read_phase.call('driver-sanitizers'), native, 2)
    require!(read_phase.call('driver-diagnostic-reader').lines.map(&:chomp).include?('DIAGNOSTIC_SNAPSHOT_READER_TESTS_PASSED_WITHOUT_CORE_AUDIO_IO'), 'diagnostic reader self-test is incomplete')
    require!(artifacts[1]['sha256'] == artifacts[2]['sha256'], 'universal driver builds differ')
    validate_driver_load(read_phase.call('driver-load'))
    require!(read_phase.call('driver-malformed-bundles').lines.map(&:chomp).include?('ALL_DRIVER_BUNDLE_VERIFIER_MUTATIONS_REJECTED'), 'driver malformed-bundle mutations are incomplete')
    sim_phase = phases.find { |entry| entry['name'] == 'simulator-tests' }['argv']
    require!(sim_phase.include?('platform=iOS Simulator,id=' + receipt['simulator']) && sim_phase.include?('DEVELOPMENT_TEAM=MSMG8CJLB3') && sim_phase.include?('CODE_SIGNING_ALLOWED=YES') &&
             SIMULATOR_CLASSES.all? { |name| sim_phase.include?('-only-testing:opensteamerTests/' + name) } &&
             sim_phase.none? { |arg| arg.start_with?('-skip-testing:') || arg == 'CODE_SIGNING_ALLOWED=NO' }, 'Simulator signing or whole-suite invocation changed')
    app = File.join(directory, 'simulator-app/Beluga.app')
    retained_app = artifacts.find { |entry| entry['name'] == 'simulator-app' }
    require!(retained_app['path'] == 'simulator-app/Beluga.app' && retained_app['tree'] == true,
             'Simulator signing evidence does not bind the retained app artifact')
    signed_record = parse_json(read_phase.call('simulator-entitlements'), 'Simulator signed identity')
    MicrophoneSimulatorSigning.validate_record(signed_record, expected_app: app)
    require!(MicrophoneSimulatorSigning.collect(app) == signed_record, 'retained Simulator signed identity changed')
    # Recollection invokes read-only tools. Fence the complete invocation again,
    # not just the main executable/Info bytes observed inside the collector.
    PHASES.each { |name| read_phase.call(name) }
    check_artifacts.call
    require!(receipt['source'] == source_identity(root), 'receipt source identity changed during verification')
    tools.each { |tool, digest| require!(sha(tool) == digest, 'receipt tool identity drifted during verification') }
    current = regular!(path)
    require!(current.nlink == 1 && MicrophoneSimulatorSigning.stat_record(current) == MicrophoneSimulatorSigning.stat_record(stat) &&
             File.realpath(path) == path && sha(path) == expected_digest, 'receipt bytes or filesystem identity changed during verification')
    require!(File.realpath(File.dirname(path)) == File.dirname(path) &&
             MicrophoneSimulatorSigning.stat_record(File.lstat(File.dirname(path))) == MicrophoneSimulatorSigning.stat_record(parent),
             'receipt parent identity changed during verification')
    receipt
  end

  def self.main(arguments)
    root = File.dirname(File.dirname(File.realpath(__FILE__)))
    if arguments == ['--verify-rust-artifact']
      validate_rust_artifacts(root)
      puts 'microphone-regressions: Rust source and published artifact checksums verified'
      return
    end
    if arguments == ['--help']
      puts 'DEVELOPER_DIR=/reviewed/Xcode.app/Contents/Developer scripts/validate-microphone-regressions.sh --scratch-path /existing/private/cache --simulator-udid UUID [--timeout-seconds 1..3600]'
      puts 'scripts/validate-microphone-regressions.sh --verify-receipt /absolute/receipt.json --receipt-sha256 independently-retained-sha256'
      puts 'Runs every offline microphone phase for every feature; preserves dedicated caches and creates fresh evidence. Does not prove physical audio, paired reconnect, installed driver, or deployment.'
      return
    end
    options = { timeout: 1800 }
    seen = Set.new
    until arguments.empty?
      key = arguments.shift
      require!(!seen.include?(key), 'duplicate option')
      seen << key
      require!(%w[--scratch-path --simulator-udid --timeout-seconds --verify-receipt --receipt-sha256].include?(key), 'unknown option')
      value = arguments.shift
      require!(value && !value.start_with?('--'), 'missing option value')
      case key
      when '--scratch-path' then options[:scratch] = value
      when '--simulator-udid' then options[:simulator] = value
      when '--verify-receipt' then options[:receipt] = value
      when '--receipt-sha256' then options[:digest] = value
      when '--timeout-seconds'
        require!(value.match?(/\A\d+\z/) && (1..3600).cover?(value.to_i), 'deadline must be 1 through 3600 seconds')
        options[:timeout] = value.to_i
      end
    end
    if options[:receipt]
      require!(seen.sort == %w[--receipt-sha256 --verify-receipt].sort, 'receipt verification accepts only receipt and digest')
      verify_receipt(options.fetch(:receipt), options.fetch(:digest), root)
      puts 'microphone-regressions: receipt verified for current source and tools (offline source evidence only)'
    else
      require!(options[:scratch] && options[:simulator] && !options[:digest], 'select explicit scratch and Simulator; receipt digest is verification-only')
      Runner.new(root, options).run
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    $stdout.sync = true
    MicrophoneRegressionGate.install_interrupt_handlers
    MicrophoneRegressionGate.main(ARGV.dup)
  rescue Interrupt
    warn 'microphone-regressions: FAIL: interrupted; owned subprocesses terminated'
    exit 130
  rescue StandardError => error
    warn 'microphone-regressions: FAIL: ' + error.message
    exit 1
  end
end
