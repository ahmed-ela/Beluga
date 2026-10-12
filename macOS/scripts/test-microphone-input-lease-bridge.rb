#!/usr/bin/env ruby
# Actual-C copied-scalar bridge only. No host, CoreAudio, device or native shim.
# Proposed canonical path: macOS/scripts/test-microphone-input-lease-bridge.rb
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'timeout'
require_relative '../../shared/Rust/BelugaCore/scripts/artifact_support'

class OwnedInputLeaseBridgeOutputLimit < StandardError; end

def capture_owned_bridge(env, *argv)
  output = +''
  status = nil
  refused = false
  Open3.popen2e(env, *argv, pgroup: true) do |input, stream, waiter|
    input.close
    begin
      Timeout.timeout(180) do
        begin
          loop do
            chunk = stream.readpartial(16_384)
            remaining = 8_388_608 - output.bytesize
            if chunk.bytesize > remaining
              output << chunk.byteslice(0, remaining)
              raise OwnedInputLeaseBridgeOutputLimit
            end
            output << chunk
          end
        rescue EOFError
          status = waiter.value
        end
      end
    rescue Timeout::Error
      refused = true
      output << "\nOwned input-lease bridge phase timed out\n"
    rescue OwnedInputLeaseBridgeOutputLimit
      refused = true
      output << "\nOwned input-lease bridge phase exceeded its output limit\n"
    ensure
      if refused || waiter.alive?
        Process.kill('TERM', -waiter.pid) rescue Errno::ESRCH
        waiter.join(2)
        begin
          Process.kill(0, -waiter.pid)
          Process.kill('KILL', -waiter.pid) rescue Errno::ESRCH
        rescue Errno::ESRCH
          # Only this invocation's owned group is eligible for retirement.
        end
        waiter.join
      end
      status ||= waiter.value
    end
  end
  [output, status, refused]
end

EXPECTED_INPUT_LEASE_METHODS = %w[
  testInputLeaseLiteralLayoutsAndAllFourCopiedOperations
  testInputLeaseNativeIntegerBoundaryAndNoSuccessfulSwiftFallback
  testInputLeaseWholeResultRejectsEveryFieldAndCoherentWrongAction
  testInputLeaseMalformedFactsRemainRefusedEvenWithCanonicalInvalidResult
].sort.freeze

