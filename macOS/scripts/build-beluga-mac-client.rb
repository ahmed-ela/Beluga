#!/usr/bin/ruby
# frozen_string_literal: true
# Root-operated offline builder. Never copies into /Applications or starts launchd.
require 'optparse'
require_relative 'verify-beluga-mac-client'

begin
  options = {}
  OptionParser.new do |parser|
    parser.banner = 'ruby build-beluga-mac-client.rb --output EMPTY0700 --scratch EMPTY0700 --identity DEVELOPER_ID_SHA1'
    parser.on('--output PATH') { |value| options[:output] = value }
    parser.on('--scratch PATH') { |value| options[:scratch] = value }
    parser.on('--identity SHA1') { |value| options[:identity] = value }
  end.parse!
  C = BelugaMacClient
  C.require!(ARGV.empty? && options.keys.sort == %i[identity output scratch], 'all three build options are required')
  config = C.config! # Refuse an unconfigured updater before allocation, auth, or build.
  C.rendezvous!(C.plist(File.join(C::ROOT, 'macOS/BelugaHost/Info.plist'))['BelugaRendezvousURL'])
  receipt = C::MicrophoneReceipt.new
  receipt.verify!
  tested_toolchain = receipt.tested_toolchain
  source = C.source!
  output = C.empty_owned_directory!(options[:output])
  scratch = C.empty_owned_directory!(options[:scratch])
  C.require!(output != scratch && !output.start_with?("#{C::ROOT}/") && !scratch.start_with?("#{C::ROOT}/"), 'release work directories must be disjoint and outside source')
  identity = options[:identity].upcase
  C.require!(/\A[0-9A-F]{40}\z/.match?(identity), 'an exact Developer ID certificate SHA1 is required; no fallback')
  identities = C.run('/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning')
  rows = identities.lines.select { |line| line.match?(/\A\s*\d+\) #{identity} "Developer ID Application:.*\(#{C::TEAM}\)"\s*\z/) }
  C.require!(rows.length == 1, 'exact Developer ID Application certificate is unavailable/ambiguous')
  C.require!(C.run('/usr/bin/uname', '-m').strip == 'arm64', 'this builder profile requires Apple silicon')
  started_at = Time.now.to_i
  build_env = tested_toolchain.build_environment(temporary_directory: scratch)
  toolchain = C.run(tested_toolchain.swift, '--version', env: build_env, unsetenv_others: true).strip
  build_logs = {}
  %w[CaptureServer OpensteamerMediaBridge BelugaUpdater].each do |product|
    tested_toolchain.verify!
    log = C.run(tested_toolchain.swift, 'build', '--package-path', C::ROOT, '--scratch-path', scratch, '--jobs', '2', '-c', 'release', '-Xswiftc', '-warnings-as-errors', '-Xcc', '-Werror', '--product', product, timeout: 1800, env: build_env, capture_stderr: true, unsetenv_others: true)
    tested_toolchain.verify!
    log_path = File.join(output, "#{product}-build.log")
    File.write(log_path, log, mode: 'wx', perm: 0o600)
    build_logs[product] = { 'path' => log_path, 'sha256' => Digest::SHA256.file(log_path).hexdigest }
  end
  tested_toolchain.verify!
  bin = C.run(tested_toolchain.swift, 'build', '--package-path', C::ROOT, '--scratch-path', scratch, '-c', 'release', '--show-bin-path', env: build_env, unsetenv_others: true).strip
  tested_toolchain.verify!
  C.canonical!(bin)
  C.require!(bin.start_with?("#{scratch}/") && File.basename(bin) == 'release', 'release products escaped isolated scratch')
  app = File.join(output, 'Beluga Host.app')
  %w[Contents Contents/MacOS Contents/Frameworks Contents/Resources Contents/Helpers].each { |relative| FileUtils.mkdir_p(File.join(app, relative), mode: 0o755) }
  %w[Contents Contents/MacOS Contents/Frameworks Contents/Resources].each { |relative| FileUtils.mkdir_p(File.join(app, C::BROKER, relative), mode: 0o755) }
  product_paths = {
    'CaptureServer' => 'Contents/MacOS/CaptureServer',
    'OpensteamerMediaBridge' => 'Contents/MacOS/OpensteamerMediaBridge',
    'BelugaUpdater' => C::BROKER_EXECUTABLE
  }
  product_paths.each do |product, relative|
    path = File.join(bin, product)
    info = C.regular!(path)
    C.require!(info.mtime.to_i >= started_at && File.executable?(path), 'stale or unsafe build product')
    FileUtils.cp(path, File.join(app, relative))
  end
  livekit = File.join(bin, 'LiveKitWebRTC.framework')
  sparkle_matches = Dir.glob(File.join(scratch, 'artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'))
  C.require!(sparkle_matches.length == 1, 'exact Sparkle framework build artifact is missing/ambiguous')
  sparkle = sparkle_matches.first
  C.canonical!(sparkle)
  C.require!(C.plist(File.join(sparkle, 'Versions/B/Resources/Info.plist'))['CFBundleShortVersionString'] == C::SPARKLE_VERSION, 'SwiftPM did not fetch the exact Sparkle version')
  [livekit, sparkle].each do |framework|
    C.canonical!(framework)
    C.require!(File.directory?(framework) && !File.symlink?(framework), 'unsafe framework source')
    C.run('/usr/bin/ditto', '--noqtn', framework, File.join(app, 'Contents/Frameworks', File.basename(framework)))
  end
  # A real second framework copy, not an alias back into the host. The updater
  # bundle remains self-contained when later staged outside its update target.
  C.run('/usr/bin/ditto', '--noqtn', sparkle, File.join(app, C::BROKER_SPARKLE))
  resources = {
    'macOS/BelugaHost/Resources/AppIcon.icns' => 'AppIcon.icns',
    'THIRD_PARTY_NOTICES.md' => 'ThirdPartyNotices.md',
    'macOS/BelugaHost/Resources/Sparkle-LICENSE.txt' => 'Sparkle-LICENSE.txt',
    'macOS/OpensteamerHost/org.example.opensteamer.media.json' => 'org.example.opensteamer.media.json',
    'macOS/BelugaHost/Release.json' => 'Release.json'
  }
  resources.each { |source_path, name| FileUtils.cp(File.join(C::ROOT, source_path), File.join(app, 'Contents/Resources', name)) }
  File.write(File.join(app, 'Contents/Resources/BuildSource.json'), JSON.pretty_generate(source) + "\n", mode: 'wx', perm: 0o644)
  %w[Release.json Sparkle-LICENSE.txt].each do |name|
    FileUtils.cp(File.join(app, 'Contents/Resources', name), File.join(app, C::BROKER, 'Contents/Resources', name))
  end
  File.write(File.join(app, C::BROKER, 'Contents/Resources/BuildSource.json'), JSON.pretty_generate(source) + "\n", mode: 'wx', perm: 0o644)
  info = File.join(app, 'Contents/Info.plist')
  FileUtils.cp(File.join(C::ROOT, 'macOS/BelugaHost/Info.plist'), info)
  {
    'CFBundleShortVersionString' => config['version'], 'CFBundleVersion' => config['build'].to_s,
    'SUFeedURL' => config['feedURL'], 'SUPublicEDKey' => config['publicEDKey'],
    'SUVerifyUpdateBeforeExtraction' => true, 'SURequireSignedFeed' => true,
    'SUAllowsAutomaticUpdates' => false, 'BelugaUpdateOwnershipProtocol' => 1
  }.each { |key, value| C.plist_set(info, key, value) }
  broker_info = File.join(app, C::BROKER, 'Contents/Info.plist')
  FileUtils.cp(File.join(C::ROOT, 'macOS/BelugaUpdater/Info.plist'), broker_info)
  C.broker_info(config).each { |key, value| C.plist_set(broker_info, key, value) }
  product_paths.each_value do |relative|
    path = File.join(app, relative)
    64.times do
      paths = C.rpaths(path)
      break if paths.empty?
      C.run('/usr/bin/install_name_tool', '-delete_rpath', paths.first, path)
      C.require!(C.rpaths(path).length < paths.length, 'rpath removal made no progress')
    end
    C.require!(C.rpaths(path).empty?, 'more than 64 unreviewed rpaths')
    C.code_loading_contract!(relative)['rpaths'].each do |rpath|
      C.run('/usr/bin/install_name_tool', '-add_rpath', rpath, path)
    end
  end
  C.run('/usr/bin/xattr', '-cr', app)
  Find.find(app) do |path|
    info = File.lstat(path)
    next if info.symlink?
    relative = path.delete_prefix("#{app}/")
    File.chmod(info.directory? || C::CODE.key?(relative) ? 0o755 : 0o644, path)
  end
  # Sparkle 2.10.0's official Downloader has empty entitlements. Do not inherit
  # arbitrary fetched/debug entitlements or use codesign --deep for signing.
  receipt.verify!
  tested_toolchain.verify!
  C.require!(C.source! == source && C.config! == config, 'source/configuration changed before signing')
  sign = lambda do |path, identifier, host: false|
    args = ['/usr/bin/codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp', '--identifier', identifier]
    args += ['--entitlements', File.join(C::ROOT, 'macOS/OpensteamerHost/MediaAutomation.entitlements')] if host
    C.run(*args, path)
  end
  C.nested_signing_contract.each { |relative, identifier| sign.call(File.join(app, relative), identifier) }
  sign.call(File.join(app, 'Contents/MacOS/CaptureServer'), C::BUNDLE_ID, host: true)
  sign.call(app, C::BUNDLE_ID, host: true)
  verification = C.verify_app!(app, config)
  receipt.verify!
  C.require!(C.source! == source && C.config! == config, 'source/configuration changed before artifact handoff')
  tested_toolchain.verify!
  report = verification.merge(source).merge('schema' => 'beluga.mac-client-build.v1', 'status' => 'SIGNED_VERIFIED_NOT_NOTARIZED', 'app' => app, 'identitySHA1' => identity, 'toolchain' => toolchain, 'testedToolchain' => tested_toolchain.binding, 'buildLogs' => build_logs)
  File.write(File.join(output, 'build.json'), JSON.pretty_generate(report) + "\n", mode: 'wx', perm: 0o600)
  puts JSON.pretty_generate(report)
rescue BelugaMacClient::Refusal, OptionParser::ParseError, SystemCallError, JSON::ParserError => error
  warn "build-beluga-mac-client: #{error.message}"
  exit 1
end
