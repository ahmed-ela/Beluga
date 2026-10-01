#!/usr/bin/env ruby
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# Builds the actual production helper and a separate offline test executable.
# No fixture, skip, or test switch is compiled into the production CLI.
ROOT = File.realpath(File.dirname(__FILE__))
PRODUCT = '/Volumes/t7/beluga-quality-step.idpzQO/source'
EXPECTED_COMMIT = '168036d74e08e7b49aad37907cf9b84b5dcc8456'
DECODER = File.join(PRODUCT, 'macOS/Sources/CaptureServer/WorldwideVirtualMicrophoneDriverIdle.swift')
INCLUDE = File.join(PRODUCT, 'macOS/VirtualAudioDriver/include')

def run!(*arguments)
  output, status = Open3.capture2e(*arguments)
  puts output unless output.empty?
  raise "command failed (#{status.exitstatus}): #{arguments.first}" unless status.success?
  output.strip
end

raise 'source commit changed' unless run!('/usr/bin/git', '-C', PRODUCT, 'rev-parse', 'HEAD') == EXPECTED_COMMIT
raise 'product source is not immutable clean' unless run!('/usr/bin/git', '-C', PRODUCT, 'status', '--porcelain').empty?
sources = [DECODER, File.join(INCLUDE, 'OpensteamerVirtualMicrophoneDriver.h'),
           File.join(PRODUCT, 'macOS/VirtualAudioDriver/tests/VirtualMicrophoneDiagnosticFixture.c'),
           File.join(PRODUCT, 'macOS/VirtualAudioDriver/tests/VirtualMicrophoneDiagnosticV2Fixture.c')]
before = sources.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
helper_sources = %w[BelugaMicrophoneIdleProof.swift BelugaMicrophoneEndpointContract.swift main.swift
                    BelugaMicrophonePristineFixture.c BelugaMicrophoneIdleProofTests.swift test-beluga-microphone-idle-proof.rb]
helper_before = helper_sources.to_h { |name| [name, Digest::SHA256.file(File.join(ROOT, name)).hexdigest] }
swiftc = run!('/usr/bin/xcrun', '--find', 'swiftc')
clang = run!('/usr/bin/xcrun', '--find', 'clang')
sdk = run!('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path')
build = Dir.mktmpdir('beluga-microphone-idle-native.')
File.chmod(0o700, build)
fixture_sources = [sources[2], sources[3], File.join(ROOT, 'BelugaMicrophonePristineFixture.c')]
fixtures = fixture_sources.each_with_index.map do |source, index|
  binary = File.join(build, "fixture-#{index + 1}")
  run!(clang, '-std=c11', '-Wall', '-Wextra', '-Werror', '-isysroot', sdk, '-I', INCLUDE, source,
       '-framework', 'CoreAudio', '-framework', 'CoreFoundation', '-o', binary)
  binary
end
common = [swiftc, '-sdk', sdk, '-swift-version', '6', '-warnings-as-errors', '-O', DECODER,
          File.join(ROOT, 'BelugaMicrophoneIdleProof.swift'), File.join(ROOT, 'BelugaMicrophoneEndpointContract.swift'),
          '-framework', 'CoreAudio', '-framework', 'CryptoKit']
helper = File.join(build, 'beluga-microphone-idle-proof')
run!(*common, File.join(ROOT, 'main.swift'), '-o', helper)
tests = File.join(build, 'beluga-microphone-idle-proof-tests')
run!(*common, File.join(ROOT, 'BelugaMicrophoneIdleProofTests.swift'), '-o', tests)
test_output = run!(tests, *fixtures)
test_count = test_output[/PASS (\d+)\/\1 native offline tests/, 1]
raise 'missing actual native test terminal' unless test_count

# Actual CLI rejection is exercised, without giving it a live query command.
output, status = Open3.capture2e(helper, '--fixture', '/tmp/not-readable')
raise 'production CLI accepted test mode' unless status.exitstatus == 64 && JSON.parse(output)['kind'] == 'REFUSED'
raise 'production source changed during test' unless before.all? { |path, sha| Digest::SHA256.file(path).hexdigest == sha }
raise 'helper source changed during build/test' unless helper_before.all? { |name, sha| Digest::SHA256.file(File.join(ROOT, name)).hexdigest == sha }
raise 'product commit changed during test' unless run!('/usr/bin/git', '-C', PRODUCT, 'rev-parse', 'HEAD') == EXPECTED_COMMIT
raise 'product dirtied during test' unless run!('/usr/bin/git', '-C', PRODUCT, 'status', '--porcelain').empty?
report = { 'contract' => 'beluga.microphone.passive-idle.build.v1', 'productCommit' => EXPECTED_COMMIT,
           'productSources' => before, 'helperSources' => helper_before, 'swiftc' => swiftc, 'clang' => clang, 'sdk' => sdk, 'helper' => helper,
           'helperSHA256' => Digest::SHA256.file(helper).hexdigest,
           'testBinary' => tests, 'nativeTests' => Integer(test_count), 'productionCLIRejection' => 'PASS',
           'liveQueriesPerformed' => false }
File.write(File.join(build, 'build-proof.json'), JSON.pretty_generate(report) + "\n", mode: 'wx', perm: 0o600)
puts JSON.pretty_generate(report)
