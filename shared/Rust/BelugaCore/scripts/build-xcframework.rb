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
TARGETS.each do |rust_target|
  sdk_name = rust_target == TARGET ? 'macosx' : (rust_target == 'aarch64-apple-ios' ? 'iphoneos' : 'iphonesimulator')
  sdk = BelugaCoreArtifact.capture!('/usr/bin/xcrun', '--sdk', sdk_name, '--show-sdk-path', env: env).strip
  deployment = rust_target == TARGET ? { 'MACOSX_DEPLOYMENT_TARGET' => '13.0' } : { 'IPHONEOS_DEPLOYMENT_TARGET' => '16.0' }
  BelugaCoreArtifact.run!(CARGO, 'build', '--offline', '--locked', '--release', '--target', rust_target,
                         env: env.merge('SDKROOT' => sdk).merge(deployment))
end
Dir.mktmpdir('stage-', File.join(CRATE, 'target')) do |scratch|
  staged = File.join(scratch, 'BelugaCore.xcframework')
  simulator = File.join(scratch, 'simulator/libbeluga_core.a')
  FileUtils.mkdir_p(File.dirname(simulator))
  BelugaCoreArtifact.run!('/usr/bin/lipo', '-create',
    File.join(target, 'aarch64-apple-ios-sim/release/libbeluga_core.a'),
    File.join(target, 'x86_64-apple-ios/release/libbeluga_core.a'), '-output', simulator, env: env)
  libraries = [File.join(target, TARGET, 'release/libbeluga_core.a'),
               File.join(target, 'aarch64-apple-ios/release/libbeluga_core.a'), simulator]
  frameworks = SLICES.keys.zip(libraries).map do |identifier, library|
    framework = File.join(scratch, 'frameworks', identifier, FRAMEWORK_NAME)
    FileUtils.mkdir_p(File.join(framework, 'Headers'))
    FileUtils.mkdir_p(File.join(framework, 'Modules'))
    FileUtils.cp(library, File.join(framework, 'BelugaCore'))
    FileUtils.cp(File.join(CRATE, 'include/beluga_core.h'), File.join(framework, 'Headers/beluga_core.h'))
    FileUtils.cp(File.join(CRATE, 'include/module.modulemap'), File.join(framework, 'Modules/module.modulemap'))
    plist = File.join(framework, 'Info.plist')
    File.binwrite(plist, JSON.generate(BelugaCoreArtifact.framework_info(identifier)))
    BelugaCoreArtifact.run!('/usr/bin/plutil', '-convert', 'xml1', plist, env: env)
    framework
  end
  arguments = frameworks.flat_map { |framework| ['-framework', framework] }
  BelugaCoreArtifact.run!("#{DEVELOPER}/usr/bin/xcodebuild", '-create-xcframework', *arguments, '-output', staged, env: env)
  %w[SOURCE_MANIFEST.sha256 THIRD_PARTY_NOTICES.html].each { |name| FileUtils.cp(File.join(CRATE, name), File.join(staged, name)) }
  File.binwrite(File.join(staged, 'BUILD_METADATA.txt'), metadata)
  File.binwrite(File.join(staged, 'ARTIFACT_MANIFEST.sha256'), BelugaCoreArtifact.manifest(staged, ARTIFACT_FILES))
  BelugaCoreArtifact.verify!(staged)
  FileUtils.mkdir_p(File.dirname(output))
  BelugaCoreArtifact.assert(!File.exist?(output) && !File.symlink?(output), 'Output appeared while building; refusing overwrite')
  File.rename(staged, output)
end
BelugaCoreArtifact.verify!(output)
puts "Built verified Mac arm64 + iOS device/Simulator BelugaCore: #{output}"
