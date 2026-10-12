#!/usr/bin/env ruby
# Offline exact-export-policy mutations; never invokes signing, Xcode, or account APIs.
require 'json'
require 'open3'
require 'shellwords'
require 'tmpdir'

root = File.expand_path('..', __dir__)
guard = File.join(root, 'iOS/opensteamer/scripts/archive-upload-side-by-side-testflight.sh')
policy = File.join(root, 'iOS/opensteamer/TestFlightExportOptions.plist')
json, error, status = Open3.capture3('/usr/bin/plutil', '-convert', 'json', '-o', '-', policy)
raise "policy decode failed: #{error}" unless status.success?
original = JSON.parse(json)
scratch = Dir.mktmpdir('beluga-export-signing-tests.', '/Volumes/t7')
File.chmod(0700, scratch)
fixture = File.join(scratch, 'ExportOptions.plist')
checks = 0
check = lambda do |label, value, expected|
  File.write(fixture, JSON.generate(value))
  command = 'source <(/usr/bin/sed \'/^verify_static_contract$/,$d\' "$GUARD"); ' \
            'trap - EXIT ZERR HUP INT QUIT TERM; verify_reviewed_export_signing_options ' + Shellwords.escape(fixture)
  output, error, status = Open3.capture3({ 'GUARD' => guard }, '/bin/zsh', '-c', command)
  raise "#{label}: #{status.exitstatus}: #{output} #{error}" unless status.success? == expected
  checks += 1
end
check.call('reviewed export policy', original, true)
['signingStyle', 'signingCertificate', 'provisioningProfiles'].each do |key|
  value = Marshal.load(Marshal.dump(original))
  value.delete(key)
  check.call('missing ' + key, value, false)
end
check.call('cloud automatic fallback rejected', original.merge('signingStyle' => 'automatic'), false)
check.call('certificate substitution rejected', original.merge('signingCertificate' => 'A' * 40), false)
profiles = original.fetch('provisioningProfiles')
profiles.each_key do |bundle|
  replacement = profiles.dup
  replacement[bundle] = '00000000-0000-4000-8000-000000000000'
  check.call('wrong profile for ' + bundle, original.merge('provisioningProfiles' => replacement), false)
  check.call('missing profile for ' + bundle, original.merge('provisioningProfiles' => profiles.reject { |key, _| key == bundle }), false)
end
check.call('extra bundle rejected', original.merge('provisioningProfiles' => profiles.merge('com.example.other' => profiles.values.first)), false)
check.call('swapped target profiles rejected', original.merge('provisioningProfiles' => profiles.keys.zip(profiles.values.reverse).to_h), false)
check.call('wrong map type rejected', original.merge('provisioningProfiles' => profiles.to_a), false)
check.call('profile name instead of pinned UUID rejected', original.merge('provisioningProfiles' => profiles.transform_values { 'iOS Team Store Provisioning Profile' }), false)
puts "PASS: #{checks} exact local export-signing checks; evidence: #{scratch}"
