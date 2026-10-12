#!/usr/bin/ruby
# frozen_string_literal: true
# Offline fixtures for the actual release input validator. No Xcode, credentials,
# signing, encrypted cache, upload, installed app, device, or audio-route access.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

root = File.expand_path('..', __dir__)
wrapper = File.join(root, 'iOS/opensteamer/scripts/archive-upload-side-by-side-testflight.sh')
source = File.read(wrapper)

def require!(condition, message)
  raise message unless condition
end

def production_function(source, name)
  matches = source.scan(/^function #{Regexp.escape(name)}\(\) \{\n.*?^\}\n/m)
  require!(matches.length == 1, "production #{name} function is missing/ambiguous")
  matches.first
end

pins = %w[EXPECTED_PACKAGE_MANIFEST_SHA256 EXPECTED_PACKAGE_RESOLVED_SHA256].map do |name|
  matches = source.scan(/^readonly #{name}="[0-9a-f]{64}"$/)
  require!(matches.length == 1, "production #{name} pin is missing/ambiguous")
  matches.first
end.join("\n")
functions = %w[sha256_file sha256_private_file_contents vendor_archive_identity
               verify_pinned_vendor_archive verify_package_dependency_contract].map do |name|
  production_function(source, name)
end.join("\n")

Dir.mktmpdir('beluga-testflight-package-inputs.') do |temporary|
  fixture = File.realpath(temporary)
  File.chmod(0o700, fixture)
  package_directory = File.join(fixture, 'package inputs with spaces')
  FileUtils.mkdir_p(package_directory, mode: 0o700)
  manifest = File.join(package_directory, 'Package.swift')
  resolved = File.join(package_directory, 'Package.resolved')
  vendor = File.join(fixture, 'fixture-vendor.zip')
  File.write(vendor, 'offline vendor fixture; not a usable native artifact')
  vendor_sha = Digest::SHA256.file(vendor).hexdigest
  reset = lambda do
    [manifest, resolved].each do |path|
      File.unlink(path) if File.exist?(path) || File.symlink?(path)
      FileUtils.cp(File.join(root, File.basename(path)), path)
    end
    File.write(vendor, 'offline vendor fixture; not a usable native artifact')
  end
  reset.call
  harness = File.join(fixture, 'production-package-validator.zsh')
  File.write(harness, <<~ZSH)
    #!/bin/zsh
    set -euo pipefail
    readonly PACKAGE_MANIFEST_PATH=$1
    readonly PACKAGE_RESOLVED_PATH=$2
    readonly VENDOR_ARCHIVE_PATH=$3
    readonly EXPECTED_VENDOR_ARCHIVE_SHA256=$4
    readonly ACTION=$5
    #{pins}
    TESTFLIGHT_VENDOR_ARCHIVE_IDENTITY=''
    TESTFLIGHT_VENDOR_ARCHIVE_SHA256=''
    #{functions}
    case "$ACTION" in
      pass)
        verify_package_dependency_contract
        verify_package_dependency_contract
        ;;
      reject)
        if verify_package_dependency_contract; then
          print -u2 -- 'changed/unsafe release input was accepted'
          exit 1
        fi
        ;;
      changed-manifest-after-admission|changed-lock-after-admission|changed-vendor-after-admission)
        verify_package_dependency_contract
        case "$ACTION" in
          changed-manifest-after-admission) print -r -- '// altered' >> "$PACKAGE_MANIFEST_PATH" ;;
          changed-lock-after-admission) print -r -- ' ' >> "$PACKAGE_RESOLVED_PATH" ;;
          changed-vendor-after-admission) print -r -- altered >> "$VENDOR_ARCHIVE_PATH" ;;
        esac
        if verify_package_dependency_contract; then
          print -u2 -- 'release input changed after admission but was accepted'
          exit 1
        fi
        ;;
      *) exit 2 ;;
    esac
  ZSH

  cases = 0
  run_case = lambda do |label, action: 'reject', manifest_path: manifest, resolved_path: resolved|
    output, status = Open3.capture2e('/bin/zsh', harness, manifest_path, resolved_path, vendor, vendor_sha, action)
    require!(status.success?, "#{label}: #{output}")
    cases += 1
  end

  run_case.call('exact current inputs and pinned vendor', action: 'pass')
  File.write(manifest, File.read(manifest) + "\n// changed manifest\n")
  run_case.call('changed manifest bytes')
  reset.call
  value = JSON.parse(File.read(resolved))
  value.fetch('pins').first.fetch('state')['version'] = '2.10.1'
  File.write(resolved, JSON.pretty_generate(value))
  run_case.call('wrong Sparkle version')
  reset.call
  value = JSON.parse(File.read(resolved))
  value.fetch('pins').first.fetch('state')['revision'] = '0' * 40
  File.write(resolved, JSON.pretty_generate(value))
  run_case.call('wrong Sparkle revision')
  reset.call
  value = JSON.parse(File.read(resolved))
  value.fetch('pins') << value.fetch('pins').first.dup
  File.write(resolved, JSON.pretty_generate(value))
  run_case.call('duplicate resolved pin')
  reset.call
  File.unlink(manifest)
  run_case.call('missing manifest')
  reset.call
  File.unlink(resolved)
  run_case.call('missing lock')
  reset.call
  File.unlink(manifest)
  File.symlink(File.join(root, 'Package.swift'), manifest)
  run_case.call('symlink manifest')
  reset.call
  File.unlink(resolved)
  File.symlink(File.join(root, 'Package.resolved'), resolved)
  run_case.call('symlink lock')
  reset.call
  alias_directory = File.join(fixture, 'package-alias')
  File.symlink(package_directory, alias_directory)
  run_case.call('symlink ancestor', manifest_path: File.join(alias_directory, 'Package.swift'))
  run_case.call('noncanonical lock path', resolved_path: File.join(package_directory, '..', File.basename(package_directory), 'Package.resolved'))
  File.write(vendor, 'changed unreviewed vendor bytes')
  run_case.call('wrong vendor bytes')
  reset.call
  run_case.call('manifest changed after admission', action: 'changed-manifest-after-admission')
  reset.call
  run_case.call('lock changed after admission', action: 'changed-lock-after-admission')
  reset.call
  run_case.call('vendor changed after admission', action: 'changed-vendor-after-admission')
  puts "TestFlight package input behavior tests passed: #{cases} cases"
end
