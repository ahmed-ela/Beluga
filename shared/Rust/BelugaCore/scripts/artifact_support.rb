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
  SOURCE_FILES = %w[
    .gitignore Cargo.lock Cargo.toml README.md THIRD_PARTY_NOTICES.html
    include/beluga_core.h include/module.modulemap rust-toolchain.toml
    scripts/artifact_support.rb scripts/build-xcframework.rb scripts/mutation-tests.rb
    scripts/verify-xcframework.rb src/lib.rs src/host_lifecycle.rs tests/c_abi_smoke.c tests/policy.rs tests/host_lifecycle.rs
    tests/swift_import_smoke.swift
  ].sort.freeze
  ARTIFACT_FILES = %w[
    BUILD_METADATA.txt Info.plist SOURCE_MANIFEST.sha256 THIRD_PARTY_NOTICES.html
    macos-arm64/Headers/beluga_core.h macos-arm64/Headers/module.modulemap
    macos-arm64/libbeluga_core.a
  ].sort.freeze

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
    Open3.popen2e(env, *argv, chdir: chdir, pgroup: true) do |input, stream, waiter|
      input.close
      begin
        Timeout.timeout(timeout) do
          stream.each_line { |line| output << line; $stdout.write(line) }
          status = waiter.value
        end
      rescue Timeout::Error
        Process.kill('TERM', -waiter.pid) rescue nil
        sleep 0.1
        Process.kill('KILL', -waiter.pid) rescue nil
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
    [CARGO, RUSTC, "#{DEVELOPER}/usr/bin/xcodebuild",
     "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang",
     "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"].each do |path|
      assert(File.executable?(path), "Pinned tool unavailable: #{path}")
    end
    version = capture!(RUSTC, '--version', '--verbose', env: env)
    assert(version.lines.include?("release: 1.97.1\n"), 'Pinned rustc release differs')
    assert(version.lines.include?("host: aarch64-apple-darwin\n"), 'Unsupported Rust host')
    sysroot = capture!(RUSTC, '--print', 'sysroot', env: env).strip
    assert(File.directory?(File.join(sysroot, 'lib/rustlib', TARGET, 'lib')), 'Pinned Darwin target absent')
    xcode = capture!("#{DEVELOPER}/usr/bin/xcodebuild", '-version', env: env)
    assert(xcode == "Xcode 26.6\nBuild version 17F113\n", 'Pinned Xcode version differs')
    sdk = capture!('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version', env: env).strip
    "rust-toolchain=1.97.1\nsupported-target=#{TARGET}\nsupported-architecture=arm64\nabi-version=1\n#{version}#{xcode}macos-sdk=#{sdk}\n"
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
    %w[beluga_core.h module.modulemap].each do |name|
      assert(File.binread(File.join(artifact, 'macos-arm64/Headers', name)) == File.binread(File.join(CRATE, 'include', name)), "#{name} copy differs")
    end
    info = JSON.parse(capture!('/usr/bin/plutil', '-convert', 'json', '-o', '-', File.join(artifact, 'Info.plist')))
    expected_library = { 'HeadersPath' => 'Headers', 'LibraryIdentifier' => 'macos-arm64', 'BinaryPath' => 'libbeluga_core.a',
                         'LibraryPath' => 'libbeluga_core.a', 'SupportedArchitectures' => ['arm64'],
                         'SupportedPlatform' => 'macos' }
    assert(info == { 'AvailableLibraries' => [expected_library], 'CFBundlePackageType' => 'XFWK',
                     'XCFrameworkFormatVersion' => '1.0' }, 'Unexpected XCFramework slice metadata')
    library = File.join(artifact, 'macos-arm64/libbeluga_core.a')
    assert(capture!('/usr/bin/lipo', '-archs', library).strip == 'arm64', 'Archive must contain only arm64')
    Dir.mktmpdir('verify-', work_directory) do |scratch|
      env = environment(File.join(CRATE, 'target/cargo'))
      metadata = pinned_tools!(env)
      assert(File.binread(File.join(artifact, 'BUILD_METADATA.txt')) == metadata, 'Artifact build-tool metadata differs')
      if smoke
        headers = File.join(artifact, 'macos-arm64/Headers')
        sdk = capture!('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path', env: env).strip
        clang = "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        swift = "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
        assert(ENV.fetch('BELUGA_CORE_CLANG_BIN', clang) == clang, 'Unbound clang path')
        assert(ENV.fetch('BELUGA_CORE_SWIFTC_BIN', swift) == swift, 'Unbound swiftc path')
        run!(clang, '-target', 'arm64-apple-macos13.0', '-isysroot', sdk,
             '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', headers,
             File.join(CRATE, 'tests/c_abi_smoke.c'), library, '-o', File.join(scratch, 'c-smoke'), env: env)
        run!(File.join(scratch, 'c-smoke'), env: env)
        run!(swift, '-target', 'arm64-apple-macos13.0', '-sdk', sdk, '-I', headers,
             File.join(CRATE, 'tests/swift_import_smoke.swift'), library,
             '-o', File.join(scratch, 'swift-smoke'), env: env)
        run!(File.join(scratch, 'swift-smoke'), env: env)
        puts 'BELUGA_CORE_LINK_SMOKE_PASS'
      end
    end
    puts "Verified BelugaCore artifact: #{artifact}"
  end
end
