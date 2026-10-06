#!/usr/bin/env ruby
require_relative 'artifact_support'
raise 'Usage: verify-xcframework.rb [XCFRAMEWORK]' if ARGV.length > 1
FileUtils.mkdir_p(File.join(BelugaCoreArtifact::CRATE, 'target'))
BelugaCoreArtifact.verify!(File.expand_path(ARGV.fetch(0, BelugaCoreArtifact::DEFAULT_ARTIFACT)))
