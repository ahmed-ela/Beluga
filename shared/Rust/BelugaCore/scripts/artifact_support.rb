#!/usr/bin/env ruby
# Shared exact-inventory and pinned-tool helpers. No package/tool installation.
require 'digest'
require 'fileutils'
require 'find'
require 'json'
require 'open3'
require 'tmpdir'
require 'timeout'

module BelugaCoreArtifact
  CRATE = File.expand_path('..', __dir__).freeze
  DEFAULT_ARTIFACT = File.expand_path('../../Vendor/BelugaCore.xcframework', CRATE).freeze
  DEVELOPER = '/Volumes/t7/opensteamer-space-recovery-20260804/nonrepo/Xcode-26.6.0.app/Contents/Developer'.freeze
  RUSTUP = '/Volumes/t7/opensteamer-rustup-1.97.1'.freeze
  CARGO_HOME_PATH = '/Volumes/t7/opensteamer-cargo-1.97.1'.freeze
  TOOLCHAIN = "#{RUSTUP}/toolchains/1.97.1-aarch64-apple-darwin".freeze
  CARGO = ENV.fetch('BELUGA_CORE_CARGO_BIN', "#{TOOLCHAIN}/bin/cargo").freeze
  RUSTC = ENV.fetch('BELUGA_CORE_RUSTC_BIN', "#{TOOLCHAIN}/bin/rustc").freeze
  TARGET = 'aarch64-apple-darwin'.freeze
  TARGETS = %w[aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios].freeze
  FRAMEWORK_NAME = 'BelugaCore.framework'.freeze
  FRAMEWORK_FILES = %w[BelugaCore Headers/beluga_core.h Modules/module.modulemap Info.plist].freeze
  SLICES = {
    'macos-arm64' => { 'architectures' => %w[arm64], 'platform' => 'macos' },
    'ios-arm64' => { 'architectures' => %w[arm64], 'platform' => 'ios' },
    'ios-arm64_x86_64-simulator' => { 'architectures' => %w[arm64 x86_64], 'platform' => 'ios', 'variant' => 'simulator' }
  }.freeze
  LINK_TARGETS = [
    [TARGET, 'macos-arm64', 'macosx', 'arm64-apple-macos13.0', true],
    ['aarch64-apple-ios', 'ios-arm64', 'iphoneos', 'arm64-apple-ios16.0', false],
    ['aarch64-apple-ios-sim', 'ios-arm64_x86_64-simulator', 'iphonesimulator', 'arm64-apple-ios16.0-simulator', false],
    ['x86_64-apple-ios', 'ios-arm64_x86_64-simulator', 'iphonesimulator', 'x86_64-apple-ios16.0-simulator', false]
  ].freeze
  SOURCE_FILES = %w[
    .gitignore Cargo.lock Cargo.toml README.md THIRD_PARTY_NOTICES.html
    include/beluga_core.h include/module.modulemap rust-toolchain.toml
    scripts/artifact_support.rb scripts/build-xcframework.rb scripts/mutation-tests.rb
    scripts/verify-xcframework.rb src/lib.rs src/host_lifecycle.rs src/handoff_transactions.rs src/handoff_offers.rs src/youtube_handoff_operation.rs src/invitation_acceptance.rs
    tests/c_abi_smoke.c tests/policy.rs tests/host_lifecycle.rs tests/handoff_transactions.rs tests/handoff_offers.rs tests/youtube_handoff_operation.rs tests/invitation_acceptance.rs
    src/replay_policy.rs tests/replay_policy.rs
    src/pairing_catalog_checkpoint.rs tests/pairing_catalog_checkpoint.rs
    src/reconnect_counters.rs tests/reconnect_counters.rs
    src/pairing_commit.rs tests/pairing_commit.rs
    tests/swift_import_smoke.swift
  ].sort.freeze
  ARTIFACT_FILES = (%w[
    BUILD_METADATA.txt Info.plist SOURCE_MANIFEST.sha256 THIRD_PARTY_NOTICES.html
  ] + SLICES.keys.flat_map { |slice| FRAMEWORK_FILES.map { |name| "#{slice}/#{FRAMEWORK_NAME}/#{name}" } }).sort.freeze

  def self.assert(condition, message)
    raise message unless condition
  end

  def self.environment(target_dir)
    { 'RUSTUP_HOME' => RUSTUP, 'CARGO_HOME' => CARGO_HOME_PATH,
      'RUSTUP_TOOLCHAIN' => '1.97.1', 'CARGO_TARGET_DIR' => target_dir,
      'RUSTC' => RUSTC,
      'DEVELOPER_DIR' => DEVELOPER, 'LC_ALL' => 'C' }
  end

  def self.work_directory
    path = File.expand_path(ENV.fetch('BELUGA_CORE_WORK_DIRECTORY', File.join(CRATE, 'target')))
    assert(!File.symlink?(path), 'Work directory must not be a symlink')
    FileUtils.mkdir_p(path)
    path
  end

  def self.run!(*argv, env: {}, chdir: CRATE, timeout: 300)
    output = ''
    status = nil
    group_mode = ENV['BELUGA_CORE_OWNED_PROCESS_GROUP']
    assert(group_mode.nil? || group_mode == 'inherit', 'Unknown owned process group mode')
    inherit_group = group_mode == 'inherit'
    assert(!inherit_group || Process.pid == Process.getpgrp, 'Inherited tools require the exclusively owned builder group')
    Open3.popen2e(env, *argv, chdir: chdir, pgroup: !inherit_group) do |input, stream, waiter|
      input.close
      begin
        Timeout.timeout(timeout) do
          stream.each_line { |line| output << line; $stdout.write(line) }
          status = waiter.value
        end
      rescue Timeout::Error
        # The outer owner cleans the whole inherited group; a nested timeout
        # must not signal its own builder. Ordinary callers retain group kill.
        signal_target = inherit_group ? waiter.pid : -waiter.pid
        Process.kill('TERM', signal_target) rescue nil
        sleep 0.1
        Process.kill('KILL', signal_target) rescue nil
        raise "Timed out after #{timeout}s: #{argv.first}"
      end
    end
    assert(status.success?, "Command failed (#{status.exitstatus}): #{argv.inspect}")
    output
  end

  def self.capture!(*argv, env: {}, chdir: CRATE)
    output, error, status = Open3.capture3(env, *argv, chdir: chdir)
    assert(status.success?, "Command failed: #{argv.inspect}: #{error}")
    output
  end

  def self.files(root, exclude: [])
    result = []
    Find.find(root) do |path|
      relative = path.delete_prefix("#{root}/")
      assert(!File.symlink?(path), "Symlink rejected: #{path}")
      if File.directory?(path)
        Find.prune if exclude.include?(relative)
      elsif File.file?(path)
        result << relative unless exclude.include?(relative)
      else
        raise "Nonregular node rejected: #{path}"
      end
    end
    result.sort
  end

  def self.manifest(root, names)
    names.sort.map { |name| "#{Digest::SHA256.file(File.join(root, name)).hexdigest}  #{name}\n" }.join
  end

  def self.framework_info(identifier)
    platform = { 'macos-arm64' => 'MacOSX', 'ios-arm64' => 'iPhoneOS', 'ios-arm64_x86_64-simulator' => 'iPhoneSimulator' }.fetch(identifier)
    info = { 'CFBundleExecutable' => 'BelugaCore', 'CFBundleIdentifier' => 'com.elamin.beluga.core',
             'CFBundleInfoDictionaryVersion' => '6.0', 'CFBundleName' => 'BelugaCore',
             'CFBundlePackageType' => 'FMWK', 'CFBundleShortVersionString' => '0.1.0',
             'CFBundleVersion' => '1', 'CFBundleSupportedPlatforms' => [platform] }
    info[platform == 'MacOSX' ? 'LSMinimumSystemVersion' : 'MinimumOSVersion'] = platform == 'MacOSX' ? '13.0' : '16.0'
    info
  end

  def self.verify_static_archive!(library, architectures)
    File.open(library, 'rb') do |file|
      magic = file.read(8)
      if architectures.size == 1
        assert(magic == "!<arch>\n", 'Framework main binary is not a static archive')
      else
        assert(magic&.byteslice(0, 4) == "\xca\xfe\xba\xbe".b && magic.byteslice(4, 4).unpack1('N') == 2,
               'Simulator main binary is not the reviewed two-architecture fat archive')
        entries = file.read(40)
        assert(entries&.bytesize == 40, 'Fat archive descriptor truncated')
        offsets = 2.times.map { |index| entries.byteslice(index * 20, 20).unpack('N5') }
        assert(offsets.map(&:first).sort == [0x01000007, 0x0100000c], 'Fat archive CPU types differ')
        offsets.each do |_, _, offset, size, _|
          assert(offset >= 48 && size >= 8 && offset + size <= file.stat.size, 'Fat archive range invalid')
          file.seek(offset)
          assert(file.read(8) == "!<arch>\n", 'Simulator slice is not a static archive')
        end
      end
    end
  end

  def self.verify_source!
    assert(files(CRATE, exclude: %w[target SOURCE_MANIFEST.sha256]) == SOURCE_FILES,
           'Source inventory differs from the reviewed exact list')
    expected = manifest(CRATE, SOURCE_FILES)
    assert(File.binread(File.join(CRATE, 'SOURCE_MANIFEST.sha256')) == expected,
           'Source manifest bytes or source hash differs')
  end

  def self.pinned_tools!(env)
    assert(ENV.fetch('DEVELOPER_DIR', DEVELOPER) == DEVELOPER, 'Unexpected Xcode path')
    assert(CARGO == "#{TOOLCHAIN}/bin/cargo" && RUSTC == "#{TOOLCHAIN}/bin/rustc", 'Unbound Rust tool path')
    %w[xcrun lipo plutil].each do |tool|
      assert(ENV.fetch("BELUGA_CORE_#{tool.upcase}_BIN", "/usr/bin/#{tool}") == "/usr/bin/#{tool}", "Unbound #{tool} path")
    end
    [CARGO, RUSTC, "#{DEVELOPER}/usr/bin/xcodebuild",
     "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang",
     "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"].each do |path|
      assert(File.executable?(path), "Pinned tool unavailable: #{path}")
    end
    version = capture!(RUSTC, '--version', '--verbose', env: env)
    assert(version.lines.include?("release: 1.97.1\n"), 'Pinned rustc release differs')
    assert(version.lines.include?("host: aarch64-apple-darwin\n"), 'Unsupported Rust host')
    sysroot = capture!(RUSTC, '--print', 'sysroot', env: env).strip
    assert(sysroot == TOOLCHAIN, 'Pinned Rust sysroot differs')
    TARGETS.each { |target| assert(File.directory?(File.join(sysroot, 'lib/rustlib', target, 'lib')), "Reviewed installed target absent: #{target}") }
    xcode = capture!("#{DEVELOPER}/usr/bin/xcodebuild", '-version', env: env)
    assert(xcode == "Xcode 26.6\nBuild version 17F113\n", 'Pinned Xcode version differs')
    sdk = %w[macosx iphoneos iphonesimulator].map { |name| capture!('/usr/bin/xcrun', '--sdk', name, '--show-sdk-version', env: env).strip }
    "rust-toolchain=1.97.1\npackaging-profile=static-framework-v1\n#{TARGETS.map { |target| "supported-target=#{target}\n" }.join}supported-architecture=arm64\nsimulator-architectures=arm64,x86_64\nabi-version=1\n#{version}#{xcode}macos-sdk=#{sdk[0]}\niphoneos-sdk=#{sdk[1]}\niphonesimulator-sdk=#{sdk[2]}\n"
  end

  def self.verify!(artifact, smoke: true)
    verify_source!
    assert(File.directory?(artifact) && !File.symlink?(artifact), 'Artifact directory unavailable')
    assert(files(artifact, exclude: ['ARTIFACT_MANIFEST.sha256']) == ARTIFACT_FILES,
           'Artifact file inventory differs')
    assert(File.binread(File.join(artifact, 'ARTIFACT_MANIFEST.sha256')) == manifest(artifact, ARTIFACT_FILES),
           'Artifact manifest bytes/hash differs')
    %w[SOURCE_MANIFEST.sha256 THIRD_PARTY_NOTICES.html].each do |name|
      assert(File.binread(File.join(artifact, name)) == File.binread(File.join(CRATE, name)), "#{name} copy differs")
    end
    SLICES.each_key do |slice|
      { 'beluga_core.h' => 'Headers', 'module.modulemap' => 'Modules' }.each do |name, directory|
        assert(File.binread(File.join(artifact, slice, FRAMEWORK_NAME, directory, name)) == File.binread(File.join(CRATE, 'include', name)), "#{slice}/#{name} copy differs")
      end
      framework_plist = JSON.parse(capture!('/usr/bin/plutil', '-convert', 'json', '-o', '-', File.join(artifact, slice, FRAMEWORK_NAME, 'Info.plist')))
      assert(framework_plist == framework_info(slice), "#{slice} framework Info.plist differs")
    end
    info = JSON.parse(capture!('/usr/bin/plutil', '-convert', 'json', '-o', '-', File.join(artifact, 'Info.plist')))
    expected_libraries = SLICES.map do |identifier, slice|
      library = { 'LibraryIdentifier' => identifier, 'BinaryPath' => "#{FRAMEWORK_NAME}/BelugaCore",
                  'LibraryPath' => FRAMEWORK_NAME, 'SupportedArchitectures' => slice.fetch('architectures'),
                  'SupportedPlatform' => slice.fetch('platform') }
      library['SupportedPlatformVariant'] = slice.fetch('variant') if slice.key?('variant')
      library
    end.sort_by { |entry| entry.fetch('LibraryIdentifier') }
    assert(info['AvailableLibraries'].is_a?(Array), 'XCFramework library metadata absent')
    info['AvailableLibraries'] = info.fetch('AvailableLibraries').sort_by { |entry| entry.fetch('LibraryIdentifier') }
    assert(info == { 'AvailableLibraries' => expected_libraries, 'CFBundlePackageType' => 'XFWK',
                     'XCFrameworkFormatVersion' => '1.0' }, 'Unexpected XCFramework slice metadata')
    SLICES.each do |identifier, slice|
      library = File.join(artifact, identifier, FRAMEWORK_NAME, 'BelugaCore')
      assert(capture!('/usr/bin/lipo', '-archs', library).split.sort == slice.fetch('architectures').sort, "#{identifier} archive architectures differ")
      verify_static_archive!(library, slice.fetch('architectures'))
    end
    Dir.mktmpdir('verify-', work_directory) do |scratch|
      env = environment(File.join(CRATE, 'target/cargo'))
      metadata = pinned_tools!(env)
      assert(File.binread(File.join(artifact, 'BUILD_METADATA.txt')) == metadata, 'Artifact build-tool metadata differs')
      if smoke
        clang = "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        swift = "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
        assert(ENV.fetch('BELUGA_CORE_CLANG_BIN', clang) == clang, 'Unbound clang path')
        assert(ENV.fetch('BELUGA_CORE_SWIFTC_BIN', swift) == swift, 'Unbound swiftc path')
        LINK_TARGETS.each do |rust_target, slice, sdk_name, link_target, runnable|
          framework_directory = File.join(artifact, slice)
          sdk = capture!('/usr/bin/xcrun', '--sdk', sdk_name, '--show-sdk-path', env: env).strip
          c_output = File.join(scratch, "c-smoke-#{rust_target}")
          swift_output = File.join(scratch, "swift-smoke-#{rust_target}")
          run!(clang, '-target', link_target, '-isysroot', sdk,
             '-std=c11', '-Wall', '-Wextra', '-Werror', '-F', framework_directory,
             File.join(CRATE, 'tests/c_abi_smoke.c'), '-framework', 'BelugaCore', '-o', c_output, env: env)
          run!(swift, '-target', link_target, '-sdk', sdk, '-F', framework_directory,
             File.join(CRATE, 'tests/swift_import_smoke.swift'), '-framework', 'BelugaCore',
             '-o', swift_output, env: env)
          [c_output, swift_output].each do |path|
            assert(capture!('/usr/bin/lipo', '-archs', path).strip == link_target.split('-').first, 'Linked smoke architecture differs')
          end
          if runnable
            run!(c_output, env: env); run!(swift_output, env: env)
            puts 'BELUGA_CORE_LINK_SMOKE_PASS'
          else
            puts "BELUGA_CORE_CROSS_LINK_PASS target=#{rust_target}"
          end
        end
      end
    end
    puts "Verified BelugaCore artifact: #{artifact}"
  end
end
