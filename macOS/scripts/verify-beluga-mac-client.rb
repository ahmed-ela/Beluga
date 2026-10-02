#!/usr/bin/ruby
# frozen_string_literal: true
require_relative 'build-beluga-mac-client-contract'

module BelugaMacClient
  def self.verify_app!(app, config = config!)
    canonical!(app)
    before = tree_digest(app)
    aliases_and_tree!(app)
    info = plist(File.join(app, 'Contents/Info.plist'))
    expected = {
      'CFBundleIdentifier' => BUNDLE_ID, 'CFBundleExecutable' => 'CaptureServer',
      'CFBundleName' => 'Beluga Host', 'CFBundleDisplayName' => 'Beluga Host',
      'CFBundleIconFile' => 'AppIcon.icns', 'CFBundlePackageType' => 'APPL',
      'CFBundleShortVersionString' => config['version'], 'CFBundleVersion' => config['build'].to_s,
      'LSMinimumSystemVersion' => '14.0', 'LSUIElement' => true,
      'OpensteamerMediaIntegrationVersion' => 1,
      'SUFeedURL' => config['feedURL'], 'SUPublicEDKey' => config['publicEDKey'],
      'SUVerifyUpdateBeforeExtraction' => true, 'SURequireSignedFeed' => true,
      'SUAllowsAutomaticUpdates' => false,
      'BelugaUpdateOwnershipProtocol' => 1,
      'BelugaRendezvousURL' => rendezvous!(plist(File.join(ROOT, 'macOS/BelugaHost/Info.plist'))['BelugaRendezvousURL']),
      'NSAppleEventsUsageDescription' => 'Beluga reads playback information and controls Chrome and Music when you enable media integration.'
    }
    expected.each { |key, value| require!(info[key] == value, "Info.plist field differs: #{key}") }
    require!(config!(File.join(app, 'Contents/Resources/Release.json')) == config, 'bundled release configuration differs')
    bound_source = JSON.parse(File.read(File.join(app, 'Contents/Resources/BuildSource.json')))
    require!(bound_source == source!, 'signed source binding differs from clean checked-out release source')
    broker = File.join(app, BROKER)
    broker_info!(plist(File.join(broker, 'Contents/Info.plist')), config: config)
    require!(config!(File.join(broker, 'Contents/Resources/Release.json')) == config, 'broker release configuration differs')
    require!(File.binread(File.join(broker, 'Contents/Resources/BuildSource.json')) == File.binread(File.join(app, 'Contents/Resources/BuildSource.json')), 'broker signed source binding differs from host')
    require!(Digest::SHA256.file(File.join(broker, 'Contents/Resources/Sparkle-LICENSE.txt')).hexdigest == Digest::SHA256.file(File.join(ROOT, 'macOS/BelugaHost/Resources/Sparkle-LICENSE.txt')).hexdigest, 'broker Sparkle license differs from source')
    %w[THIRD_PARTY_NOTICES.md macOS/BelugaHost/Resources/Sparkle-LICENSE.txt].zip(%w[ThirdPartyNotices.md Sparkle-LICENSE.txt]).each do |source, resource|
      require!(Digest::SHA256.file(File.join(ROOT, source)).hexdigest == Digest::SHA256.file(File.join(app, 'Contents/Resources', resource)).hexdigest, 'bundled license/notices differ from source')
    end
    require!(Digest::SHA256.file(File.join(app, 'Contents/Resources/AppIcon.icns')).hexdigest == ICON_SHA, 'app icon differs')
    manifest = JSON.parse(File.read(File.join(app, 'Contents/Resources/org.example.opensteamer.media.json')))
    expected_manifest = {
      'name' => 'org.example.opensteamer.media', 'description' => 'opensteamer browser media bridge',
      'path' => '/Applications/opensteamer Host.app/Contents/MacOS/OpensteamerMediaBridge',
      'type' => 'stdio', 'allowed_origins' => ['chrome-extension://dhmdpbpcldmnkjfibepklolofapiceab/']
    }
    require!(manifest == expected_manifest, 'native media bridge manifest differs from compatibility contract')
    SPARKLE_COPIES.each do |framework|
      spine = "#{framework}/Versions/B"
      sparkle = plist(File.join(app, spine, 'Resources/Info.plist'))
      require!(sparkle['CFBundleShortVersionString'] == SPARKLE_VERSION && sparkle['CFBundleVersion'] == '2064' && sparkle['CFBundleIdentifier'] == 'org.sparkle-project.Sparkle', 'embedded Sparkle version/identity differs')
      {
        'Updater.app' => ['org.sparkle-project.Sparkle.Updater', 'Updater'],
        'XPCServices/Installer.xpc' => ['org.sparkle-project.InstallerLauncher', 'Installer'],
        'XPCServices/Downloader.xpc' => ['org.sparkle-project.DownloaderService', 'Downloader']
      }.each do |relative, (identifier, executable)|
        helper = File.join(app, spine, relative)
        helper_info = plist(File.join(helper, 'Contents/Info.plist'))
        require!(helper_info['CFBundleIdentifier'] == identifier && helper_info['CFBundleExecutable'] == executable, 'Sparkle helper bundle identity differs')
        verify_code!(helper, identifier)
      end
    end
    livekit = plist(File.join(app, LIVEKIT, 'Versions/A/Resources/Info.plist'))
    # The pinned package version is 144.7559.11, but its actual framework plist
    # intentionally reports 1.0. Do not invent a framework metadata version.
    require!(livekit['CFBundleIdentifier'] == 'io.livekit.LiveKitWebRTC' && livekit['CFBundleShortVersionString'] == '1.0' && livekit['CFBundleVersion'] == '1.0', 'embedded LiveKit metadata/identity differs')
    require!(run('/usr/bin/xattr', '-r', app).empty?, 'distribution app has extended attributes')
    host = File.join(app, 'Contents/MacOS/CaptureServer')
    require!(run('/usr/bin/lipo', '-archs', host).strip == 'arm64', 'this distribution profile is Apple-silicon-only')
    CODE.each do |relative, identifier|
      path = File.join(app, relative)
      loading = code_loading_contract!(relative)
      arches = run('/usr/bin/lipo', '-archs', path).strip.split(' ')
      require!(!arches.empty? && arches.uniq == arches && (arches - %w[arm64 x86_64]).empty? && arches.include?('arm64'), 'embedded code architecture mismatch')
      require!(!loading['compiledArm64'] || arches == ['arm64'], 'host/bridge/broker architecture mismatch')
      build_metadata = run('/usr/bin/vtool', '-show-build', path)
      versions = build_metadata.scan(/^\s*(?:minos|version)\s+(\d+(?:\.\d+){1,2})\s*$/).flatten
      require!(versions.length == arches.length, 'missing per-slice deployment target')
      require!(versions.all? { |version| ((version.split('.').map(&:to_i) + [0, 0, 0])[0, 3] <=> [14, 0, 0]) <= 0 }, 'embedded code requires a newer macOS')
      require!(!loading['compiledArm64'] || versions == ['14.0'], 'host/bridge/broker deployment target must be exactly 14.0')
      install_id = loading['installID']
      slice_count = verify_loading_contract!(relative, actual_rpaths: rpaths(path), dependency_output: run('/usr/bin/otool', '-L', path))
      require!(slice_count == arches.length, 'dependency parser did not cover every architecture')
      if install_id
        ids = run('/usr/bin/otool', '-D', path).lines.reject { |line| line.match?(/:\s*\z/) || line.strip.empty? }.map(&:strip)
        require!(ids == Array.new(arches.length, install_id), 'framework install ID differs')
      end
      verify_code!(path, identifier, host: relative == 'Contents/MacOS/CaptureServer')
    end
    verify_code!(broker, BROKER_ID)
    verify_code!(app, BUNDLE_ID, host: true)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', app)
    run(File.join(ROOT, 'macOS/scripts/verify-no-private-virtual-display-imports.sh'), host)
    aliases_and_tree!(app)
    candidate_identity = candidate_identity_for_app!(app, config: config, expected_tree_sha256: before)
    { 'schema' => 'beluga.mac-client-verification.v1', 'status' => 'VERIFIED_DISTRIBUTION_APP',
      'version' => config['version'], 'build' => config['build'], 'appSHA256' => before,
      'candidateIdentity' => candidate_identity,
      'liveInstalled' => false, 'microphonePCMProven' => false }
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    BelugaMacClient.require!(ARGV.length == 1, 'usage: ruby verify-beluga-mac-client.rb /absolute/Beluga\ Host.app')
    puts JSON.pretty_generate(BelugaMacClient.verify_app!(ARGV.first))
  rescue BelugaMacClient::Refusal, SystemCallError, JSON::ParserError => error
    warn "verify-beluga-mac-client: #{error.message}"
    exit 1
  end
end
