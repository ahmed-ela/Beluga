# frozen_string_literal: true
# Filesystem/metadata fixtures only; source and receipt validation are explicit doubles.
require_relative 'build-beluga-mac-client'

module BelugaMacClientUpdateTrialTests
  C = BelugaMacClient
  TRIAL_PROFILE = BelugaMacClient::UpdateTrialProfile
  TRIAL_PROFILE_ID = 'a1111111-b222-4333-8444-555555555555'

  def setup_update_trial_profile
    developer = '/Applications/Xcode-Synthetic.app/Contents/Developer'
    @trial_profile_context = {
      production_config: {
        'schema' => 'beluga.mac-client-release.v1', 'version' => '0.2.0', 'build' => 100,
        'minimumSystemVersion' => '14.0', 'bundleIdentifier' => TRIAL_PROFILE::BUNDLE_ID,
        'teamIdentifier' => TRIAL_PROFILE::TEAM, 'sparkleVersion' => '2.10.0',
        'repository' => 'ahmed-ela/Beluga', 'feedURL' => TRIAL_PROFILE::STABLE_FEED,
        'publicEDKey' => Base64.strict_encode64("\x11" * 32)
      },
      trusted_source: { 'commit' => '1' * 40, 'tree' => '2' * 40 },
      source_release_sha256: '3' * 64, receipt_sha256: '4' * 64,
      tested_toolchain: {
        'developer_directory' => developer,
        'tools' => {
          developer + '/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift' => '5' * 64,
          developer + '/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang' => '6' * 64,
          developer + '/usr/bin/xcodebuild' => '7' * 64
        }
      },
      approved_namespace: "https://updates.example.test/trials/#{TRIAL_PROFILE_ID}/",
      approved_public_key: Base64.strict_encode64("\x22" * 32)
    }
    @trial_profile_manifest = {
      'schema' => 'beluga.update-trial-profile.v1', 'purpose' => 'native-update-validation',
      'productionPromotionAllowed' => false, 'trialID' => TRIAL_PROFILE_ID,
      'source' => trial_profile_clone_data(@trial_profile_context[:trusted_source]),
      'sourceReleaseSHA256' => @trial_profile_context[:source_release_sha256],
      'microphoneReceiptSHA256' => @trial_profile_context[:receipt_sha256],
      'testedToolchain' => trial_profile_clone_data(@trial_profile_context[:tested_toolchain]),
      'namespaceURL' => @trial_profile_context[:approved_namespace],
      'appcastURL' => @trial_profile_context[:approved_namespace] + 'appcast.xml',
      'payloadBaseURL' => @trial_profile_context[:approved_namespace] + 'payloads/',
      'publicEDKey' => @trial_profile_context[:approved_public_key],
      'slots' => { 'old' => { 'version' => '0.2.0', 'build' => 100 },
                   'new' => { 'version' => '0.2.1', 'build' => 101 } }
    }
    # Keep caller inputs mutable even under frozen_string_literal so copy tests
    # measure model ownership, not the fixture's literal-freezing policy.
    @trial_profile_context = trial_profile_clone_data(@trial_profile_context)
    @trial_profile_manifest = trial_profile_clone_data(@trial_profile_manifest)
  end

  def test_update_trial_profile_both_slots_derive_exact_release_fields_and_fixed_payload_names
    profile = trial_profile_parse
    %w[old new].each do |slot|
      config = profile.config(slot)
      assert_equal TRIAL_PROFILE::CONFIG_KEYS, config.keys.sort
      assert_equal profile.appcast_url, config['feedURL']
      assert_equal @trial_profile_context[:approved_public_key], config['publicEDKey']
      assert_equal TRIAL_PROFILE::BUNDLE_ID, config['bundleIdentifier']
      assert_equal TRIAL_PROFILE::TEAM, config['teamIdentifier']
      assert_equal '2.10.0', config['sparkleVersion']
      assert_equal "Beluga-Mac-#{config['version']}-#{config['build']}.dmg", profile.payload_name(slot)
      assert_equal profile.payload_base_url + profile.payload_name(slot), profile.payload_url(slot)
      assert_equal Digest::SHA256.hexdigest(TRIAL_PROFILE.canonical_json(config)), profile.config_sha256(slot)
    end
    refute profile.production_promotion_allowed?
    refute profile.published?
    assert_equal 'beluga.update-candidate.v2', TRIAL_PROFILE::CONTRACT['candidateIdentitySchema']
    assert_equal 1, TRIAL_PROFILE::CONTRACT['updaterOwnershipProtocolVersion']
    assert_equal 1, TRIAL_PROFILE::CONTRACT['pairedPhoneCatalogVersion']
    assert_equal 'arm64', TRIAL_PROFILE::CONTRACT['architecture']
  end

  def test_update_trial_profile_build_source_seals_same_source_receipt_and_exact_slot_config
    profile = trial_profile_parse
    %w[old new].each do |slot|
      source = profile.build_source(slot)
      assert_equal @trial_profile_context[:trusted_source]['commit'], source['commit']
      assert_equal @trial_profile_context[:trusted_source]['tree'], source['tree']
      binding = source['validationBinding']
      assert_equal %w[manifestSHA256 microphoneReceiptSHA256 schema slot slotConfigSHA256 sourceReleaseSHA256 trialID], binding.keys.sort
      assert_equal 'beluga.update-trial-binding.v1', binding['schema']
      assert_equal profile.manifest_sha256, binding['manifestSHA256']
      assert_equal profile.config_sha256(slot), binding['slotConfigSHA256']
      assert_equal slot, binding['slot']
      assert_equal @trial_profile_context[:receipt_sha256], binding['microphoneReceiptSHA256']
      assert_equal @trial_profile_context[:source_release_sha256], binding['sourceReleaseSHA256']
    end
    refute_equal profile.build_source('old'), profile.build_source('new')
  end

  def test_update_trial_profile_all_retained_data_are_defensively_copied_and_deeply_frozen
    profile = trial_profile_parse
    @trial_profile_context[:production_config]['version'].replace('9.9.9')
    @trial_profile_context[:trusted_source]['commit'].replace('8' * 40)
    @trial_profile_context[:tested_toolchain]['tools'].values.first.replace('9' * 64)
    @trial_profile_context[:approved_namespace].replace('https://evil.example.test/')
    @trial_profile_context[:approved_public_key].replace(Base64.strict_encode64("\x33" * 32))
    assert_equal '0.2.0', profile.config('old')['version']
    assert_equal '1' * 40, profile.source['commit']
    assert_equal '5' * 64, profile.tested_toolchain['tools'].values.first
    assert_equal "https://updates.example.test/trials/#{TRIAL_PROFILE_ID}/", profile.namespace_url
    assert_equal Base64.strict_encode64("\x22" * 32), profile.public_ed_key
    [profile.config('new'), profile.build_source('old'), profile.source, profile.tested_toolchain, TRIAL_PROFILE::CONTRACT].each do |value|
      trial_profile_assert_deeply_frozen(value)
    end
    assert_raises(FrozenError) { profile.config('new')['version'].replace('1.0.0') }
    assert_raises(FrozenError) { profile.build_source('new')['validationBinding']['slot'].replace('old') }
    assert_raises(FrozenError) { profile.tested_toolchain['tools'].clear }
  end

  def test_update_trial_profile_exact_raw_manifest_digest_is_required_even_for_valid_whitespace
    bytes = JSON.generate(@trial_profile_manifest)
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse_bytes(bytes, expected: 'f' * 64) }
    pretty = JSON.pretty_generate(@trial_profile_manifest)
    assert_equal Digest::SHA256.hexdigest(pretty), trial_profile_parse_bytes(pretty).manifest_sha256
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse_bytes(pretty, expected: Digest::SHA256.hexdigest(bytes)) }
  end

  def test_update_trial_profile_duplicate_fields_are_rejected_at_every_relevant_level
    bytes = JSON.generate(@trial_profile_manifest)
    trial_profile_assert_refused_bytes(bytes.sub('"schema":', '"schema":"beluga.update-trial-profile.v1","schema":'))
    trial_profile_assert_refused_bytes(bytes.sub('"schema":', '"\\u0073chema":"beluga.update-trial-profile.v1","schema":'))
    trial_profile_assert_refused_bytes(bytes.sub('"commit":', '"commit":"' + '1' * 40 + '","commit":'))
    trial_profile_assert_refused_bytes(bytes.sub('"developer_directory":', '"developer_directory":"x","developer_directory":'))
    trial_profile_assert_refused_bytes(bytes.sub('"build":100', '"build":100,"build":100'))
    trial_profile_assert_refused_bytes(bytes.sub('"old":', '"old":{"version":"0.2.0","build":100},"old":'))
  end

  def test_update_trial_profile_malformed_oversized_trailing_and_non_utf8_json_are_refused
    ['', '{}', '[]', 'null', 'true', JSON.generate(@trial_profile_manifest) + '{}',
     '{"schema":NaN}', '[' * 10 + '0' + ']' * 10,
     JSON.generate(@trial_profile_manifest) + "\xff".b, ' ' * (TRIAL_PROFILE::MAXIMUM_MANIFEST_BYTES + 1)].each do |bytes|
      trial_profile_assert_refused_bytes(bytes)
    end
  end

  def test_update_trial_profile_unknown_missing_and_wrong_json_types_are_refused
    %w[schema purpose source testedToolchain slots namespaceURL publicEDKey trialID].each do |key|
      trial_profile_assert_mutation_refused { |m| m.delete(key) }
      trial_profile_assert_mutation_refused { |m| m[key] = nil }
    end
    trial_profile_assert_mutation_refused { |m| m['privateSigningSeed'] = 'not permitted' }
    trial_profile_assert_mutation_refused { |m| m['source']['unknown'] = 'x' }
    trial_profile_assert_mutation_refused { |m| m['slots']['new']['payloadURL'] = 'https://evil.example.test/x' }
    [true, 0, 'false', nil].each { |item| trial_profile_assert_mutation_refused { |m| m['productionPromotionAllowed'] = item } }
  end

  def test_update_trial_profile_native_build_types_bounds_and_strict_increase
    [99, 2**63, 100.0, 100.5, '100', true, false, nil].each do |item|
      trial_profile_assert_mutation_refused { |m| m['slots']['old']['build'] = item }
    end
    [99, 100, 2**63, 101.0, '101'].each { |item| trial_profile_assert_mutation_refused { |m| m['slots']['new']['build'] = item } }
    trial_profile_assert_refused_bytes(JSON.generate(@trial_profile_manifest).sub('"build":100', '"build":1e2'))
    trial_profile_assert_refused_bytes(JSON.generate(@trial_profile_manifest).sub('"build":100', '"build":100.0'))
    @trial_profile_manifest['slots']['old']['build'] = 2**63 - 2
    @trial_profile_manifest['slots']['new']['build'] = 2**63 - 1
    assert_equal 2**63 - 1, trial_profile_parse.config('new')['build']
  end

  def test_update_trial_profile_canonical_versions_and_no_version_rollback
    ['01.2.0', '1.2', '1.2.3-beta', '1.2.3+build', ' 1.2.3', '1.2.3\n',
     '4294967296.0.0', '9' * 65, 2, nil].each do |item|
      trial_profile_assert_mutation_refused { |m| m['slots']['new']['version'] = item }
    end
    trial_profile_assert_mutation_refused { |m| m['slots']['new']['version'] = '0.1.99' }
    @trial_profile_manifest['slots']['new']['version'] = '0.2.0'
    assert_equal '0.2.0', trial_profile_parse.config('new')['version']
    @trial_profile_manifest['slots']['new']['version'] = '4294967295.4294967295.4294967295'
    assert_equal @trial_profile_manifest['slots']['new']['version'], trial_profile_parse.config('new')['version']
  end

  def test_update_trial_profile_exact_source_config_receipt_and_toolchain_context_are_required
    trial_profile_assert_mutation_refused { |m| m['source']['commit'] = '9' * 40 }
    trial_profile_assert_mutation_refused { |m| m['source']['tree'] = '9' * 40 }
    trial_profile_assert_mutation_refused { |m| m['sourceReleaseSHA256'] = '9' * 64 }
    trial_profile_assert_mutation_refused { |m| m['microphoneReceiptSHA256'] = '9' * 64 }
    trial_profile_assert_mutation_refused { |m| m['testedToolchain']['tools'].values.first.replace('9' * 64) }
    trial_profile_assert_mutation_refused { |m| m['testedToolchain']['tools']['/synthetic/other-tool'] = '9' * 64 }
    trial_profile_assert_mutation_refused { |m| m['testedToolchain']['developer_directory'] += '/Other' }
    trial_profile_assert_mutation_refused { |m| m['source']['commit'] = '0' * 40 }
    trial_profile_assert_mutation_refused { |m| m['sourceReleaseSHA256'] = 'A' * 64 }
  end

  def test_update_trial_profile_fixed_production_context_cannot_be_redefined_or_left_unconfigured
    %w[bundleIdentifier teamIdentifier minimumSystemVersion sparkleVersion repository feedURL schema].each do |key|
      context = trial_profile_clone_data(@trial_profile_context)
      context[:production_config][key] = 'unreviewed'
      assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(context: context) }
    end
    context = trial_profile_clone_data(@trial_profile_context)
    context[:production_config]['publicEDKey'] = nil
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(context: context) }
    context = trial_profile_clone_data(@trial_profile_context)
    context[:production_config]['build'] = 100.0
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(context: context) }
  end

  def test_update_trial_profile_exact_approved_namespace_and_derived_feed_payload_are_required
    trial_profile_assert_mutation_refused { |m| m['namespaceURL'] = m['namespaceURL'].sub('updates.', 'other.') }
    trial_profile_assert_mutation_refused { |m| m['appcastURL'] += '?x=1' }
    trial_profile_assert_mutation_refused { |m| m['payloadBaseURL'] = m['namespaceURL'] + 'elsewhere/' }
    trial_profile_assert_mutation_refused { |m| m['trialID'] = '11111111-2222-4333-8444-666666666666' }
    trial_profile_assert_mutation_refused { |m| m['trialID'] = '00000000-0000-0000-0000-000000000000' }
    trial_profile_assert_mutation_refused { |m| m['trialID'] = TRIAL_PROFILE_ID.upcase }
  end

  def test_update_trial_profile_url_grammar_rejects_aliases_injections_and_unbounded_paths_even_if_approved
    base = "updates.example.test/trials/#{TRIAL_PROFILE_ID}/"
    urls = [
      'http://' + base, 'HTTPS://' + base, 'https://user@' + base,
      'https://updates.example.test:444/trials/' + TRIAL_PROFILE_ID + '/',
      'https://UPDATES.example.test/trials/' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test./trials/' + TRIAL_PROFILE_ID + '/',
      'https://updates..example.test/trials/' + TRIAL_PROFILE_ID + '/',
      'https://-updates.example.test/trials/' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/../' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/./' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials//' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/%2f/' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/%2e%2e/' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/\\/' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/' + TRIAL_PROFILE_ID + '/?x=1',
      'https://updates.example.test/trials/' + TRIAL_PROFILE_ID + '/#fragment',
      'https://updates.example.test/trials/"/' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/<xml>/' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/' + TRIAL_PROFILE_ID + "/\n",
      'https://updates.example.test/trials/é/' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/' + 'a' * 1050 + '/' + TRIAL_PROFILE_ID + '/',
      'https://updates.example.test/trials/not-' + TRIAL_PROFILE_ID + '/'
    ]
    urls.each do |url|
      manifest, context = trial_profile_namespace_fixture(url)
      assert_raises(BelugaMacClient::Refusal, url) { trial_profile_parse(manifest: manifest, context: context) }
    end
    manifest, context = trial_profile_namespace_fixture("https://updates.example.test:443/trials/#{TRIAL_PROFILE_ID}/")
    assert_equal context[:approved_namespace], trial_profile_parse(manifest: manifest, context: context).namespace_url
  end

  def test_update_trial_profile_production_destination_family_overlap_is_refused_including_port_alias
    ['', ':443'].each do |port|
      url = "https://github.com#{port}/ahmed-ela/Beluga/releases/download/#{TRIAL_PROFILE_ID}/"
      manifest, context = trial_profile_namespace_fixture(url)
      assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(manifest: manifest, context: context) }
    end
    manifest, context = trial_profile_namespace_fixture("https://github.com/synthetic-owner/test-updates/#{TRIAL_PROFILE_ID}/")
    assert_equal context[:approved_namespace], trial_profile_parse(manifest: manifest, context: context).namespace_url
  end

  def test_update_trial_profile_native_reserved_hosts_are_refused_even_if_explicitly_approved
    ['updates.invalid', 'updates.example', 'localhost'].each do |host|
      manifest, context = trial_profile_namespace_fixture("https://#{host}/trials/#{TRIAL_PROFILE_ID}/")
      assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(manifest: manifest, context: context) }
    end
  end

  def test_update_trial_profile_full_derived_payload_limit_not_only_feed_or_base_limit
    basename_bytes = 'Beluga-Mac-0.2.1-101.dmg'.bytesize
    namespace_path_bytes = 1024 - 'payloads/'.bytesize - basename_bytes
    prefix_bytes = TRIAL_PROFILE_ID.bytesize + 3
    path = "/#{TRIAL_PROFILE_ID}/#{'x' * (namespace_path_bytes - prefix_bytes)}/"
    manifest, context = trial_profile_namespace_fixture('https://updates.example.test' + path)
    profile = trial_profile_parse(manifest: manifest, context: context)
    assert_equal 1024, TRIAL_PROFILE.url!(profile.payload_url('new'), directory: false).fetch(:path).bytesize
    manifest, context = trial_profile_namespace_fixture('https://updates.example.test' + path.sub('/x', '/xx'))
    assert TRIAL_PROFILE.url!(manifest['appcastURL'], directory: false)
    assert TRIAL_PROFILE.url!(manifest['payloadBaseURL'], directory: true)
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(manifest: manifest, context: context) }
  end

  def test_update_trial_profile_public_key_is_exact_canonical_nonzero_and_independent
    [nil, '', Base64.strict_encode64("\0" * 32), Base64.strict_encode64("\x22" * 31),
     Base64.strict_encode64("\x22" * 32).delete_suffix('='),
     Base64.strict_encode64("\x22" * 32) + "\n"].each do |key|
      manifest = trial_profile_clone_data(@trial_profile_manifest)
      context = trial_profile_clone_data(@trial_profile_context)
      manifest['publicEDKey'] = context[:approved_public_key] = key
      assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(manifest: manifest, context: context) }
    end
    manifest = trial_profile_clone_data(@trial_profile_manifest)
    context = trial_profile_clone_data(@trial_profile_context)
    manifest['publicEDKey'] = context[:approved_public_key] = context[:production_config]['publicEDKey']
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(manifest: manifest, context: context) }
    trial_profile_assert_mutation_refused { |m| m['publicEDKey'] = Base64.strict_encode64("\x33" * 32) }
  end

  def test_update_trial_profile_unknown_slot_and_direct_constructor_refuse_authority
    profile = trial_profile_parse
    [:old, nil, 'OLD', 'other'].each do |slot|
      %i[config config_sha256 build_source payload_name payload_url].each do |method|
        assert_raises(BelugaMacClient::Refusal) { profile.public_send(method, slot) }
      end
    end
    assert_raises(NoMethodError) { TRIAL_PROFILE.new({}) }
    refute_includes profile.inspect, @trial_profile_context[:approved_namespace]
  end

  def test_update_trial_profile_malformed_or_unbounded_supplied_context_refuses_without_traversal_effects
    context = trial_profile_clone_data(@trial_profile_context)
    context[:trusted_source]['commit'] = "\xff".b
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(context: context) }
    context = trial_profile_clone_data(@trial_profile_context)
    context[:tested_toolchain]['developer_directory'] = '/' + 'x' * 5000
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(context: context) }
    context = trial_profile_clone_data(@trial_profile_context)
    context[:production_config]['cycle'] = context[:production_config]
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(context: context) }
    context = trial_profile_clone_data(@trial_profile_context)
    40.times { |index| context[:production_config]["unknown#{index}"] = 'x' }
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(context: context) }
  end

  def test_trial_admission_requires_receipt_validation_before_manifest_access
    assert_raises(C::Refusal) do
      C::AdmittedUpdateTrial.open('/nonexistent-trial', 'a' * 64, slot: 'old',
        approved_namespace: 'unused', approved_public_key: 'unused', receipt: Object.new)
    end
    receipt = C::MicrophoneReceipt.allocate
    receipt.define_singleton_method(:verify!) { raise C::Refusal, 'fixture receipt denied' }
    error = assert_raises(C::Refusal) do
      C::AdmittedUpdateTrial.open('/nonexistent-trial', 'a' * 64, slot: 'old',
        approved_namespace: 'unused', approved_public_key: 'unused', receipt: receipt)
    end
    assert_equal 'fixture receipt denied', error.message
    assert_raises(NoMethodError) { C::AdmittedUpdateTrial.new }
  end

  def test_trial_admission_pins_manifest_source_receipt_and_toolchain
    %i[manifest_inode manifest_bytes manifest_mode source receipt tool production].each do |boundary|
      with_admitted_trial_fixture do |fixture|
        binding = admit_trial_fixture(fixture, 'old')
        assert binding.verify!
        case boundary
        when :manifest_inode
          replacement = fixture[:path] + '.replacement'
          File.write(replacement, File.binread(fixture[:path]), perm: 0o600)
          File.rename(replacement, fixture[:path])
        when :manifest_bytes then File.write(fixture[:path], File.binread(fixture[:path]) + "\n")
        when :manifest_mode then File.chmod(0o644, fixture[:path])
        when :source then fixture[:source]['commit'] = '9' * 40
        when :receipt then File.write(fixture[:receipt_path], 'changed receipt')
        when :tool then File.write(fixture[:toolchain].swift, 'changed compiler')
        when :production
          C.stub(:config!, fixture[:production].merge('build' => 999)) do
            assert_raises(C::Refusal, boundary.to_s) { binding.verify! }
          end
          next
        end
        assert_raises(C::Refusal, boundary.to_s) { binding.verify! }
      end
    end
  end

  def test_trial_metadata_stages_and_verifies_both_slots_without_changing_production
    before = C.snapshot(C::CONFIG_PATH)
    with_admitted_trial_fixture do |fixture|
      %w[old new].each do |slot|
        binding = admit_trial_fixture(fixture, slot)
        app = trial_app_tree(fixture[:directory], slot)
        assert_equal binding.config, C.stage_release_metadata!(app, source: fixture[:source], trial_binding: binding)
        assert_equal [binding.config, binding.build_source], C.verify_release_metadata!(app, trial_binding: binding)
        ['', C::BROKER].each do |relative|
          resources = File.join(app, relative, 'Contents/Resources')
          assert_equal binding.config, JSON.parse(File.binread(File.join(resources, 'Release.json')))
          source = JSON.parse(File.binread(File.join(resources, 'BuildSource.json')))
          assert_equal slot, source.dig('validationBinding', 'slot')
          assert_equal fixture[:source]['commit'], source['commit']
        end
        assert_equal false, binding.report_fields['productionPromotionAllowed']
        assert_equal false, binding.report_fields['published']
        assert_raises(C::Refusal) { C.verify_release_metadata!(app) }
        assert_raises(C::Refusal) { C.verify_app!(app, binding.config) }
        assert_raises(C::Refusal) { C.package_evidence_mode!(app, nil, nil) }
      end
      app = trial_app_tree(fixture[:directory], 'production')
      assert_equal fixture[:production], C.stage_release_metadata!(app, source: fixture[:source])
      assert_equal [fixture[:production], fixture[:source]], C.verify_release_metadata!(app)
      assert_equal File.binread(C::CONFIG_PATH), File.binread(File.join(app, 'Contents/Resources/Release.json'))
      assert_equal fixture[:source], JSON.parse(File.binread(File.join(app, 'Contents/Resources/BuildSource.json')))
    end
    assert_equal before, C.snapshot(C::CONFIG_PATH)
  end

  def test_trial_metadata_rejects_mixed_slot_config_provenance_and_plists
    with_admitted_trial_fixture do |fixture|
      old = admit_trial_fixture(fixture, 'old')
      successor = admit_trial_fixture(fixture, 'new')
      %i[host_config broker_config host_source broker_source both_source host_plist broker_plist host_catalog broker_catalog duplicate_config duplicate_source].each do |boundary|
        app = trial_app_tree(fixture[:directory], boundary.to_s)
        C.stage_release_metadata!(app, source: fixture[:source], trial_binding: old)
        host_resources = File.join(app, 'Contents/Resources')
        broker_resources = File.join(app, C::BROKER, 'Contents/Resources')
        case boundary
        when :host_config then File.write(File.join(host_resources, 'Release.json'), JSON.generate(successor.config))
        when :broker_config then File.write(File.join(broker_resources, 'Release.json'), JSON.generate(successor.config))
        when :host_source then File.write(File.join(host_resources, 'BuildSource.json'), JSON.generate(successor.build_source))
        when :broker_source then File.write(File.join(broker_resources, 'BuildSource.json'), JSON.generate(successor.build_source))
        when :both_source
          [host_resources, broker_resources].each do |resources|
            File.write(File.join(resources, 'BuildSource.json'), JSON.generate(successor.build_source))
          end
        when :host_plist then C.plist_set(File.join(app, 'Contents/Info.plist'), 'SUFeedURL', fixture[:production]['feedURL'])
        when :broker_plist then C.plist_set(File.join(app, C::BROKER, 'Contents/Info.plist'), 'CFBundleVersion', '101')
        when :host_catalog then C.plist_set(File.join(app, 'Contents/Info.plist'), 'BelugaPairedPhoneCatalogVersion', 0)
        when :broker_catalog then C.plist_set(File.join(app, C::BROKER, 'Contents/Info.plist'), 'BelugaPairedPhoneCatalogVersion', 0)
        when :duplicate_config
          bytes = JSON.generate(old.config).sub('{', '{"build":101,')
          File.write(File.join(host_resources, 'Release.json'), bytes)
        when :duplicate_source
          bytes = JSON.generate(old.build_source).sub('{', '{"commit":"wrong",')
          File.write(File.join(host_resources, 'BuildSource.json'), bytes)
        end
        assert_raises(C::Refusal, boundary.to_s) { C.verify_release_metadata!(app, trial_binding: old) }
      end
      app = trial_app_tree(fixture[:directory], 'wrong-binding')
      C.stage_release_metadata!(app, source: fixture[:source], trial_binding: old)
      assert_raises(C::Refusal) { C.verify_release_metadata!(app, trial_binding: successor) }
    end
  end

  def test_trial_metadata_requires_integer_build_in_both_signed_configs
    with_admitted_trial_fixture do |fixture|
      binding = admit_trial_fixture(fixture, 'old')
      ['', C::BROKER].each_with_index do |relative, index|
        app = trial_app_tree(fixture[:directory], "float-build-#{index}")
        C.stage_release_metadata!(app, source: fixture[:source], trial_binding: binding)
        path = File.join(app, relative, 'Contents/Resources/Release.json')
        value = JSON.parse(File.binread(path))
        value['build'] = value.fetch('build').to_f
        File.write(path, JSON.generate(value))
        assert_raises(C::Refusal, relative.empty? ? 'host build must be Integer' : 'broker build must be Integer') do
          C.verify_release_metadata!(app, trial_binding: binding)
        end
      end
    end
  end

  def test_trial_native_verifier_rejects_loose_bindings_before_native_work
    [nil, false, {}, trial_profile_parse, Object.new].each do |binding|
      assert_raises(C::Refusal) { C.verify_trial_app!('/nonexistent-app', binding) }
      next if binding.nil?
      assert_raises(C::Refusal) do
        C::Builder.build({ output: '/nonexistent', scratch: '/nonexistent', identity: 'A' * 40 }, trial_binding: binding)
      end
      assert_raises(C::Refusal) { C.stage_release_metadata!('/nonexistent', source: {}, trial_binding: binding) }
      assert_raises(C::Refusal) { C.verify_release_metadata!('/nonexistent', trial_binding: binding) }
    end
    with_admitted_trial_fixture do |fixture|
      binding = admit_trial_fixture(fixture, 'old')
      assert_raises(C::Refusal) do
        C.verify_release_metadata!('/nonexistent-app', product_binding: {}, trial_binding: binding)
      end
      File.write(fixture[:path], File.binread(fixture[:path]) + "\n")
      assert_raises(C::Refusal) { C.verify_trial_app!('/nonexistent-app', binding) }
    end
  end

  def test_trial_metadata_requires_native_integer_catalog_and_ownership_markers
    with_admitted_trial_fixture do |fixture|
      binding = admit_trial_fixture(fixture, 'old')
      %w[BelugaPairedPhoneCatalogVersion BelugaUpdateOwnershipProtocol].each do |key|
        app = trial_app_tree(fixture[:directory], key)
        C.stage_release_metadata!(app, source: fixture[:source], trial_binding: binding)
        path = File.join(app, 'Contents/Info.plist')
        C.run('/usr/bin/plutil', '-replace', key, '-float', '1.0', path)
        assert_raises(C::Refusal, "#{key} must be a native plist integer") do
          C.verify_release_metadata!(app, trial_binding: binding)
        end
      end
    end
  end

  private

  def with_admitted_trial_fixture
    directory = File.realpath(Dir.mktmpdir('trial-artifact.', @directory))
    record = fake_tested_toolchain
    toolchain = C::TestedToolchain.new(record, ambient: {})
    verify_tools = toolchain.method(:verify!)
    toolchain.define_singleton_method(:verify!) { |**_options| verify_tools.call(ambient: {}) }
    receipt_path = File.join(directory, 'receipt.json')
    File.write(receipt_path, 'explicit offline receipt-validation double', perm: 0o600)
    receipt_snapshot = C.snapshot(receipt_path)
    receipt_binding = { 'path' => receipt_path, 'sha256' => receipt_snapshot.last }
    receipt = C::MicrophoneReceipt.allocate
    receipt.define_singleton_method(:verify!) do
      C.require!(C.snapshot(receipt_path) == receipt_snapshot, 'fixture receipt changed')
      true
    end
    receipt.define_singleton_method(:evidence_binding) { receipt_binding }
    receipt.define_singleton_method(:tested_toolchain) { toolchain }
    source = { 'commit' => '1' * 40, 'tree' => '2' * 40 }
    production = C.config!
    manifest = trial_profile_clone_data(@trial_profile_manifest)
    manifest['source'] = source.dup
    manifest['sourceReleaseSHA256'] = Digest::SHA256.file(C::CONFIG_PATH).hexdigest
    manifest['microphoneReceiptSHA256'] = receipt_binding['sha256']
    manifest['testedToolchain'] = toolchain.binding
    path = File.join(directory, 'trial.json')
    File.write(path, JSON.generate(manifest), perm: 0o600)
    fixture = { directory: directory, path: path, digest: Digest::SHA256.file(path).hexdigest,
      source: source, production: production, manifest: manifest, receipt: receipt,
      receipt_path: receipt_path, toolchain: toolchain }
    C.stub(:source!, lambda { source }) { yield fixture }
  end

  def admit_trial_fixture(fixture, slot)
    C::AdmittedUpdateTrial.open(fixture[:path], fixture[:digest], slot: slot,
      approved_namespace: fixture[:manifest]['namespaceURL'],
      approved_public_key: fixture[:manifest]['publicEDKey'], receipt: fixture[:receipt])
  end

  def trial_app_tree(directory, label)
    app = File.join(directory, label, 'Beluga Host.app')
    ['', C::BROKER].each { |relative| FileUtils.mkdir_p(File.join(app, relative, 'Contents/Resources')) }
    app
  end

  def trial_profile_parse(manifest: @trial_profile_manifest, context: @trial_profile_context)
    trial_profile_parse_bytes(JSON.generate(manifest), context: context)
  end

  def trial_profile_parse_bytes(bytes, context: @trial_profile_context, expected: Digest::SHA256.hexdigest(bytes))
    TRIAL_PROFILE.parse(bytes, expected_manifest_sha256: expected, **context)
  end

  def trial_profile_assert_refused_bytes(bytes)
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse_bytes(bytes) }
  end

  def trial_profile_assert_mutation_refused
    manifest = trial_profile_clone_data(@trial_profile_manifest)
    yield manifest
    assert_raises(BelugaMacClient::Refusal) { trial_profile_parse(manifest: manifest) }
  end

  def trial_profile_namespace_fixture(url)
    manifest = trial_profile_clone_data(@trial_profile_manifest)
    context = trial_profile_clone_data(@trial_profile_context)
    context[:approved_namespace] = manifest['namespaceURL'] = url
    manifest['appcastURL'] = url + 'appcast.xml'
    manifest['payloadBaseURL'] = url + 'payloads/'
    [manifest, context]
  end

  def trial_profile_clone_data(value)
    Marshal.load(Marshal.dump(value))
  end

  def trial_profile_assert_deeply_frozen(value)
    assert value.frozen?
    return unless value.is_a?(Hash)
    value.each do |key, item|
      assert key.frozen?
      trial_profile_assert_deeply_frozen(item)
    end
  end
end
