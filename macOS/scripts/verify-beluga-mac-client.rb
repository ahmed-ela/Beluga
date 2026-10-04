#!/usr/bin/ruby
# frozen_string_literal: true
require_relative 'build-beluga-mac-client-contract'
require_relative 'retained-beluga-mac-client'
require_relative 'update-trial-artifact'
require 'optparse'

module BelugaMacClient
  def self.product_source_for!(app, binding)
    return source! if binding.nil?
    require!(binding.instance_of?(AdmittedRetainedProduct), 'product source requires filesystem-admitted retained evidence')
    binding.verify!(app)
    binding.product_source
  end

  def self.verify_app!(app, config = config!, product_binding: nil)
    require!(config == config!, 'production verification requires the production configuration')
    verify_bound_app!(app, config, product_binding: product_binding)
  end

  def self.verify_trial_app!(app, binding)
    admitted = trial_artifact_binding!(binding)
    verify_bound_app!(app, admitted.config, trial_binding: admitted)
  end

  def self.verify_release_metadata!(app, product_binding: nil, trial_binding: nil)
    trial_artifact_binding!(trial_binding) unless trial_binding.nil?
    require!(product_binding.nil? || trial_binding.nil?, 'retained and trial authority cannot be combined')
    if trial_binding
      binding = trial_artifact_binding!(trial_binding)
      config, expected_source = binding.config, binding.build_source
    else
      config, expected_source = config!, product_source_for!(app, product_binding)
    end
    bytes = []
    ['', BROKER].each do |relative|
      resources = File.join(app, relative, 'Contents/Resources')
      release = File.join(resources, 'Release.json')
      if trial_binding
        regular!(release)
        require!(File.size(release) <= 16 * 1024, 'trial bundled configuration exceeds bound')
        value = JSON.parse(File.binread(release), object_class: UniqueObject)
        require!(value.is_a?(Hash) && value['build'].instance_of?(Integer), 'trial bundled build must be an exact integer')
      else
        value = config!(release)
      end
      require!(value == config, 'bundled release configuration differs from artifact authority')
      provenance = File.join(resources, 'BuildSource.json')
      regular!(provenance)
      require!(File.size(provenance) <= 16 * 1024, 'bundled source binding exceeds bound')
      bytes << File.binread(provenance)
      require!(JSON.parse(bytes.last, object_class: UniqueObject) == expected_source, 'signed source binding differs from artifact authority')
    end
    require!(bytes[0] == bytes[1], 'broker signed source binding differs from host')
    info_path = File.join(app, 'Contents/Info.plist')
    # plutil's JSON conversion can erase plist real-vs-integer distinctions.
    paired_phone_catalog_plist!(info_path)
    ownership = run('/usr/bin/plutil', '-extract', 'BelugaUpdateOwnershipProtocol',
                    'raw', '-expect', 'integer', '-n', info_path)
    require!(ownership == '1', 'signed app does not declare exact updater ownership protocol1')
    info = plist(info_path)
    release_info(config).each { |key, value| require!(info[key] == value, "artifact Info.plist field differs: #{key}") }
    broker_info!(plist(File.join(app, BROKER, 'Contents/Info.plist')), config: config)
    trial_artifact_binding!(trial_binding) if trial_binding
    [config, expected_source]
  rescue JSON::ParserError
    raise Refusal, 'invalid bundled artifact metadata'
  end

  def self.verify_bound_app!(app, config, product_binding: nil, trial_binding: nil)
    expected_source = trial_binding ? trial_artifact_binding!(trial_binding).build_source : product_source_for!(app, product_binding)
    canonical!(app)
    before = tree_digest(app)
    aliases_and_tree!(app)
    paired_phone_catalog_plist!(File.join(app, 'Contents/Info.plist'))
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
      'BelugaPairedPhoneCatalogVersion' => PAIRED_PHONE_CATALOG_VERSION,
      'BelugaRendezvousURL' => rendezvous!(plist(File.join(ROOT, 'macOS/BelugaHost/Info.plist'))['BelugaRendezvousURL']),
      'NSAppleEventsUsageDescription' => 'Beluga reads playback information and controls Chrome and Music when you enable media integration.'
    }
    expected.each { |key, value| require!(info[key] == value, "Info.plist field differs: #{key}") }
    require!(verify_release_metadata!(app, product_binding: product_binding, trial_binding: trial_binding) == [config, expected_source], 'artifact metadata authority changed')
    broker = File.join(app, BROKER)
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
      versions = deployment_versions!(build_metadata, path: path, architectures: arches)
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
    require!(verify_release_metadata!(app, product_binding: product_binding, trial_binding: trial_binding) == [config, expected_source], 'product/source evidence changed during native verification')
    result = { 'schema' => 'beluga.mac-client-verification.v1', 'status' => 'VERIFIED_DISTRIBUTION_APP',
      'version' => config['version'], 'build' => config['build'], 'appSHA256' => before,
      'candidateIdentity' => candidate_identity,
      'liveInstalled' => false, 'microphonePCMProven' => false }
    return result unless trial_binding
    result.merge(trial_binding.report_fields).merge(
      'schema' => 'beluga.mac-client-update-trial-verification.v1', 'status' => 'VERIFIED_UPDATE_TRIAL_APP')
  end

  private_class_method :verify_bound_app!
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {}
    OptionParser.new do |parser|
      parser.on('--retained-admission PATH') { |value| options[:retained] = value }
      parser.on('--retained-sha256 SHA256') { |value| options[:sha256] = value }
      parser.on('--identity SHA1') { |value| options[:identity] = value }
    end.parse!
    BelugaMacClient.require!(ARGV.length == 1 && (options.empty? || options.keys.sort == %i[identity retained sha256]),
      'usage: ruby verify-beluga-mac-client.rb APP [--retained-admission PATH --retained-sha256 SHA256 --identity SHA1]')
    binding = unless options.empty?
      BelugaMacClient.require!(BelugaMacClient.package_evidence_mode!(ARGV.first, options[:retained], options[:sha256]) == :retained, 'retained verification requires unambiguous evidence')
      BelugaMacClient::AdmittedRetainedProduct.open(options[:retained], options[:sha256], receipt: BelugaMacClient::MicrophoneReceipt.new,
        app: ARGV.first, identity: options[:identity].upcase)
    end
    result = BelugaMacClient.verify_app!(ARGV.first, product_binding: binding)
    result = result.merge('provenance' => binding.provenance) if binding
    puts JSON.pretty_generate(result)
  rescue BelugaMacClient::Refusal, OptionParser::ParseError, SystemCallError, JSON::ParserError => error
    warn "verify-beluga-mac-client: #{error.message}"
    exit 1
  end
end