raise 'Usage: test-microphone-input-lease-bridge.rb VERIFIED_XCFRAMEWORK' unless ARGV.length == 1
root = File.expand_path('../..', __dir__)
artifact = File.realpath(ARGV.fetch(0))
framework = File.join(artifact, 'macos-arm64/BelugaCore.framework')
artifact_files = BelugaCoreArtifact::ARTIFACT_FILES + ['ARTIFACT_MANIFEST.sha256']
bridge = File.join(root, 'macOS/Sources/CaptureServer/BelugaRustMicrophoneInputLease.swift')
tests = File.join(root, 'macOS/Tests/CaptureServerTests/BelugaRustMicrophoneInputLeaseTests.swift')
main = File.join(root, 'macOS/scripts/microphone-input-lease-bridge-fixture/main.swift')
runner = File.join(root, 'macOS/scripts/test-microphone-input-lease-bridge.rb')
sources = [bridge, tests, main, runner]
raise 'Bridge source missing or linked' unless sources.all? { |path| File.file?(path) && !File.symlink?(path) }
raise 'Runner is not the adopted canonical source' unless File.realpath(__FILE__) == runner
raise 'Unexpected Xcode path' unless ENV.fetch('DEVELOPER_DIR', BelugaCoreArtifact::DEVELOPER) == BelugaCoreArtifact::DEVELOPER
tool = File.join(BelugaCoreArtifact::DEVELOPER, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
test_frameworks = File.join(BelugaCoreArtifact::DEVELOPER, 'Platforms/MacOSX.platform/Developer/Library/Frameworks')
test_libraries = File.join(BelugaCoreArtifact::DEVELOPER, 'Platforms/MacOSX.platform/Developer/usr/lib')
shared_frameworks = File.expand_path('../SharedFrameworks', BelugaCoreArtifact::DEVELOPER)
tool_paths = [tool, '/usr/bin/xcrun', File.join(test_frameworks, 'XCTest.framework/XCTest'),
  File.join(test_libraries, 'libXCTestSwiftSupport.dylib')]
tools = tool_paths.to_h { |path| [path, File.realpath(path)] }
fenced_paths = (sources + tools.values +
  artifact_files.map { |path| File.join(artifact, path) } +
  (BelugaCoreArtifact::SOURCE_FILES + ['SOURCE_MANIFEST.sha256']).map { |path| File.join(BelugaCoreArtifact::CRATE, path) }).uniq
before = fenced_paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
raise 'Artifact is not the current source' unless File.binread(File.join(artifact, 'SOURCE_MANIFEST.sha256')) ==
  File.binread(File.join(BelugaCoreArtifact::CRATE, 'SOURCE_MANIFEST.sha256'))
BelugaCoreArtifact.verify_source!
raise 'Artifact inventory differs' unless BelugaCoreArtifact.files(artifact) == artifact_files.sort
raise 'Artifact manifest differs' unless File.binread(File.join(artifact, 'ARTIFACT_MANIFEST.sha256')) ==
  BelugaCoreArtifact.manifest(artifact, BelugaCoreArtifact::ARTIFACT_FILES)
original_tests = File.binread(tests)
methods = original_tests.scan(/^    func (test\w+)\(/).flatten.sort
raise 'Four exact unique bridge methods required' unless methods == EXPECTED_INPUT_LEASE_METHODS && methods.uniq == methods
raise 'Expected exactly one native-target import' unless original_tests.scan(/^@testable import CaptureServer\n/).length == 1
projected_tests = original_tests.sub(/^@testable import CaptureServer\n/, '')
EXPECTED_INPUT_LEASE_METHODS.each do |method|
  needle = "    func #{method}("
  raise 'Method declaration is ambiguous' unless projected_tests.scan(Regexp.new(Regexp.escape(needle))).length == 1
  projected_tests = projected_tests.sub(needle, "    @objc func #{method}(")
end
raise 'Unexpected framework import in isolated sources' if [File.binread(bridge), projected_tests, File.binread(main)].any? { |text|
  text.match?(/^(?:@testable )?import (?:CaptureServer|CaptureCore|CoreAudio|AudioToolbox|AppKit|WebRTC)\b/)
}
scratch_parent = File.join(BelugaCoreArtifact::CRATE, 'target')
raise 'Scratch parent missing or linked' unless File.directory?(scratch_parent) && !File.symlink?(scratch_parent)
scratch = Dir.mktmpdir('microphone-input-lease-bridge-', scratch_parent)
File.chmod(0o700, scratch)
projected = File.join(scratch, 'BelugaRustMicrophoneInputLeaseTests.swift')
File.binwrite(projected, projected_tests)
env = { 'DEVELOPER_DIR' => BelugaCoreArtifact::DEVELOPER, 'LC_ALL' => 'C',
  'DYLD_INSERT_LIBRARIES' => nil, 'DYLD_LIBRARY_PATH' => nil, 'DYLD_FRAMEWORK_PATH' => nil }
sdk, sdk_status, sdk_refused = capture_owned_bridge(env, '/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path')
raise "SDK lookup failed: #{scratch}" unless sdk_status.success? && !sdk_refused
sdk = sdk.strip
raise 'SDK lookup returned an invalid path' unless sdk.start_with?(BelugaCoreArtifact::DEVELOPER + '/') &&
  !sdk.include?("\n") && File.directory?(sdk)
sdk_settings = File.join(sdk, 'SDKSettings.json')
before[sdk_settings] = Digest::SHA256.file(sdk_settings).hexdigest
fenced_paths << sdk_settings
common = [tool, '-D', 'BELUGA_MIC_INPUT_LEASE_BRIDGE_FIXTURE', '-sdk', sdk,
  '-target', 'arm64-apple-macos13.0', '-F', File.dirname(framework), '-framework', 'BelugaCore',
  '-F', test_frameworks, '-Xlinker', '-rpath', '-Xlinker', test_frameworks,
  '-I', test_libraries, '-L', test_libraries, '-lXCTestSwiftSupport',
  '-Xlinker', '-rpath', '-Xlinker', test_libraries,
  '-Xlinker', '-rpath', '-Xlinker', shared_frameworks]
debug = File.join(scratch, 'microphone-input-lease-bridge-debug')
release = File.join(scratch, 'microphone-input-lease-bridge-release')
debug_argv = [*common, '-D', 'DEBUG', '-Onone', bridge, projected, main, '-o', debug]
release_argv = [*common, '-O', bridge, main, '-o', release]
compiled, compile_status, compile_refused = capture_owned_bridge(env, *debug_argv)
File.binwrite(File.join(scratch, 'debug-compile.log'), compiled)
raise "Debug bridge compilation failed: #{scratch}" unless compile_status.success? && !compile_refused
release_output, release_status, release_refused = capture_owned_bridge(env, *release_argv)
File.binwrite(File.join(scratch, 'release-compile.log'), release_output)
raise "Release bridge compilation failed: #{scratch}" unless release_status.success? && !release_refused
raise 'Projected test bytes changed during compilation' unless File.binread(projected) == projected_tests
debug_digest = Digest::SHA256.file(debug).hexdigest
release_digest = Digest::SHA256.file(release).hexdigest
output, status, test_refused = capture_owned_bridge(env, debug)
File.binwrite(File.join(scratch, 'tests.log'), output)
started = output.scan(/^MIC_INPUT_LEASE_XCTEST_STARTED (test\w+)$/).flatten.sort
finished = output.scan(/^MIC_INPUT_LEASE_XCTEST_FINISHED (test\w+)$/).flatten.sort
apple_started = output.scan(/^Test Case '-\[(?:[A-Za-z_]\w*\.)?BelugaRustMicrophoneInputLeaseTests (test\w+)\]' started\.$/).flatten.sort
apple_passed = output.scan(/^Test Case '-\[(?:[A-Za-z_]\w*\.)?BelugaRustMicrophoneInputLeaseTests (test\w+)\]' passed \(/).flatten.sort
counter = 'MIC_INPUT_LEASE_XCTEST_COUNTS cases=4 executions=4 skipped=0 failures=0'
without_zero_counter = output.lines.reject { |line| line.chomp == counter }.join
BelugaCoreArtifact.verify_source!
final_inventory = BelugaCoreArtifact.files(artifact) == artifact_files.sort
final_manifest = File.binread(File.join(artifact, 'ARTIFACT_MANIFEST.sha256')) ==
  BelugaCoreArtifact.manifest(artifact, BelugaCoreArtifact::ARTIFACT_FILES)
source_unchanged = before == fenced_paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
tools_unchanged = tools.all? { |path, real| File.realpath(path) == real }
executable_unchanged = Digest::SHA256.file(debug).hexdigest == debug_digest &&
  Digest::SHA256.file(release).hexdigest == release_digest && File.binread(projected) == projected_tests
passed = status.success? && !test_refused && started == EXPECTED_INPUT_LEASE_METHODS &&
  finished == EXPECTED_INPUT_LEASE_METHODS && apple_started == EXPECTED_INPUT_LEASE_METHODS &&
  apple_passed == EXPECTED_INPUT_LEASE_METHODS && output.lines.count { |line| line.chomp == counter } == 1 &&
  output.include?('Executed 4 tests, with 0 failures') && !without_zero_counter.match?(/\bskipped\b|\bfailed\b/i) &&
  final_inventory && final_manifest && source_unchanged && tools_unchanged && executable_unchanged
result = { schema: 'beluga.microphone-input-lease.bridge-qualifier.v1',
  scope: 'actual-C copied-scalar bridge; no native lease or effect execution', passed: passed,
  expected: EXPECTED_INPUT_LEASE_METHODS, started: started, finished: finished,
  apple_started: apple_started, apple_passed: apple_passed, source_sha256: before,
  archive_sha256: Digest::SHA256.file(File.join(framework, 'BelugaCore')).hexdigest,
  projected_test_sha256: Digest::SHA256.hexdigest(projected_tests),
  debug_executable_sha256: debug_digest, release_executable_sha256: release_digest,
  debug_compile_argv: debug_argv, release_compile_argv: release_argv,
  release_executed: false, native_or_device_proof: false, deployment_proof: false }
File.binwrite(File.join(scratch, 'RESULT.json'), JSON.pretty_generate(result) + "\n")
puts output
raise "Input-lease bridge qualifier refused: #{scratch}" unless passed
puts "MIC_INPUT_LEASE_BRIDGE_QUALIFIER_PASS #{scratch}"
