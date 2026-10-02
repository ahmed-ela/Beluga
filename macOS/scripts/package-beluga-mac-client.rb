#!/usr/bin/ruby
# frozen_string_literal: true
# Root-operated distribution preparation ONLY; no publish, install, driver, or host launch.
# The notary profile and updater account are Keychain identifiers, never credential values.
require 'optparse'
require_relative 'verify-beluga-mac-client'

begin
  options = {}
  OptionParser.new do |parser|
    parser.banner = 'ruby package-beluga-mac-client.rb --app APP --output EMPTY0700 --identity SHA1 --notary-profile NAME --sparkle-tools DIRECTORY --keychain-account NAME'
    parser.on('--app PATH') { |value| options[:app] = value }
    parser.on('--output PATH') { |value| options[:output] = value }
    parser.on('--identity SHA1') { |value| options[:identity] = value }
    parser.on('--notary-profile NAME') { |value| options[:profile] = value }
    parser.on('--sparkle-tools PATH') { |value| options[:tools] = value }
    parser.on('--keychain-account NAME') { |value| options[:account] = value }
  end.parse!
  C = BelugaMacClient
  C.require!(ARGV.empty? && options.keys.sort == %i[account app identity output profile tools], 'all six package options are required')
  config = C.config! # No output mutation or authentication until complete config.
  receipt = C::MicrophoneReceipt.new
  receipt.verify!
  source = C.source!
  app = C.canonical!(options[:app])
  output = C.empty_owned_directory!(options[:output])
  C.require!(!output.start_with?("#{C::ROOT}/") && !output.start_with?("#{app}/"), 'package output must be outside source/app')
  C.require!(/\A[0-9A-Fa-f]{40}\z/.match?(options[:identity]), 'exact Developer ID identity SHA1 is required')
  %i[profile account].each { |key| C.require!(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/.match?(options[key]), 'Keychain profile/account identifier is malformed') }
  tools = C.canonical!(options[:tools])
  C.tools!(tools)
  signer = File.join(tools, 'sign_update')
  public_reader = File.join(tools, 'generate_keys')
  # Bind the official tools to the pinned resolved SwiftPM artifact, not an
  # arbitrary caller-supplied executable with the same filename.
  sparkle_info = C.plist(File.join(tools, '../Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/Resources/Info.plist').then { |path| File.realpath(path) })
  C.require!(sparkle_info['CFBundleShortVersionString'] == C::SPARKLE_VERSION && sparkle_info['CFBundleVersion'] == '2064', 'tool distribution is not Sparkle 2.10.0')
  tool_bindings = [C.snapshot(signer), C.snapshot(public_reader)]
  verification = C.verify_app!(app, config)
  candidate_identity = C.candidate_identity!(verification.fetch('candidateIdentity'), config: config)
  build_report_path = File.join(File.dirname(app), 'build.json')
  C.regular!(build_report_path)
  build = JSON.parse(File.read(build_report_path))
  C.require!(build['schema'] == 'beluga.mac-client-build.v1' && build['status'] == 'SIGNED_VERIFIED_NOT_NOTARIZED' && build['commit'] == source['commit'] && build['tree'] == source['tree'] && build['app'] == app && build['appSHA256'] == verification['appSHA256'] && build['identitySHA1'] == options[:identity].upcase, 'source-bound build report differs from app/identity')
  # generate_keys -p is lookup-only: it never generates, rotates, exports, or
  # persists a private key. The private key stays inside the Sparkle process.
  public_key = C.run(public_reader, '--account', options[:account], '-p').strip
  C.require!(public_key == config['publicEDKey'], 'Keychain updater public key differs from signed app/configuration')
  stage = File.join(output, 'image-root')
  FileUtils.mkdir(stage, mode: 0o700)
  staged_app = File.join(stage, 'Beluga Host.app')
  C.run('/usr/bin/ditto', '--noqtn', app, staged_app)
  File.symlink('/Applications', File.join(stage, 'Applications'))
  C.require!(C.tree_digest(staged_app) == verification['appSHA256'], 'DMG staging altered app bytes/aliases')
  dmg_name = "Beluga-Mac-#{config['version']}-#{config['build']}.dmg"
  dmg = File.join(output, dmg_name)
  C.run('/usr/bin/hdiutil', 'create', '-volname', "Beluga #{config['version']}", '-srcfolder', stage, '-fs', 'APFS', '-format', 'ULFO', dmg)
  C.run('/usr/bin/codesign', '--sign', options[:identity].upcase, '--timestamp', dmg)
  C.run('/usr/bin/codesign', '--verify', '--strict', '--verbose=2', dmg)
  receipt.verify!
  C.require!(C.source! == source && C.config! == config, 'source/configuration changed before notary submission')
  submission = JSON.parse(C.run('/usr/bin/xcrun', 'notarytool', 'submit', dmg, '--keychain-profile', options[:profile], '--wait', '--timeout', '20m', '--output-format', 'json', timeout: 1230))
  File.write(File.join(output, 'notary.json'), JSON.pretty_generate(submission) + "\n", mode: 'wx', perm: 0o600)
  C.require!(submission['status'] == 'Accepted' && submission['id'].is_a?(String) && /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.match?(submission['id']), 'notarization did not reach Accepted; preserve failed evidence and do not publish')
  C.run('/usr/bin/xcrun', 'stapler', 'staple', dmg)
  C.run('/usr/bin/xcrun', 'stapler', 'validate', dmg)
  C.run('/usr/sbin/spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg)
  C.run('/usr/bin/hdiutil', 'verify', dmg)
  # Verify the final read-only mounted DMG, not just the source used to create it.
  mount = File.join(output, 'mount')
  FileUtils.mkdir(mount, mode: 0o700)
  mounted = false
  begin
    C.run('/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', mount, dmg)
    mounted = true
    expected_root = ['Beluga Host.app', 'Applications']
    filesystem_metadata = %w[.fseventsd .Trashes .DS_Store]
    C.require!((Dir.children(mount) - expected_root - filesystem_metadata).empty? && expected_root.all? { |name| File.exist?(File.join(mount, name)) }, 'DMG contains an unexpected payload')
    C.require!(File.symlink?(File.join(mount, 'Applications')) && File.readlink(File.join(mount, 'Applications')) == '/Applications', 'DMG Applications alias differs')
    C.require!(C.tree_digest(File.join(mount, 'Beluga Host.app')) == verification['appSHA256'], 'final DMG app differs from verified app')
    C.run('/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', File.join(mount, 'Beluga Host.app'))
    mounted_identity = C.candidate_identity_for_app!(File.join(mount, 'Beluga Host.app'),
      config: config, expected_tree_sha256: verification['appSHA256'])
    C.require!(mounted_identity == candidate_identity, 'final mounted DMG candidate identity differs from verified app')
  ensure
    C.run('/usr/bin/hdiutil', 'detach', mount) if mounted
  end
  dmg_hash = Digest::SHA256.file(dmg).hexdigest
  size = File.size(dmg)
  C.require!([C.snapshot(signer), C.snapshot(public_reader)] == tool_bindings, 'Sparkle tools changed before signing')
  signature = C.run(signer, '--account', options[:account], '-p', dmg).strip
  C.run(signer, '--account', options[:account], '--verify', dmg, signature)
  appcast = File.join(output, 'appcast.xml')
  File.write(appcast, C.appcast(config, dmg_name, size, signature, candidate_identity: candidate_identity), mode: 'wx', perm: 0o644)
  # Sparkle 2.10 signs the feed in-place with the signature comment/header used by
  # SURequireSignedFeed. Do not edit the XML again after this call.
  C.run(signer, '--account', options[:account], appcast)
  C.run(signer, '--account', options[:account], '--verify', appcast)
  C.require!(C.run(public_reader, '--account', options[:account], '-p').strip == config['publicEDKey'], 'updater key changed during package signing')
  C.require!(File.size(dmg) == size && Digest::SHA256.file(dmg).hexdigest == dmg_hash && [C.snapshot(signer), C.snapshot(public_reader)] == tool_bindings, 'payload/tools changed during signing')
  receipt.verify!
  C.require!(C.source! == source && C.config! == config && C.tree_digest(app) == verification['appSHA256'], 'source/app changed before distribution handoff')
  report = {
    'schema' => 'beluga.mac-client-package.v1', 'status' => 'NOTARIZED_STAPLED_SIGNED_DISTRIBUTION_READY',
    'version' => config['version'], 'build' => config['build'], 'commit' => source['commit'], 'tree' => source['tree'],
    'dmg' => dmg, 'dmgSHA256' => dmg_hash, 'dmgLength' => size, 'notarySubmissionID' => submission['id'],
    'appSHA256' => verification['appSHA256'], 'appcast' => appcast, 'appcastSHA256' => Digest::SHA256.file(appcast).hexdigest,
    'candidateIdentity' => candidate_identity,
    'releaseTag' => "mac-v#{config['version']}", 'publicEDKey' => config['publicEDKey'],
    'feedReleaseTag' => C::STABLE_FEED_RELEASE_TAG, 'feedURL' => config['feedURL'],
    'feedPromotion' => 'Publish and verify the immutable versioned DMG first; promote the signed stable-channel appcast last.',
    'published' => false, 'liveInstalled' => false, 'microphonePCMProven' => false
  }
  File.write(File.join(output, 'package.json'), JSON.pretty_generate(report) + "\n", mode: 'wx', perm: 0o600)
  puts JSON.pretty_generate(report)
rescue BelugaMacClient::Refusal, OptionParser::ParseError, SystemCallError, JSON::ParserError => error
  warn "package-beluga-mac-client: #{error.message}"
  exit 1
end
