#!/usr/bin/env ruby
# Pure scalar/bridge parity only. No CaptureServer, browser, phone or audio effects.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'timeout'
require_relative '../../shared/Rust/BelugaCore/scripts/artifact_support'

class OwnedParityOutputLimit < StandardError; end

def capture_owned(env, *argv)
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
              raise OwnedParityOutputLimit
            end
            output << chunk
          end
        rescue EOFError
          status = waiter.value
        end
      end
    rescue Timeout::Error
      refused = true
      output << "\nOwned pure parity phase timed out\n"
    rescue OwnedParityOutputLimit
      refused = true
      output << "\nOwned pure parity phase exceeded its output limit\n"
    ensure
      if refused || waiter.alive?
        Process.kill('TERM', -waiter.pid) rescue Errno::ESRCH
        waiter.join(2)
        begin
          Process.kill(0, -waiter.pid)
          Process.kill('KILL', -waiter.pid) rescue Errno::ESRCH
        rescue Errno::ESRCH
          # The owned group already retired after TERM.
        end
        waiter.join
      end
      status ||= waiter.value
    end
  end
  [output, status, refused]
end

raise 'Usage: test-handoff-source-parity.rb VERIFIED_XCFRAMEWORK' unless ARGV.length == 1
root = File.expand_path('../..', __dir__)
artifact = File.realpath(ARGV.fetch(0))
framework = File.join(artifact, 'macos-arm64/BelugaCore.framework')
artifact_files = BelugaCoreArtifact::ARTIFACT_FILES + ['ARTIFACT_MANIFEST.sha256']
sources = %w[
  macOS/Sources/CaptureServer/BelugaRustMacChromeHandoffSourcePolicy.swift
  macOS/Sources/CaptureServer/MacChromeHandoffPauseCondition.swift
  macOS/Tests/CaptureServerTests/BelugaRustMacChromeHandoffSourcePolicyTests.swift
  macOS/scripts/handoff-source-parity-fixture/Snapshots.swift
  macOS/scripts/handoff-source-parity-fixture/main.swift
].map { |path| File.join(root, path) }
raise 'Fixture source missing or linked' unless sources.all? { |path| File.file?(path) && !File.symlink?(path) }
fenced_paths = sources + [File.join(root, 'macOS/Sources/CaptureServer/MacChromeAppleEventsBackend.swift')] +
  artifact_files.map { |path| File.join(artifact, path) } +
  (BelugaCoreArtifact::SOURCE_FILES + ['SOURCE_MANIFEST.sha256']).map { |path| File.join(BelugaCoreArtifact::CRATE, path) }
before = fenced_paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
raise 'Artifact is not the current source' unless File.binread(File.join(artifact, 'SOURCE_MANIFEST.sha256')) ==
  File.binread(File.join(BelugaCoreArtifact::CRATE, 'SOURCE_MANIFEST.sha256'))
BelugaCoreArtifact.verify_source!
raise 'Artifact inventory differs' unless BelugaCoreArtifact.files(artifact) == artifact_files.sort
raise 'Artifact manifest differs' unless File.binread(File.join(artifact, 'ARTIFACT_MANIFEST.sha256')) ==
  BelugaCoreArtifact.manifest(artifact, BelugaCoreArtifact::ARTIFACT_FILES)
parser = File.binread(File.join(root, 'macOS/Sources/CaptureServer/MacChromeAppleEventsBackend.swift'))
  .match(/^    static func videoID\(from value: String\) -> String\? \{.*?^    \}/m)&.[](0)
raise 'Snapshot fixture parser drifted' unless parser && File.binread(sources[3]).include?(parser)
expected = File.binread(sources[2]).scan(/^    func (test\w+)\(/).flatten.sort
raise 'Nine unique parity methods required' unless expected.length == 9 && expected.uniq == expected
scratch = Dir.mktmpdir('handoff-source-parity-', File.join(BelugaCoreArtifact::CRATE, 'target'))
File.chmod(0o700, scratch)
tool = File.join(BelugaCoreArtifact::DEVELOPER, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
env = { 'DEVELOPER_DIR' => BelugaCoreArtifact::DEVELOPER, 'LC_ALL' => 'C',
  'DYLD_INSERT_LIBRARIES' => nil, 'DYLD_LIBRARY_PATH' => nil, 'DYLD_FRAMEWORK_PATH' => nil }
sdk, sdk_status, sdk_timeout = capture_owned(env, '/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path')
raise "SDK lookup failed: #{sdk}" unless sdk_status.success? && !sdk_timeout
executable = File.join(scratch, 'handoff-source-parity')
test_frameworks = File.join(BelugaCoreArtifact::DEVELOPER, 'Platforms/MacOSX.platform/Developer/Library/Frameworks')
test_libraries = File.join(BelugaCoreArtifact::DEVELOPER, 'Platforms/MacOSX.platform/Developer/usr/lib')
shared_frameworks = File.expand_path('../SharedFrameworks', BelugaCoreArtifact::DEVELOPER)
argv = [tool, '-D', 'BELUGA_HANDOFF_PURE_STUB_FIXTURE', '-sdk', sdk.strip,
  '-target', 'arm64-apple-macos13.0', '-F', File.dirname(framework), '-framework', 'BelugaCore',
  '-F', test_frameworks, '-Xlinker', '-rpath', '-Xlinker', test_frameworks,
  '-I', test_libraries, '-L', test_libraries, '-lXCTestSwiftSupport',
  '-Xlinker', '-rpath', '-Xlinker', test_libraries,
  '-Xlinker', '-rpath', '-Xlinker', shared_frameworks,
  *sources, '-o', executable]
compiled, status, compile_timeout = capture_owned(env, *argv)
File.binwrite(File.join(scratch, 'compile.log'), compiled)
raise "Parity compilation failed: #{scratch}" unless status.success? && !compile_timeout
output, status, test_timeout = capture_owned(env, executable)
File.binwrite(File.join(scratch, 'tests.log'), output)
observed = output.scan(/^Test Case '-\[\S+\.(?:BelugaRustMacChromeHandoffSourcePolicyTests) (test\w+)\]' passed/).flatten.sort
# XCTest may emit an unqualified class name in a direct executable.
if observed.empty?
  observed = output.scan(/^Test Case '-\[BelugaRustMacChromeHandoffSourcePolicyTests (test\w+)\]' passed/).flatten.sort
end
BelugaCoreArtifact.verify_source!
final_inventory = BelugaCoreArtifact.files(artifact) == artifact_files.sort
final_manifest = File.binread(File.join(artifact, 'ARTIFACT_MANIFEST.sha256')) ==
  BelugaCoreArtifact.manifest(artifact, BelugaCoreArtifact::ARTIFACT_FILES)
passed = status.success? && !test_timeout && observed == expected &&
  output.include?('Executed 9 tests, with 0 failures') && !output.match?(/\bskipped\b|\bfailed\b/i) &&
  final_inventory && final_manifest &&
  before == fenced_paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
result = { schema: 'beluga.handoff-source.pure-parity.v1', scope: 'copied scalar/bridge; shape fixture only',
  passed: passed, expected: expected, observed: observed, source_sha256: before,
  archive_sha256: Digest::SHA256.file(File.join(framework, 'BelugaCore')).hexdigest,
  compile_argv: argv, native_or_device_proof: false, deployment_proof: false }
File.binwrite(File.join(scratch, 'RESULT.json'), JSON.pretty_generate(result) + "\n")
puts output
raise "Parity refused: #{scratch}" unless passed
puts "HANDOFF_SOURCE_PURE_PARITY_PASS #{scratch}"
