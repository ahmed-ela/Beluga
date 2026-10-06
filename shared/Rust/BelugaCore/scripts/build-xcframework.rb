#!/usr/bin/env ruby
require_relative 'artifact_support'
include BelugaCoreArtifact

if ARGV == ['--refresh-source-manifest']
  BelugaCoreArtifact.assert(BelugaCoreArtifact.files(CRATE, exclude: %w[target SOURCE_MANIFEST.sha256]) == SOURCE_FILES,
                            'Cannot refresh an unexpected source inventory')
  File.binwrite(File.join(CRATE, 'SOURCE_MANIFEST.sha256'), BelugaCoreArtifact.manifest(CRATE, SOURCE_FILES))
  puts 'Refreshed exact source manifest'
  exit
end
raise 'Usage: build-xcframework.rb [ABSENT_OUTPUT_PATH|--refresh-source-manifest]' if ARGV.length > 1 || ARGV.any? { |arg| arg.start_with?('--') }
output = File.expand_path(ARGV.fetch(0, DEFAULT_ARTIFACT))
BelugaCoreArtifact.assert(!File.exist?(output) && !File.symlink?(output), 'Refusing to overwrite an existing artifact')
BelugaCoreArtifact.verify_source!
target = File.join(CRATE, 'target/cargo')
env = BelugaCoreArtifact.environment(target)
metadata = BelugaCoreArtifact.pinned_tools!(env)
FileUtils.mkdir_p(File.join(CRATE, 'target'))
BelugaCoreArtifact.run!(CARGO, 'build', '--offline', '--locked', '--release', '--target', TARGET, env: env)
Dir.mktmpdir('stage-', File.join(CRATE, 'target')) do |scratch|
  staged = File.join(scratch, 'BelugaCore.xcframework')
  BelugaCoreArtifact.run!("#{DEVELOPER}/usr/bin/xcodebuild", '-create-xcframework',
    '-library', File.join(target, TARGET, 'release/libbeluga_core.a'),
    '-headers', File.join(CRATE, 'include'), '-output', staged, env: env)
  %w[SOURCE_MANIFEST.sha256 THIRD_PARTY_NOTICES.html].each { |name| FileUtils.cp(File.join(CRATE, name), File.join(staged, name)) }
  File.binwrite(File.join(staged, 'BUILD_METADATA.txt'), metadata)
  File.binwrite(File.join(staged, 'ARTIFACT_MANIFEST.sha256'), BelugaCoreArtifact.manifest(staged, ARTIFACT_FILES))
  BelugaCoreArtifact.verify!(staged)
  FileUtils.mkdir_p(File.dirname(output))
  BelugaCoreArtifact.assert(!File.exist?(output) && !File.symlink?(output), 'Output appeared while building; refusing overwrite')
  File.rename(staged, output)
end
BelugaCoreArtifact.verify!(output)
puts "Built verified arm64-only BelugaCore: #{output}"
