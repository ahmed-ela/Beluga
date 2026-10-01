#!/usr/bin/env ruby
# Offline compilation/evaluator checks only. This runner never opens audio.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

tooling = File.realpath(File.join(__dir__, '../..'))
product = '/Volumes/t7/beluga-quality-step.idpzQO/source'
developer = '/Volumes/t7/opensteamer-space-recovery-20260804/nonrepo/Xcode-26.6.0.app/Contents/Developer'
source = File.join(tooling, 'iOS/opensteamer/scripts/physical-blackhole-microphone-probe.swift')
decoder = File.join(product, 'macOS/Sources/CaptureServer/WorldwideVirtualMicrophoneDriverIdle.swift')
expected_decoder = 'fd108f745f4d8b78208d63f639c612c721e376df1d1fff12a85613e3e82792f8'
raise 'immutable production decoder changed' unless Digest::SHA256.file(decoder).hexdigest == expected_decoder
env = { 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME' => '/var/empty',
        'DEVELOPER_DIR' => developer, 'LC_ALL' => 'en_US.UTF-8' }
run = lambda do |*argv|
  output, status = Open3.capture2e(env, *argv, unsetenv_others: true)
  raise "offline command failed #{status.exitstatus}: #{output.byteslice(0, 8192)}" unless status.success?
  output
end
raise 'product commit differs' unless run.call('/usr/bin/git', '-C', product, 'rev-parse', 'HEAD').strip == '168036d74e08e7b49aad37907cf9b84b5dcc8456'
raise 'product is not clean' unless run.call('/usr/bin/git', '-C', product, 'status', '--porcelain').empty?
swiftc = File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
sdk = run.call('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path').strip
build = Dir.mktmpdir('beluga-v9-public-proof-offline.', '/private/tmp')
File.chmod(0o700, build)
main = File.join(build, 'main.swift')
FileUtils.cp(source, main)
common = [swiftc, '-sdk', sdk, '-swift-version', '5', '-O', '-D', 'BELUGA_MICROPHONE_V9_ORACLE', main, decoder,
          '-framework', 'CoreAudio', '-framework', 'AudioToolbox', '-framework', 'CryptoKit']
binary = File.join(build, 'public-proof')
run.call(*common, '-o', binary)
test_binary = File.join(build, 'epoch-tests')
run.call(*common, '-D', 'BELUGA_MICROPHONE_V9_ORACLE_SELF_TEST', '-o', test_binary)
epoch_output = run.call(test_binary)
epoch_tests = epoch_output.match(/V9_EPOCH_PROOF_OFFLINE_TESTS_PASS (\d+)\/\1 liveQueries=0/)&.captures&.first&.to_i
raise 'epoch fixture/mutation coverage failed' unless epoch_tests && epoch_tests >= 32

output, status = Open3.capture2e(env, binary, 'mirror-loopback-v9', '--fixture', 'not-allowed', unsetenv_others: true)
raise 'production v9 CLI admitted fixture input' unless status.exitstatus == 64 && output.empty?
healthy_paths = []
%w[visible-first hidden-first].each do |order|
  nonce = 'a' * 64 + ':' + order
  path = File.join(build, "#{order}.json")
  run.call(binary, 'mirror-loopback-self-test', '--case', 'healthy', '--nonce', nonce,
           '--required-headroom-seconds', '60', '--result', path)
  result = JSON.parse(File.binread(path))
  raise 'existing complete waveform baseline failed' unless result.fetch('status') == 'passed' &&
    result.fetch('challenge').fetch('expectedPCMHash') == result.fetch('challenge').fetch('capturedAlignedPCMHash')
  healthy_paths << path
end
%w[bit-flip dropped-frame duplicated-frame gain-change post-roll-noise frozen-device-time default-notification listener-remove].each do |mutation|
  path = File.join(build, "mutant-#{mutation}.json")
  _, status = Open3.capture2e(env, binary, 'mirror-loopback-self-test', '--case', mutation,
                            '--nonce', 'a' * 64 + ':visible-first', '--required-headroom-seconds', '60',
                            '--result', path, unsetenv_others: true)
  raise "existing waveform oracle accepted #{mutation}" unless status.exitstatus == 1 && JSON.parse(File.binread(path)).fetch('status') == 'failed'
end
raise 'copied source changed' unless Digest::SHA256.file(source).hexdigest == Digest::SHA256.file(main).hexdigest
raise 'product changed during offline tests' unless Digest::SHA256.file(decoder).hexdigest == expected_decoder &&
  run.call('/usr/bin/git', '-C', product, 'status', '--porcelain').empty?
contract_output = run.call('/usr/bin/ruby', File.join(__dir__, 'test-opensteamer-microphone-v9-public-proof-contract.rb'), build)
raise 'independent parser/mutation suite failed' unless contract_output.include?('0 failures, 0 errors, 0 skips')
proof = { 'schema' => 'beluga.microphone.public-proof.offline.v1', 'liveQueriesPerformed' => false,
          'sourceSHA256' => Digest::SHA256.file(source).hexdigest, 'decoderSHA256' => expected_decoder,
          'compiler' => swiftc, 'sdk' => sdk, 'binary' => binary, 'binarySHA256' => Digest::SHA256.file(binary).hexdigest,
          'nativeEpochTests' => epoch_tests, 'productionCLIRefusals' => 1, 'waveformBaselines' => healthy_paths,
          'waveformMutants' => 8, 'independentParserOutput' => contract_output }
File.write(File.join(build, 'proof.json'), JSON.pretty_generate(proof) + "\n", mode: 'wx', perm: 0o600)
puts JSON.pretty_generate(proof)
