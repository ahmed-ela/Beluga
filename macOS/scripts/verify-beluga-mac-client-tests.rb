#!/usr/bin/ruby
# frozen_string_literal: true
# Offline policy tests only: no build, signing, Keychain, notary, app launch or routes.
require 'minitest/autorun'
require 'rexml/document'
require 'tmpdir'
require_relative 'build-beluga-mac-client-contract'

class BelugaMacClientContractTests < Minitest::Test
  C = BelugaMacClient
  def setup
    @directory = File.realpath(Dir.mktmpdir('beluga-mac-client-policy.'))
    File.chmod(0o700, @directory)
  end

  def teardown
    FileUtils.remove_entry_secure(@directory)
  end

  def config
    JSON.parse(File.read(C::CONFIG_PATH)).merge('publicEDKey' => Base64.strict_encode64('k' * 32))
  end

  def admit_config(value)
    path = File.join(@directory, 'Release.json')
    File.write(path, JSON.generate(value), perm: 0o600)
    C.config!(path)
  end

  def test_release_configuration_accepts_only_configured_exact_identity_version_and_feed
    assert_equal config, admit_config(config)
    mutations = {
      'publicEDKey' => [nil, '', Base64.strict_encode64("\0" * 32), Base64.strict_encode64('k' * 31), Base64.strict_encode64('k' * 32) + "\n"],
      'version' => ['01.2.0', '0.2', 'v0.2.0', '0.2.0-beta', '4294967296.2.0'],
      'build' => [0, -1, 99, '100', 1.2, 2**63],
      'sparkleVersion' => ['2.9.0', '2.10.1'], 'minimumSystemVersion' => ['13.0'],
      'bundleIdentifier' => ['com.example.new-host'], 'teamIdentifier' => ['OTHERTEAM1'],
      'feedURL' => ['http://github.com/ahmed-ela/Beluga/releases/download/mac-update-stable/appcast.xml', 'https://example.com/appcast.xml'],
      'repository' => ['other/repository'], 'schema' => ['beluga.mac-client-release.v2']
    }
    mutations.each do |key, values|
      values.each { |value| assert_raises(C::Refusal, "#{key}=#{value.inspect}") { admit_config(config.merge(key => value)) } }
    end
    assert_raises(C::Refusal) { admit_config(config.merge('unreviewed' => true)) }
    path = File.join(@directory, 'duplicate.json')
    File.write(path, JSON.generate(config).sub('"build":100', '"build":99,"build":100'), perm: 0o600)
    assert_raises(C::Refusal) { C.config!(path) }
  end

  def test_stable_mac_feed_is_independent_of_repository_latest_and_versioned_releases
    stable = 'https://github.com/ahmed-ela/Beluga/releases/download/mac-update-stable/appcast.xml'
    assert_equal stable, C::STABLE_FEED_URL
    assert_equal stable, admit_config(config)['feedURL']
    [
      'https://github.com/ahmed-ela/Beluga/releases/latest/download/appcast.xml',
      'https://github.com/ahmed-ela/Beluga/releases/download/mac-v0.2.0/appcast.xml',
      'https://github.com/ahmed-ela/Beluga/releases/download/mac-update-beta/appcast.xml',
      stable + '?channel=stable', stable + '#stable'
    ].each do |feed|
      assert_raises(C::Refusal) { admit_config(config.merge('feedURL' => feed)) }
    end
  end

  def test_ownership_protocol_producer_refuses_in_process_sdk_startup
    sources = {
      'macOS/Sources/CaptureServer/BelugaUpdateController.swift' => 'BelugaUpdateMenuClient.begin',
      'macOS/Sources/CaptureServer/BelugaUpdateMenuClient.swift' => 'BelugaUpdateBrokerArtifact.verifyStaged BelugaUpdateIPCChannel'
    }
    assert C.updater_source_contract!(sources)
    ['import Sparkle', 'SPUUpdater(', 'SPUStandardUpdaterController('].each do |unsafe|
      assert_raises(C::Refusal) { C.updater_source_contract!(sources.merge('extra.swift' => unsafe)) }
    end
    assert_raises(C::Refusal) { C.updater_source_contract!({}) }
    assert_raises(C::Refusal) { C.updater_source_contract!(sources.reject { |key, _| key.end_with?('BelugaUpdateMenuClient.swift') }) }
    assert C.updater_source_contract!
  end

  def test_source_text_boundaries_accept_utf8_bytes_under_c_locale_and_reject_invalid_bytes
    [Encoding::US_ASCII, Encoding::ASCII_8BIT].each do |encoding|
      source = "// π\n".dup.force_encoding(encoding).freeze
      assert_equal "// π\n", C.utf8_text(source, 'fixture')
      assert_equal encoding, source.encoding
      assert_equal "// π\n".bytes, source.bytes
      updater = {
        'macOS/Sources/CaptureServer/BelugaUpdateController.swift' => 'BelugaUpdateMenuClient.begin',
        'macOS/Sources/CaptureServer/BelugaUpdateMenuClient.swift' => 'BelugaUpdateBrokerArtifact.verifyStaged BelugaUpdateIPCChannel',
        'extra.swift' => source
      }
      assert C.updater_source_contract!(updater)
      assert C.catalog_source_contract!(catalog_sources.merge('extra.swift' => source))
      invalid = "\xFF".b
      assert_raises(C::Refusal) { C.updater_source_contract!(updater.merge('extra.swift' => invalid)) }
      assert_raises(C::Refusal) { C.catalog_source_contract!(catalog_sources.merge('extra.swift' => invalid)) }
    end
    assert_raises(C::Refusal) { C.utf8_text(nil, 'fixture') }
  end

  def catalog_sources
    {
      'macOS/Sources/CaptureServer/WorldwideHostCoordinator.swift' =>
        'store.phoneCatalog.loadOrMigrate(for: identity) snapshot.selectedRecord publishPresentation(.unselected) startAvailabilityLoop()',
      'macOS/Sources/CaptureServer/WorldwidePairingStore.swift' =>
        'WorldwidePairedPhoneCatalogStore.catalogAccount throw WorldwidePairingStoreError.catalogIsAuthoritative try requireLegacyNamespace() try requireLegacyNamespace() try requireLegacyNamespace()',
      'macOS/Sources/CaptureServer/WorldwidePairingBootstrap.swift' =>
        'try checkpoint.add(pending) try checkpoint.update(record)',
      'macOS/Sources/CaptureServer/WorldwidePairingCatalogCheckpoint.swift' =>
        'catalog.addPairedPhone( catalog.updatePairedPhone('
    }
  end

  def test_catalog_producer_requires_migration_checkpoint_routing_and_legacy_account_fence
    assert C.catalog_source_contract!(catalog_sources)
    catalog_sources.each_key do |path|
      assert_raises(C::Refusal, path) { C.catalog_source_contract!(catalog_sources.reject { |key, _| key == path }) }
    end
    coordinator = 'macOS/Sources/CaptureServer/WorldwideHostCoordinator.swift'
    [
      catalog_sources[coordinator].sub('store.phoneCatalog.loadOrMigrate(for: identity)', ''),
      'startAvailabilityLoop() ' + catalog_sources[coordinator],
      catalog_sources[coordinator].sub('snapshot.selectedRecord', ''),
      catalog_sources[coordinator].sub('publishPresentation(.unselected)', ''),
      catalog_sources[coordinator] + ' store.savePairedViewer(record, for: identity)'
    ].each do |source|
      assert_raises(C::Refusal) { C.catalog_source_contract!(catalog_sources.merge(coordinator => source)) }
    end
    store = 'macOS/Sources/CaptureServer/WorldwidePairingStore.swift'
    ['WorldwidePairedPhoneCatalogStore.catalogAccount',
     'throw WorldwidePairingStoreError.catalogIsAuthoritative', 'try requireLegacyNamespace()'].each do |text|
      changed = catalog_sources[store].sub(text, '')
      assert_raises(C::Refusal) { C.catalog_source_contract!(catalog_sources.merge(store => changed)) }
    end
    bootstrap = 'macOS/Sources/CaptureServer/WorldwidePairingBootstrap.swift'
    ['try checkpoint.add(pending)', 'try checkpoint.update(record)'].each do |text|
      changed = catalog_sources[bootstrap].sub(text, '')
      assert_raises(C::Refusal) { C.catalog_source_contract!(catalog_sources.merge(bootstrap => changed)) }
    end
    assert_raises(C::Refusal) do
      C.catalog_source_contract!(catalog_sources.merge(bootstrap => catalog_sources[bootstrap] + ' store.savePairedViewer(record)'))
    end
    checkpoint = 'macOS/Sources/CaptureServer/WorldwidePairingCatalogCheckpoint.swift'
    ['catalog.addPairedPhone(', 'catalog.updatePairedPhone('].each do |text|
      changed = catalog_sources[checkpoint].sub(text, '')
      assert_raises(C::Refusal) { C.catalog_source_contract!(catalog_sources.merge(checkpoint => changed)) }
    end
    assert C.catalog_source_contract!
  end

  def test_catalog_marker_is_exact_integer_not_boolean_string_float_missing_or_future_version
    assert C.paired_phone_catalog_info!('BelugaPairedPhoneCatalogVersion' => 1)
    [nil, [], {}, { 'BelugaPairedPhoneCatalogVersion' => nil }].each do |value|
      assert_raises(C::Refusal) { C.paired_phone_catalog_info!(value) }
    end
    [true, false, '1', 0, 2, -1, 1.0, 1.5, [1]].each do |value|
      assert_raises(C::Refusal) { C.paired_phone_catalog_info!('BelugaPairedPhoneCatalogVersion' => value) }
    end
  end

  def test_paths_refuse_symlink_ancestors_shared_or_nonempty_directories_and_hardlinks
    assert_equal @directory, C.empty_owned_directory!(@directory)
    path = File.join(@directory, 'record')
    File.write(path, 'evidence', perm: 0o600)
    assert_raises(C::Refusal) { C.empty_owned_directory!(@directory) }
    File.link(path, File.join(@directory, 'alias'))
    assert_raises(C::Refusal) { C.regular!(path) }
    File.unlink(File.join(@directory, 'alias'))
    File.symlink(path, File.join(@directory, 'symlink'))
    assert_raises(C::Refusal) { C.regular!(File.join(@directory, 'symlink')) }
    File.chmod(0o666, path)
    assert_raises(C::Refusal) { C.regular!(path) }
  end

  def test_rendezvous_requires_canonical_public_wss_base_without_credentials_or_query
    value = 'wss://audiostreamer-rendezvous.elaminahmed03.workers.dev'
    assert_equal value, C.rendezvous!(value)
    [nil, '', 'ws://example.com', 'wss://127.0.0.1', 'wss://test.invalid',
     'wss://user:secret@example.com', 'wss://example.com?token=secret',
     'wss://example.com#secret', 'wss://example.com:444', 'wss://example.com/v1/rendezvous'].each do |candidate|
      assert_raises(C::Refusal) { C.rendezvous!(candidate) }
    end
  end

  def signed_metadata
    "Identifier=#{C::BUNDLE_ID}\nCodeDirectory=v=20500 size=123 flags=0x10000(runtime) hashes=3\nAuthority=Developer ID Application: Reviewed Owner (#{C::TEAM})\nAuthority=Developer ID Certification Authority\nTeamIdentifier=#{C::TEAM}\nTimestamp=Oct 2, 2026 at 12:00:00 PM\n"
  end

  def test_codesign_parser_rejects_duplicate_identity_development_adhoc_no_runtime_or_no_timestamp
    assert_equal C::BUNDLE_ID, C.signature_fields!(signed_metadata)['Identifier']
    [signed_metadata + "Identifier=other\n", signed_metadata + "TeamIdentifier=#{C::TEAM}\n",
     signed_metadata.sub('Developer ID Application:', 'Apple Development:'),
     signed_metadata.sub('runtime', 'adhoc'), signed_metadata.sub(/^Timestamp=.*\n/, ''),
     signed_metadata.sub(C::TEAM, 'OTHERTEAM1')].each do |value|
      assert_raises(C::Refusal) { C.signature_fields!(value) }
    end
  end

  def test_exact_entitlements_preserve_media_permission_without_debug_or_library_validation_exceptions
    C.entitlements!({})
    C.entitlements!({ 'com.apple.security.automation.apple-events' => true }, host: true)
    %w[com.apple.security.get-task-allow com.apple.security.cs.disable-library-validation com.apple.security.cs.allow-jit com.apple.security.cs.allow-unsigned-executable-memory].each do |key|
      assert_raises(C::Refusal) { C.entitlements!({ key => true }) }
      assert_raises(C::Refusal) { C.entitlements!({ 'com.apple.security.automation.apple-events' => true, key => true }, host: true) }
    end
    assert_raises(C::Refusal) { C.entitlements!({}, host: true) }
  end

  def otool(dependencies, slices: 1)
    Array.new(slices) do |index|
      "/private/owned/Beluga Host.app/Contents/MacOS/CaptureServer (architecture slice#{index}):\n" + dependencies.map { |dependency| "\t#{dependency} (compatibility version 1.0.0, current version 1.0.0)\n" }.join
    end.join
  end

  def test_dependencies_bind_both_frameworks_per_slice_and_reject_dyld_escape_or_duplicate
    system = '/usr/lib/libSystem.B.dylib'
    expected = [C::LIVEKIT_INSTALL, C::SPARKLE_INSTALL]
    assert_equal 2, C.dependencies!(otool(expected + [system], slices: 2), expected)
    assert_equal 1, C.dependencies!(otool([system]), [])
    assert_equal 1, C.dependencies!(otool([C::SPARKLE_INSTALL, system]), [], install_id: C::SPARKLE_INSTALL)
    [[], [C::LIVEKIT_INSTALL, system], expected + [C::SPARKLE_INSTALL], expected + ['@rpath/Evil.framework/Evil'], expected + ['/tmp/library.dylib'], expected + ['@loader_path/../Evil']].each do |dependencies|
      assert_raises(C::Refusal) { C.dependencies!(otool(dependencies), expected) }
    end
    assert_raises(C::Refusal) { C.dependencies!(otool([system]), [C::SPARKLE_INSTALL]) }
    assert_raises(C::Refusal) { C.dependencies!(otool([]), []) }
  end

  def test_embedded_broker_loading_contract_requires_its_own_sparkle_only
    host = C.code_loading_contract!('Contents/MacOS/CaptureServer')
    assert_equal [C::LIVEKIT_INSTALL, C::SPARKLE_INSTALL], host['dependencies']
    assert_equal [C::HOST_RPATH], host['rpaths']
    broker = C.code_loading_contract!(C::BROKER_EXECUTABLE)
    assert_equal [C::SPARKLE_INSTALL], broker['dependencies']
    assert_equal [C::HOST_RPATH], broker['rpaths']
    assert broker['compiledArm64']
    assert_equal 1, C.verify_loading_contract!(C::BROKER_EXECUTABLE, actual_rpaths: [C::HOST_RPATH], dependency_output: otool([C::SPARKLE_INSTALL, '/usr/lib/libSystem.B.dylib']))
    [[], [C::SPARKLE_INSTALL, C::LIVEKIT_INSTALL], [C::SPARKLE_INSTALL, '@rpath/Other.framework/Other'], [C::SPARKLE_INSTALL, '@loader_path/../../../../Frameworks/Sparkle.framework/Versions/B/Sparkle']].each do |dependencies|
      assert_raises(C::Refusal) do
        C.verify_loading_contract!(C::BROKER_EXECUTABLE, actual_rpaths: [C::HOST_RPATH], dependency_output: otool(dependencies))
      end
    end
    [[], [C::HOST_RPATH, C::HOST_RPATH], ['@executable_path/../../../../Frameworks'], ['/tmp/frameworks']].each do |rpaths|
      assert_raises(C::Refusal) do
        C.verify_loading_contract!(C::BROKER_EXECUTABLE, actual_rpaths: rpaths, dependency_output: otool([C::SPARKLE_INSTALL]))
      end
    end
    C::SPARKLE_COPIES.each do |framework|
      relative = "#{framework}/Versions/B/Sparkle"
      assert_equal C::SPARKLE_INSTALL, C.code_loading_contract!(relative)['installID']
      assert_equal 2, C.verify_loading_contract!(relative, actual_rpaths: [], dependency_output: otool([C::SPARKLE_INSTALL, '/usr/lib/libSystem.B.dylib'], slices: 2))
      assert_raises(C::Refusal) { C.verify_loading_contract!(relative, actual_rpaths: [C::HOST_RPATH], dependency_output: otool([C::SPARKLE_INSTALL])) }
    end
    assert_raises(C::Refusal) { C.code_loading_contract!('Contents/Helpers/Other.app/Contents/MacOS/Other') }
  end

  def test_broker_metadata_seals_release_values_and_refuses_permission_or_updater_aliases
    expected = C.broker_info(config)
    C.broker_info!(expected, config: config)
    assert_equal C::BROKER_ID, expected['CFBundleIdentifier']
    assert_equal 'BelugaUpdater', expected['CFBundleExecutable']
    assert_equal config['feedURL'], expected['SUFeedURL']
    assert_equal config['publicEDKey'], expected['SUPublicEDKey']
    {
      'CFBundleIdentifier' => C::BUNDLE_ID, 'CFBundleExecutable' => 'CaptureServer',
      'CFBundleShortVersionString' => '0.1.0', 'CFBundleVersion' => '99',
      'LSMinimumSystemVersion' => '13.0', 'LSUIElement' => false,
      'SUFeedURL' => 'https://example.com/feed.xml', 'SUPublicEDKey' => Base64.strict_encode64('x' * 32),
      'SURequireSignedFeed' => false, 'SUVerifyUpdateBeforeExtraction' => false,
      'SUAllowsAutomaticUpdates' => true
    }.each do |key, value|
      assert_raises(C::Refusal) { C.broker_info!(expected.merge(key => value), config: config) }
    end
    %w[NSAppleEventsUsageDescription NSMicrophoneUsageDescription SUEnableInstallerLauncherService SUEnableDownloaderService].each do |key|
      assert_raises(C::Refusal) { C.broker_info!(expected.merge(key => true), config: config) }
    end
    assert_raises(C::Refusal) { C.broker_info!(expected.reject { |key, _| key == 'SUPublicEDKey' }, config: config) }
    C.entitlements!({})
    assert_raises(C::Refusal) { C.entitlements!({ 'com.apple.security.automation.apple-events' => true }) }
  end

  def test_both_sparkle_closures_have_fixed_executables_aliases_and_inside_out_signing
    assert_equal 14, C::CODE.length
    assert_equal C::BROKER_ID, C::CODE.fetch(C::BROKER_EXECUTABLE)
    signing = C.nested_signing_contract
    assert_equal signing.length, signing.map(&:first).uniq.length
    C::SPARKLE_COPIES.each do |framework|
      assert_equal 5, C::CODE.keys.count { |relative| relative.start_with?("#{framework}/") }
      assert_equal 9, C::ALIASES.keys.count { |relative| relative.start_with?("#{framework}/") }
      spine = "#{framework}/Versions/B"
      ["#{spine}/XPCServices/Installer.xpc", "#{spine}/XPCServices/Downloader.xpc", "#{spine}/Autoupdate", "#{spine}/Updater.app"].each do |child|
        assert_operator signing.map(&:first).index(child), :<, signing.map(&:first).index(framework)
      end
    end
    assert_operator signing.map(&:first).index(C::BROKER_SPARKLE), :<, signing.map(&:first).index(C::BROKER_EXECUTABLE)
    assert_operator signing.map(&:first).index(C::BROKER_EXECUTABLE), :<, signing.map(&:first).index(C::BROKER)
    refute_includes signing.map(&:first), 'Contents/MacOS/CaptureServer'
  end

  def fake_app
    app = File.join(@directory, 'Beluga Host.app')
    dirs = %w[Contents Contents/MacOS Contents/Resources Contents/_CodeSignature Contents/Frameworks Contents/Helpers]
    dirs += [C::BROKER] + %w[Contents Contents/MacOS Contents/Resources Contents/_CodeSignature Contents/Frameworks].map { |relative| "#{C::BROKER}/#{relative}" }
    dirs += [C::LIVEKIT, "#{C::LIVEKIT}/Versions", "#{C::LIVEKIT}/Versions/A", "#{C::LIVEKIT}/Versions/A/Versions", "#{C::LIVEKIT}/Versions/A/Versions/A", "#{C::LIVEKIT}/Versions/A/Versions/A/Resources"]
    dirs += %w[Headers Modules Resources _CodeSignature].map { |name| "#{C::LIVEKIT}/Versions/A/#{name}" }
    C::SPARKLE_COPIES.each do |framework|
      spine = "#{framework}/Versions/B"
      dirs += [framework, "#{framework}/Versions", spine]
      dirs += %w[Headers Modules PrivateHeaders Resources _CodeSignature XPCServices].map { |name| "#{spine}/#{name}" }
    end
    dirs.each { |relative| FileUtils.mkdir_p(File.join(app, relative), mode: 0o755) }
    C::CODE.each_key do |relative|
      path = File.join(app, relative)
      FileUtils.mkdir_p(File.dirname(path), mode: 0o755)
      File.write(path, 'fixture bytes', perm: 0o755)
    end
    %w[AppIcon.icns BuildSource.json Release.json Sparkle-LICENSE.txt ThirdPartyNotices.md org.example.opensteamer.media.json].each { |name| File.write(File.join(app, 'Contents/Resources', name), '{}', perm: 0o644) }
    %w[BuildSource.json Release.json Sparkle-LICENSE.txt].each { |name| File.write(File.join(app, C::BROKER, 'Contents/Resources', name), '{}', perm: 0o644) }
    File.write(File.join(app, 'Contents/Info.plist'),
      '<plist version="1.0"><dict><key>BelugaPairedPhoneCatalogVersion</key><integer>1</integer></dict></plist>', perm: 0o644)
    File.write(File.join(app, C::BROKER, 'Contents/Info.plist'), '{}', perm: 0o644)
    File.write(File.join(app, "#{C::LIVEKIT}/Versions/A/Versions/A/Resources/PrivacyInfo.xcprivacy"), '{}', perm: 0o644)
    C::ALIASES.each { |relative, destination| File.symlink(destination, File.join(app, relative)) }
    Find.find(app) do |path|
      info = File.lstat(path)
      next if info.symlink?
      relative = path.delete_prefix("#{app}/")
      File.chmod(info.directory? || C::CODE.key?(relative) ? 0o755 : 0o644, path)
    end
    app
  end

  def test_bundle_structure_accepts_exact_closure_and_rejects_extra_executable_symlink_or_resource
    app = fake_app
    C.aliases_and_tree!(app)
    extra = File.join(app, 'Contents/MacOS/DriverInstaller')
    File.write(extra, 'not allowed', perm: 0o755)
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
    File.unlink(extra)
    extra = File.join(app, 'Contents/Resources/unreviewed.txt')
    File.write(extra, 'not allowed', perm: 0o644)
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
    File.unlink(extra)
    extra = File.join(app, C::SPARKLE_B, 'Resources/Evil.dylib')
    File.write(extra, [0xfeedfacf].pack('N'), perm: 0o644)
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
    File.unlink(extra)
    alias_path = File.join(app, C::SPARKLE, 'Versions/Current')
    File.unlink(alias_path)
    File.symlink('/tmp', alias_path)
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
  end

  def test_embedded_broker_rejects_stray_helpers_livekit_and_missing_framework_alias
    app = fake_app
    C.aliases_and_tree!(app)
    extra = File.join(app, 'Contents/Helpers/Unexpected.app')
    Dir.mkdir(extra, 0o755)
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
    Dir.rmdir(extra)
    extra = File.join(app, C::BROKER, 'Contents/Frameworks/LiveKitWebRTC.framework')
    Dir.mkdir(extra, 0o755)
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
    Dir.rmdir(extra)
    extra = File.join(app, C::BROKER, 'Contents/MacOS/StrayUpdater')
    File.write(extra, 'stray', perm: 0o755)
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
    File.unlink(extra)
    alias_path = File.join(app, C::BROKER_SPARKLE, 'Autoupdate')
    File.unlink(alias_path)
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
    File.symlink('Versions/Current/Autoupdate', alias_path)
    C.aliases_and_tree!(app)
    File.unlink(File.join(app, C::BROKER_SPARKLE, 'Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader'))
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
  end

  def test_broker_sparkle_alias_cannot_resolve_the_outer_copy
    app = fake_app
    alias_path = File.join(app, C::BROKER_SPARKLE, 'Versions/Current')
    File.unlink(alias_path)
    File.symlink(File.join(app, C::SPARKLE_B), alias_path)
    assert_raises(C::Refusal) { C.aliases_and_tree!(app) }
  end

  def test_tree_digest_detects_byte_permission_and_alias_changes
    app = fake_app
    initial = C.tree_digest(app)
    path = File.join(app, 'Contents/MacOS/CaptureServer')
    File.write(path, 'changed bytes')
    refute_equal initial, C.tree_digest(app)
    second = C.tree_digest(app)
    File.chmod(0o644, path)
    refute_equal second, C.tree_digest(app)
  end

  def test_bundle_tree_v1_has_exact_preorder_json_modes_file_hash_and_link_bytes
    root = File.join(@directory, 'tree')
    FileUtils.mkdir(root, mode: 0o755)
    # Deliberately create out of lexical order. The digest is an ordered tree
    # traversal, not the filesystem's creation/directory enumeration order.
    File.write(File.join(root, 'z'), 'last', perm: 0o644)
    FileUtils.mkdir(File.join(root, 'a'), mode: 0o755)
    File.write(File.join(root, 'a/marker'), 'signed bytes', perm: 0o644)
    File.symlink('a/marker', File.join(root, 'link'))
    File.chmod(0o755, root, File.join(root, 'a'))
    File.chmod(0o644, File.join(root, 'z'), File.join(root, 'a/marker'))
    File.lchmod(0o755, File.join(root, 'link'))
    expected_stream = '["",493,"directory"]' +
      '["/a",493,"directory"]' +
      '["/a/marker",420,"file"]' + Digest::SHA256.hexdigest('signed bytes') +
      '["/link",493,"link"]a/marker' +
      '["/z",420,"file"]' + Digest::SHA256.hexdigest('last')
    assert_equal Digest::SHA256.hexdigest(expected_stream), C.tree_digest(root)
    File.unlink(File.join(root, 'link'))
    File.symlink('./a/marker', File.join(root, 'link'))
    File.lchmod(0o755, File.join(root, 'link'))
    refute_equal Digest::SHA256.hexdigest(expected_stream), C.tree_digest(root)
  end

  def test_bundle_tree_native_reader_shared_unicode_and_escaping_vector
    root = File.join(@directory, 'native-tree')
    FileUtils.mkdir_p(File.join(root, 'Contents/MacOS'), mode: 0o755)
    executable = File.join(root, 'Contents/MacOS/CaptureServer')
    File.write(executable, 'fixture bytes', perm: 0o755)
    File.chmod(0o755, root, File.join(root, 'Contents'), File.join(root, 'Contents/MacOS'), executable)
    ["🦈", "中", "π", "quoted\"\\\nπ", "Z"].each do |name|
      path = File.join(root, name)
      File.write(path, 'value', perm: 0o644)
      File.chmod(0o644, path)
    end
    assert_equal 'e68bcee4217c4f0b0899fe10a45f77f3daa719d0d8daa14f535ed2ad8f7654dd', C.tree_digest(root)
    renamed = File.join(@directory, 'native-tree-π')
    File.rename(root, renamed)
    [Encoding::UTF_8, Encoding::US_ASCII, Encoding::ASCII_8BIT].each do |encoding|
      path = renamed.dup.force_encoding(encoding).freeze
      assert_equal 'e68bcee4217c4f0b0899fe10a45f77f3daa719d0d8daa14f535ed2ad8f7654dd', C.tree_digest(path)
      assert_equal encoding, path.encoding
    end
  end

  def test_bundle_tree_refuses_invalid_utf8_names_before_serialization
    root = File.join(@directory, 'native-tree')
    visitor = ->(_path, &block) { block.call(root.b + "/\xFF".b) }
    Find.stub(:find, visitor) do
      error = assert_raises(C::Refusal) { C.tree_digest(root) }
      assert_equal 'bundle tree relative path is not valid UTF-8', error.message
    end
  end

  def candidate_identity
    { 'schema' => C::CANDIDATE_IDENTITY_SCHEMA, 'version' => '0.2.0', 'build' => 100,
      'executableSHA256' => 'a' * 64, 'bundleTreeSHA256' => 'b' * 64,
      'bundleTreeAlgorithm' => C::BUNDLE_TREE_ALGORITHM }
  end

  def test_candidate_identity_is_derived_from_actual_executable_and_full_signed_app_tree
    app = fake_app
    signature_resource = File.join(app, 'Contents/_CodeSignature/CodeResources')
    File.write(signature_resource, 'actual signed resource bytes', perm: 0o644)
    tree = C.tree_digest(app)
    identity = C.candidate_identity_for_app!(app, config: config, expected_tree_sha256: tree)
    assert_equal candidate_identity.merge(
      'executableSHA256' => Digest::SHA256.hexdigest('fixture bytes'),
      'bundleTreeSHA256' => tree), identity
    assert identity.frozen?
    File.write(signature_resource, 'changed signature resources')
    assert_raises(C::Refusal) do
      C.candidate_identity_for_app!(app, config: config, expected_tree_sha256: tree)
    end
    changed_tree = C.tree_digest(app)
    changed = C.candidate_identity_for_app!(app, config: config, expected_tree_sha256: changed_tree)
    assert_equal identity['executableSHA256'], changed['executableSHA256']
    refute_equal identity['bundleTreeSHA256'], changed['bundleTreeSHA256']
    File.write(File.join(app, 'Contents/MacOS/CaptureServer'), 'different executable')
    assert_raises(C::Refusal) do
      C.candidate_identity_for_app!(app, config: config, expected_tree_sha256: changed_tree)
    end
    assert_raises(C::Refusal) do
      C.candidate_identity_for_app!(app, config: config, expected_tree_sha256: nil)
    end
  end

  def test_candidate_identity_cannot_stamp_v2_onto_an_app_with_old_or_missing_catalog_marker
    app = fake_app
    info = File.join(app, 'Contents/Info.plist')
    [
      '<plist version="1.0"><dict></dict></plist>',
      '<plist version="1.0"><dict><key>BelugaPairedPhoneCatalogVersion</key><integer>2</integer></dict></plist>',
      '<plist version="1.0"><dict><key>BelugaPairedPhoneCatalogVersion</key><true/></dict></plist>',
      '<plist version="1.0"><dict><key>BelugaPairedPhoneCatalogVersion</key><string>1</string></dict></plist>',
      '<plist version="1.0"><dict><key>BelugaPairedPhoneCatalogVersion</key><real>1.0</real></dict></plist>'
    ].each do |bytes|
      %w[xml1 binary1].each do |format|
        File.write(info, bytes, perm: 0o644)
        C.run('/usr/bin/plutil', '-convert', format, info)
        assert_raises(C::Refusal) do
          C.candidate_identity_for_app!(app, config: config, expected_tree_sha256: C.tree_digest(app))
        end
      end
    end
  end

  def test_producer_admits_only_v2_catalog_contract_even_for_high_build_candidate
    high = config.merge('build' => 1_000_000)
    identity = candidate_identity.merge('build' => high['build'])
    assert_equal 'beluga.update-candidate.v2', C.candidate_identity!(identity, config: high)['schema']
    ['beluga.update-candidate.v1', 'beluga.update-candidate.v3'].each do |schema|
      assert_raises(C::Refusal) { C.candidate_identity!(identity.merge('schema' => schema), config: high) }
    end
    source = File.read(File.join(C::ROOT, 'macOS/scripts/build-beluga-mac-client-contract.rb'))
    source_body = source.split('def self.source!', 2).last.split('def self.updater_source_contract!', 2).first
    assert_includes source_body, 'catalog_source_contract!'
    builder = File.read(File.join(C::ROOT, 'macOS/scripts/build-beluga-mac-client.rb'))
    verifier = File.read(File.join(C::ROOT, 'macOS/scripts/verify-beluga-mac-client.rb'))
    assert_includes builder, "'BelugaPairedPhoneCatalogVersion' => C::PAIRED_PHONE_CATALOG_VERSION"
    assert_includes verifier, "'BelugaPairedPhoneCatalogVersion' => PAIRED_PHONE_CATALOG_VERSION"
    assert_operator verifier.index("paired_phone_catalog_plist!(File.join(app, 'Contents/Info.plist'))"), :<,
                    verifier.index('candidate_identity = candidate_identity_for_app!')
  end

  def test_candidate_identity_rejects_wrong_schema_unknown_missing_or_malformed_fields
    assert_equal candidate_identity, C.candidate_identity!(candidate_identity, config: config)
    [nil, [], 'identity', candidate_identity.merge('unreviewed' => true),
     candidate_identity.reject { |key, _| key == 'bundleTreeSHA256' },
     candidate_identity.merge(:schema => C::CANDIDATE_IDENTITY_SCHEMA)].each do |value|
      assert_raises(C::Refusal) { C.candidate_identity!(value, config: config) }
    end
    mutations = {
      'schema' => [nil, '', 'beluga.update-candidate.v1', 'beluga.update-candidate.v3'],
      'version' => [nil, 2, '0.2.1', '00.2.0', "0.2.0\n", '4294967296.2.0'],
      'build' => [nil, true, 0, -1, '100', 100.0, 101, 2**63],
      'executableSHA256' => [nil, 3, '', 'a' * 63, 'A' * 64, 'a' * 64 + "\n"],
      'bundleTreeSHA256' => [nil, [], '', 'b' * 65, 'B' * 64, 'b' * 64 + "\n"],
      'bundleTreeAlgorithm' => [nil, 1, '', 'beluga.executable-only.v1']
    }
    mutations.each do |key, values|
      values.each do |value|
        assert_raises(C::Refusal, key) { C.candidate_identity!(candidate_identity.merge(key => value), config: config) }
      end
    end
  end

  def test_appcast_contains_exact_signed_payload_version_arm64_and_public_github_release_url
    signature = Base64.strict_encode64('s' * 64)
    name = 'Beluga-Mac-0.2.0-100.dmg'
    xml = C.appcast(config, name, 12345, signature, Time.utc(2026, 10, 2), candidate_identity: candidate_identity)
    assert_includes xml, 'https://github.com/ahmed-ela/Beluga/releases/download/mac-v0.2.0/Beluga-Mac-0.2.0-100.dmg'
    assert_includes xml, '<sparkle:version>100</sparkle:version>'
    assert_includes xml, '<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>'
    assert_includes xml, "length=\"12345\""
    assert_includes xml, "sparkle:edSignature=\"#{signature}\""
    document = REXML::Document.new(xml)
    enclosure = document.elements['rss/channel/item/enclosure']
    assert_equal C::CANDIDATE_XML_NAMESPACE, document.root.namespace('beluga')
    assert_equal C::CANDIDATE_IDENTITY_SCHEMA, enclosure.attributes['beluga:artifactSchema']
    assert_equal 'a' * 64, enclosure.attributes['beluga:executableSHA256']
    assert_equal 'b' * 64, enclosure.attributes['beluga:bundleTreeSHA256']
    assert_equal C::BUNDLE_TREE_ALGORITHM, enclosure.attributes['beluga:bundleTreeAlgorithm']
    assert_equal %w[beluga:artifactSchema beluga:bundleTreeAlgorithm beluga:bundleTreeSHA256 beluga:executableSHA256],
      enclosure.attributes.each_attribute.map(&:expanded_name).select { |name| name.start_with?('beluga:') }.sort
    assert_nil document.elements['rss/channel/item/sparkle:deltas']
    assert_raises(C::Refusal) { C.appcast(config, 'wrong.dmg', 12345, signature, candidate_identity: candidate_identity) }
    assert_raises(C::Refusal) { C.appcast(config, name, 0, signature, candidate_identity: candidate_identity) }
    assert_raises(C::Refusal) { C.appcast(config, name, 12345, Base64.strict_encode64('x' * 63), candidate_identity: candidate_identity) }
    assert_raises(ArgumentError) { C.appcast(config, name, 12345, signature) }
  end

  def test_appcast_refuses_malformed_or_release_mismatched_candidate_metadata_before_xml_generation
    signature = Base64.strict_encode64('s' * 64)
    [nil, candidate_identity.merge('build' => 101), candidate_identity.merge('version' => '0.2.1'),
     candidate_identity.merge('executableSHA256' => 'A' * 64),
     candidate_identity.merge('unknown' => 'ignored')].each do |value|
      assert_raises(C::Refusal) do
        C.appcast(config, 'Beluga-Mac-0.2.0-100.dmg', 12345, signature, candidate_identity: value)
      end
    end
  end

  def test_package_binds_final_mounted_candidate_metadata_before_whole_feed_signing
    package = File.read(File.join(C::ROOT, 'macOS/scripts/package-beluga-mac-client.rb'))
    mounted = package.index('mounted_identity = C.candidate_identity_for_app!')
    equality = package.index('C.require!(mounted_identity == candidate_identity')
    xml = package.index('C.appcast(config, dmg_name, size, signature, candidate_identity: candidate_identity)')
    whole_feed_signing = package.index("C.run(signer, '--account', options[:account], appcast)")
    refute_nil mounted
    refute_nil equality
    refute_nil xml
    refute_nil whole_feed_signing
    assert_operator mounted, :<, equality
    assert_operator equality, :<, xml
    assert_operator xml, :<, whole_feed_signing
  end

  def test_microphone_receipt_brackets_exact_runner_invocation_and_refuses_changed_receipt
    path = File.join(@directory, 'receipt.json')
    File.write(path, 'source-bound offline fixture', perm: 0o600)
    previous_path = ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT']
    previous_sha = ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256']
    ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT'] = path
    ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256'] = Digest::SHA256.file(path).hexdigest
    invocations = []
    original = C.method(:run)
    C.define_singleton_method(:run) { |*arguments, **_keywords| invocations << arguments; '' }
    gate = C::MicrophoneReceipt.new
    gate.verify!
    assert_equal [[File.join(C::ROOT, 'scripts/validate-microphone-regressions.sh'), '--verify-receipt', path, '--receipt-sha256', ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256']]], invocations
    gate.verify!
    assert_equal 2, invocations.length
    File.write(path, 'changed receipt')
    assert_raises(C::Refusal) { gate.verify! }
    assert_equal 2, invocations.length
  ensure
    C.define_singleton_method(:run, original) if original
    ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT'] = previous_path
    ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256'] = previous_sha
  end

  # These executable fixtures are never invoked. Only their bytes, location and
  # file identity are admitted, using the real receipt field names.
  def fake_tested_toolchain
    developer = File.join(@directory, 'Reviewed Xcode.app/Contents/Developer')
    paths = %w[Toolchains/XcodeDefault.xctoolchain/usr/bin/swift
               Toolchains/XcodeDefault.xctoolchain/usr/bin/clang usr/bin/xcodebuild]
    tools = paths.to_h do |relative|
      path = File.join(developer, relative)
      FileUtils.mkdir_p(File.dirname(path), mode: 0o755)
      File.write(path, 'offline fixture: ' + relative, perm: 0o755)
      [path, Digest::SHA256.file(path).hexdigest]
    end
    { 'invocation' => { 'developer_directory' => developer }, 'tools' => tools }
  end

  def test_tested_toolchain_uses_exact_receipt_fields_and_private_scrubbed_environment
    record = fake_tested_toolchain
    developer = record.fetch('invocation').fetch('developer_directory')
    toolchain = C::TestedToolchain.new(record, ambient: {})
    assert_equal File.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swift'), toolchain.swift
    assert_equal({ 'developer_directory' => developer, 'tools' => record.fetch('tools') }, toolchain.binding)
    assert toolchain.verify!(ambient: { 'DEVELOPER_DIR' => developer })
    environment = toolchain.build_environment(temporary_directory: @directory, ambient: {
      'DEVELOPER_DIR' => developer, 'PATH' => '/unreviewed/bin',
      'HOME' => '/unreviewed/home', 'BELUGA_UNSUPPORTED_FLAG' => 'do-not-inherit'
    })
    assert_equal %w[DEVELOPER_DIR HOME LC_ALL MACOSX_DEPLOYMENT_TARGET PATH SWIFT_TREAT_WARNINGS_AS_ERRORS TMPDIR], environment.keys.sort
    assert_equal developer, environment.fetch('DEVELOPER_DIR')
    assert_equal File.dirname(toolchain.swift) + ':/usr/bin:/bin:/usr/sbin:/sbin', environment.fetch('PATH')
    assert_equal Etc.getpwuid(Process.uid).dir, environment.fetch('HOME')
    assert_equal @directory, environment.fetch('TMPDIR')
    assert_equal '14.0', environment.fetch('MACOSX_DEPLOYMENT_TARGET')
    assert_equal 'YES', environment.fetch('SWIFT_TREAT_WARNINGS_AS_ERRORS')
    refute environment.key?('BELUGA_UNSUPPORTED_FLAG')
    File.chmod(0o755, @directory)
    assert_raises(C::Refusal) { toolchain.build_environment(temporary_directory: @directory, ambient: {}) }
  end

  def test_supported_build_overrides_refuse_before_compilation_without_echoing_values
    record = fake_tested_toolchain
    developer = record.fetch('invocation').fetch('developer_directory')
    names = C::TestedToolchain::OVERRIDE_NAMES + %w[OTHER_SWIFT_FLAGS OTHER_CFLAGS OTHER_LDFLAGS
      DYLD_INSERT_LIBRARIES DYLD_FRAMEWORK_PATH SWIFT_DRIVER_SWIFT_FRONTEND_EXEC
      SWIFTPM_CUSTOM_BIN_DIR SPM_BUILD_FLAGS CLANG_MODULE_CACHE_PATH LLVM_PROFILE_FILE
      GCC_PREPROCESSOR_DEFINITIONS XCODE_VERSION_ACTUAL __XCODE_BUILT_PRODUCTS_DIR_PATHS]
    names.each do |name|
      error = assert_raises(C::Refusal, name) do
        C::TestedToolchain.new(record, ambient: { name => 'never-echo-this-value' })
      end
      assert_includes error.message, name
      refute_includes error.message, 'never-echo-this-value'
    end
    ['', developer + '/', '/unreviewed/Xcode.app/Contents/Developer'].each do |selected|
      assert_raises(C::Refusal) { C::TestedToolchain.new(record, ambient: { 'DEVELOPER_DIR' => selected }) }
    end
    toolchain = C::TestedToolchain.new(record, ambient: {})
    assert_raises(C::Refusal) { toolchain.verify!(ambient: { 'TOOLCHAINS' => 'late-override' }) }
    assert_raises(C::Refusal) { toolchain.build_environment(temporary_directory: @directory, ambient: { 'SDKROOT' => 'late-override' }) }
  end

  def test_tested_toolchain_refuses_missing_wrong_or_malformed_receipt_identities
    record = fake_tested_toolchain
    swift = record.fetch('tools').keys.first
    [nil, [], {}, { 'invocation' => [] }, record.merge('tools' => [])].each do |bad|
      assert_raises(C::Refusal) { C::TestedToolchain.new(bad, ambient: {}) }
    end
    [nil, '', '0' * 64, record.fetch('tools').fetch(swift).upcase].each do |digest|
      bad = record.merge('tools' => record.fetch('tools').merge(swift => digest))
      assert_raises(C::Refusal) { C::TestedToolchain.new(bad, ambient: {}) }
    end
    assert_raises(C::Refusal) { C::TestedToolchain.new(record.merge('tools' => record.fetch('tools').reject { |path, _| path == swift }), ambient: {}) }
    File.unlink(swift)
    assert_raises(C::Refusal) { C::TestedToolchain.new(record, ambient: {}) }
  end

  def test_tested_toolchain_accepts_only_bound_internal_tool_alias_and_refuses_escape
    record = fake_tested_toolchain
    swift = record.fetch('tools').keys.first
    frontend = File.join(File.dirname(swift), 'swift-frontend')
    File.rename(swift, frontend)
    File.symlink('swift-frontend', swift)
    toolchain = C::TestedToolchain.new(record, ambient: {})
    assert toolchain.verify!(ambient: {})
    File.unlink(swift)
    File.symlink('./swift-frontend', swift)
    assert_raises(C::Refusal) { toolchain.verify!(ambient: {}) }
    outside = File.join(@directory, 'unreviewed-swift')
    File.write(outside, File.read(frontend), perm: 0o755)
    File.unlink(swift)
    File.symlink(outside, swift)
    assert_raises(C::Refusal) { C::TestedToolchain.new(record, ambient: {}) }
  end

  def test_tested_toolchain_revalidation_detects_replaced_inode_bytes_and_permissions
    record = fake_tested_toolchain
    swift = record.fetch('tools').keys.first
    toolchain = C::TestedToolchain.new(record, ambient: {})
    replacement = File.join(File.dirname(swift), 'replacement')
    File.write(replacement, File.read(swift), perm: 0o755)
    File.rename(replacement, swift)
    assert_raises(C::Refusal) { toolchain.verify!(ambient: {}) }
    rebound = C::TestedToolchain.new(record, ambient: {})
    File.write(swift, 'changed bytes')
    assert_raises(C::Refusal) { rebound.verify!(ambient: {}) }
    File.write(swift, 'offline fixture: Toolchains/XcodeDefault.xctoolchain/usr/bin/swift')
    File.chmod(0o775, swift)
    assert_raises(C::Refusal) { C::TestedToolchain.new(record, ambient: {}) }
    File.chmod(0o644, swift)
    assert_raises(C::Refusal) { C::TestedToolchain.new(record, ambient: {}) }
  end

  def test_release_executor_really_drops_unlisted_inherited_environment
    # A system env reader only, not a compiler or authentication tool. Exactly
    # one controlled fixture variable is exposed; no ambient value is printed.
    previous = ENV['BELUGA_POLICY_INHERITED_PROBE']
    ENV['BELUGA_POLICY_INHERITED_PROBE'] = 'must-not-reach-child'
    result = C.run('/usr/bin/env', timeout: 5, env: { 'BELUGA_POLICY_CHILD' => 'controlled-fixture' }, unsetenv_others: true)
    assert_equal "BELUGA_POLICY_CHILD=controlled-fixture\n", result
  ensure
    ENV['BELUGA_POLICY_INHERITED_PROBE'] = previous
  end

  def test_release_builder_binds_tools_before_identity_and_scrubs_every_swift_child
    builder = File.read(File.join(C::ROOT, 'macOS/scripts/build-beluga-mac-client.rb'))
    assert_operator builder.index('receipt.verify!'), :<, builder.index('tested_toolchain = receipt.tested_toolchain')
    assert_operator builder.index('tested_toolchain = receipt.tested_toolchain'), :<, builder.index("'/usr/bin/security'")
    refute_includes builder, "'/usr/bin/swift'"
    commands = builder.lines.select { |line| line.include?('C.run(tested_toolchain.swift,') }
    assert_equal 3, commands.length # version, three products in one loop, show-bin-path.
    assert_includes builder, '%w[CaptureServer OpensteamerMediaBridge BelugaUpdater].each'
    assert_includes builder, 'C.nested_signing_contract.each'
    assert_operator builder.index('C.nested_signing_contract.each'), :<, builder.index('sign.call(app, C::BUNDLE_ID, host: true)')
    commands.each do |line|
      assert_includes line, 'env: build_env'
      assert_includes line, 'unsetenv_others: true'
    end
    assert_includes builder, "'testedToolchain' => tested_toolchain.binding"
  end

  def test_tool_selection_requires_prior_receipt_verification_and_refuses_changed_receipt
    record = fake_tested_toolchain
    path = File.join(@directory, 'receipt.json')
    File.write(path, JSON.generate(record), perm: 0o600)
    previous_path = ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT']
    previous_sha = ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256']
    ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT'] = path
    ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256'] = Digest::SHA256.file(path).hexdigest
    original = C.method(:run)
    C.define_singleton_method(:run) { |*_arguments, **_keywords| '' }
    gate = C::MicrophoneReceipt.new
    assert_raises(C::Refusal) { gate.tested_toolchain(ambient: {}) }
    gate.verify! # Validator stub; this is a wrapper fixture, not production proof.
    assert_equal record.fetch('tools').keys.first, gate.tested_toolchain(ambient: {}).swift
    File.write(path, JSON.generate(record) + "\n")
    assert_raises(C::Refusal) { gate.tested_toolchain(ambient: {}) }
  ensure
    C.define_singleton_method(:run, original) if original
    ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT'] = previous_path
    ENV['BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256'] = previous_sha
  end
end
