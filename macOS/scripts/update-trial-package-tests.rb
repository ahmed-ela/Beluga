# frozen_string_literal: true
# Real private files/metadata with explicit native-command doubles. No native release proof.
require_relative 'package-beluga-mac-client'

module BelugaMacClientUpdateTrialPackageTests
  C = BelugaMacClient
  TRIAL_SIGNING_IDENTITY = 'A' * 40
  TRIAL_NOTARY_ID = '11111111-2222-4333-8444-555555555555'

  def test_trial_build_report_admission_binds_both_actual_slot_artifacts
    %w[old new].each do |slot|
      with_trial_package_fixture(slot) do |fixture|
        with_trial_package_commands(fixture) do
          admitted = C::AdmittedTrialBuild.open(fixture[:app], trial_binding: fixture[:binding], identity: TRIAL_SIGNING_IDENTITY)
          assert admitted.verify!
          assert_equal fixture[:verification], admitted.verification
          assert_equal Digest::SHA256.file(fixture[:report_path]).hexdigest, admitted.provenance['sha256']
          assert_equal 'successful-trial-build', admitted.provenance['kind']
          assert admitted.verification.frozen?
          assert_equal [fixture[:app_signature_command]], fixture[:commands]
        end
      end
    end
  end

  def test_trial_build_report_rejects_mixed_authority_candidates_and_json_types
    with_trial_package_fixture do |fixture|
      original = File.binread(fixture[:report_path])
      mutations = {
        schema: ->(v) { v['schema'] = 'beluga.mac-client-build.v1' },
        status: ->(v) { v['status'] = 'SIGNED_VERIFIED_NOT_NOTARIZED' },
        slot: ->(v) { v['validationBinding']['slot'] = 'new' },
        manifest: ->(v) { v['validationBinding']['manifestSHA256'] = '0' * 64 },
        config: ->(v) { v['validationBinding']['slotConfigSHA256'] = '0' * 64 },
        receipt: ->(v) { v['validationBinding']['microphoneReceiptSHA256'] = '0' * 64 },
        source: ->(v) { v['commit'] = '0' * 40 },
        tree: ->(v) { v['tree'] = '0' * 40 },
        tools: ->(v) { v['testedToolchain']['tools'].transform_values! { '0' * 64 } },
        app: ->(v) { v['app'] = '/unrelated/Beluga Host.app' },
        identity: ->(v) { v['identitySHA1'] = 'B' * 40 },
        app_hash: ->(v) { v['appSHA256'] = '0' * 64 },
        executable: ->(v) { v['candidateIdentity']['executableSHA256'] = '0' * 64 },
        candidate_tree: ->(v) { v['candidateIdentity']['bundleTreeSHA256'] = '0' * 64 },
        float_build: ->(v) { v['build'] = v['build'].to_f },
        float_candidate_build: ->(v) { v['candidateIdentity']['build'] = v['build'].to_f },
        publication: ->(v) { v['published'] = true },
        promotion: ->(v) { v['productionPromotionAllowed'] = true },
        unknown: ->(v) { v['releaseTag'] = 'production' },
        logs: ->(v) { v['buildLogs']['CaptureServer']['sha256'] = '0' * 64 }
      }
      with_trial_package_commands(fixture) do
        mutations.each do |name, mutate|
          report = JSON.parse(original)
          mutate.call(report)
          File.write(fixture[:report_path], JSON.generate(report))
          assert_raises(C::Refusal, name.to_s) do
            C::AdmittedTrialBuild.open(fixture[:app], trial_binding: fixture[:binding], identity: TRIAL_SIGNING_IDENTITY)
          end
        end
        File.write(fixture[:report_path], original.sub('{', '{"schema":"duplicate",'))
        assert_raises(C::Refusal) do
          C::AdmittedTrialBuild.open(fixture[:app], trial_binding: fixture[:binding], identity: TRIAL_SIGNING_IDENTITY)
        end
      end
    end
  end

  def test_trial_build_admission_rechecks_report_logs_app_and_production_evidence
    %i[inode report mode log app production].each do |mutation|
      with_trial_package_fixture do |fixture|
        with_trial_package_commands(fixture) do
          admitted = C::AdmittedTrialBuild.open(fixture[:app], trial_binding: fixture[:binding], identity: TRIAL_SIGNING_IDENTITY)
          case mutation
          when :inode
            replacement = fixture[:report_path] + '.replacement'
            File.write(replacement, File.binread(fixture[:report_path]), perm: 0o600)
            File.rename(replacement, fixture[:report_path])
          when :report then File.write(fixture[:report_path], File.binread(fixture[:report_path]) + "\n")
          when :mode then File.chmod(0o644, fixture[:report_path])
          when :log then File.write(File.join(File.dirname(fixture[:app]), 'CaptureServer-build.log'), 'changed')
          when :app then File.write(File.join(fixture[:app], 'Contents/MacOS/CaptureServer'), 'changed')
          when :production then File.write(File.join(File.dirname(fixture[:app]), 'build.json'), '{}', perm: 0o600)
          end
          assert_raises(C::Refusal, mutation.to_s) { admitted.verify! }
        end
      end
    end
  end

  def test_trial_package_refuses_loose_authority_production_accounts_and_recovery_before_commands
    with_trial_package_fixture do |fixture|
      options, binding = fixture.values_at(:options, :binding)
      with_trial_package_commands(fixture) do
        [false, {}, trial_profile_parse, Object.new].each do |loose|
          assert_raises(C::Refusal) { C::Packager.package(options, trial_binding: loose) }
        end
        %w[default beluga-mac beluga-update-trial-other].each do |account|
          assert_raises(C::Refusal) { C::Packager.package(options.merge(account: account), trial_binding: binding) }
        end
        %i[retained retained_sha resume_dmg resume_sha resume_id unknown].each do |key|
          assert_raises(C::Refusal) { C::Packager.package(options.merge(key => nil), trial_binding: binding) }
        end
        # Default production packaging cannot treat trial-build.json as build authority.
        C::MicrophoneReceipt.stub(:new, fixture[:receipt]) do
          assert_raises(C::Refusal) { C::Packager.package(options) }
        end
        assert_empty fixture[:commands]
      end
      assert_equal "beluga-update-trial-#{binding.trial_id}", binding.signing_account
    end
  end

  def test_trial_appcast_parses_exact_admitted_urls_and_rejects_bad_payload_identity
    with_trial_package_fixture do |fixture|
      binding = fixture[:binding]
      signature = Base64.strict_encode64('s' * 64)
      candidate = fixture[:verification]['candidateIdentity']
      xml = C.trial_appcast(binding, 12345, signature, Time.utc(2026, 10, 2), candidate_identity: candidate)
      document = REXML::Document.new(xml)
      assert_equal 1, document.get_elements('rss/channel/item/enclosure').length
      enclosure = document.elements['rss/channel/item/enclosure']
      assert_equal binding.payload_url, enclosure.attributes['url']
      assert_equal binding.namespace_url, document.elements['rss/channel/link'].text
      assert_equal binding.config['build'].to_s, document.elements['rss/channel/item/sparkle:version'].text
      assert_equal binding.config['version'], document.elements['rss/channel/item/sparkle:shortVersionString'].text
      assert_equal '12345', enclosure.attributes['length']
      assert_equal signature, enclosure.attributes['sparkle:edSignature']
      assert_equal candidate['bundleTreeSHA256'], enclosure.attributes['beluga:bundleTreeSHA256']
      assert_equal candidate['executableSHA256'], enclosure.attributes['beluga:executableSHA256']
      refute_includes xml, 'github.com/ahmed-ela/Beluga/releases/download/'
      [0, -1, 1.0, nil].each do |size|
        assert_raises(C::Refusal) { C.trial_appcast(binding, size, signature, candidate_identity: candidate) }
      end
      [nil, 1, true, signature + "\n", Base64.strict_encode64('s' * 63), '"/>'].each do |bad|
        assert_raises(C::Refusal) { C.trial_appcast(binding, 1, bad, candidate_identity: candidate) }
      end
      assert_raises(C::Refusal) do
        C.trial_appcast(binding, 1, signature, candidate_identity: candidate.merge('build' => 101))
      end
      File.write(fixture[:path], File.binread(fixture[:path]) + "\n")
      assert_raises(C::Refusal) { C.trial_appcast(binding, 1, signature, candidate_identity: candidate) }
    end
  end

  def test_shared_appcast_preserves_fixed_production_bytes_and_escapes_all_dynamic_xml
    signature = Base64.strict_encode64('s' * 64)
    expected = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:beluga="https://github.com/ahmed-ela/Beluga/ns/update">
        <channel>
          <title>Beluga Mac updates</title>
          <link>https://github.com/ahmed-ela/Beluga</link>
          <description>Signed Beluga Mac client releases</description>
          <language>en</language>
          <item>
            <title>Beluga 0.3.0</title>
            <pubDate>Fri, 02 Oct 2026 00:00:00 -0000</pubDate>
            <sparkle:version>101</sparkle:version>
            <sparkle:shortVersionString>0.3.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <enclosure url="https://github.com/ahmed-ela/Beluga/releases/download/mac-v0.3.0/Beluga-Mac-0.3.0-101.dmg" length="12345" type="application/octet-stream" sparkle:edSignature="#{signature}" beluga:artifactSchema="beluga.update-candidate.v2" beluga:executableSHA256="#{'a' * 64}" beluga:bundleTreeSHA256="#{'b' * 64}" beluga:bundleTreeAlgorithm="beluga.bundle-tree-json-v1" />
          </item>
        </channel>
      </rss>
    XML
    assert_equal expected, C.appcast(config, 'Beluga-Mac-0.3.0-101.dmg', 12345, signature,
      Time.utc(2026, 10, 2), candidate_identity: candidate_identity)
    # Internal emitter escaping is defense in depth; the admitted URL grammar is narrower.
    text = %q[https://host.test/<tag>&"quoted'field]
    xml = C.send(:appcast_xml, config, 'Beluga-Mac-0.3.0-101.dmg', 1, signature, Time.utc(2026, 10, 2),
      candidate_identity: candidate_identity, url: text, link: text)
    document = REXML::Document.new(xml)
    assert_equal text, document.elements['rss/channel/link'].text
    assert_equal text, document.elements['rss/channel/item/enclosure'].attributes['url']
    refute C.respond_to?(:appcast_xml)
  end

  def test_trial_package_shared_workflow_emits_only_nonpromotable_reports
    %w[old new].each do |slot|
      with_trial_package_fixture(slot) do |fixture|
        with_trial_package_commands(fixture) do
          report = C::Packager.package(fixture[:options], trial_binding: fixture[:binding])
          assert_equal 'beluga.mac-client-update-trial-package.v1', report['schema']
          assert_equal 'NOTARIZED_STAPLED_SIGNED_UPDATE_TRIAL', report['status']
          %w[productionPromotionAllowed published liveInstalled microphonePCMProven].each { |key| assert_equal false, report[key] }
          %w[releaseTag feedReleaseTag feedPromotion recovery].each { |key| refute report.key?(key), key }
          assert_equal fixture[:binding].payload_url, report['payloadURL']
          assert_equal fixture[:binding].report_fields['validationBinding'], report['validationBinding']
          assert_equal fixture[:verification]['candidateIdentity'], report['candidateIdentity']
          assert_equal report, JSON.parse(File.binread(File.join(fixture[:options][:output], 'trial-package.json')))
          refute File.exist?(File.join(fixture[:options][:output], 'package.json'))
          assert_includes fixture[:events], :dmg_signature
          commands = fixture[:commands]
          assert_equal 2, commands.count { |args| args.first == fixture[:reader] }
          assert_equal 4, commands.count { |args| args.first == fixture[:signer] }
          assert_operator commands.index(fixture[:mounted_signature_command]), :<,
            commands.index([fixture[:signer], '--account', fixture[:binding].signing_account, '-p', fixture[:dmg]])
        end
      end
    end
  end

  def test_trial_package_rejects_wrong_lookup_key_before_any_sign_command
    with_trial_package_fixture do |fixture|
      fixture[:lookup_key] = fixture[:production]['publicEDKey']
      with_trial_package_commands(fixture) do
        assert_raises(C::Refusal) { C::Packager.package(fixture[:options], trial_binding: fixture[:binding]) }
        refute fixture[:commands].any? { |args| args.first == fixture[:signer] || args.include?('--sign') }
        assert_equal 1, fixture[:commands].count { |args| args.first == fixture[:reader] }
      end
    end
  end

  def test_trial_package_rechecks_authority_at_signing_notary_and_handoff_boundaries
    { dmg_sign: :report, notary: :manifest, payload_sign: :tools, feed_sign: :receipt, handoff: :source }.each do |boundary, mutation|
      with_trial_package_fixture do |fixture|
        fixture[:after_command] = lambda do |args|
          trigger = case boundary
          when :dmg_sign then args[0, 2] == ['/usr/bin/hdiutil', 'create']
          when :notary then args == ['/usr/bin/codesign', '--verify', '--strict', '--verbose=2', fixture[:dmg]]
          when :payload_sign then args[0, 2] == ['/usr/bin/hdiutil', 'detach']
          when :feed_sign then args == [fixture[:signer], '--account', fixture[:binding].signing_account, '--verify', fixture[:dmg], fixture[:signature]]
          when :handoff then args == [fixture[:signer], '--account', fixture[:binding].signing_account, '--verify', fixture[:appcast]]
          end
          next unless trigger
          case mutation
          when :report then File.write(fixture[:report_path], File.binread(fixture[:report_path]) + "\n")
          when :manifest then File.write(fixture[:path], File.binread(fixture[:path]) + "\n")
          when :tools then File.write(fixture[:signer], 'changed signer')
          when :receipt then File.write(fixture[:receipt_path], 'changed receipt')
          when :source then fixture[:source]['commit'] = '0' * 40
          end
        end
        with_trial_package_commands(fixture) do
          assert_raises(C::Refusal, boundary.to_s) { C::Packager.package(fixture[:options], trial_binding: fixture[:binding]) }
          refute File.exist?(File.join(fixture[:options][:output], 'trial-package.json'))
          case boundary
          when :dmg_sign then refute fixture[:commands].any? { |args| args.include?('--sign') }
          when :notary then refute fixture[:commands].any? { |args| args[1, 2] == %w[notarytool submit] }
          when :payload_sign then refute fixture[:commands].any? { |args| args.first == fixture[:signer] }
          when :feed_sign then refute_includes fixture[:commands], [fixture[:signer], '--account', fixture[:binding].signing_account, fixture[:appcast]]
          end
        end
      end
    end
  end

  private

  def with_trial_package_fixture(slot = 'old')
    with_admitted_trial_fixture do |fixture|
      binding = admit_trial_fixture(fixture, slot)
      app = trial_app_tree(fixture[:directory], 'build')
      File.chmod(0o700, File.dirname(app))
      C.stage_release_metadata!(app, source: fixture[:source], trial_binding: binding)
      FileUtils.mkdir_p(File.join(app, 'Contents/MacOS'))
      File.write(File.join(app, 'Contents/MacOS/CaptureServer'), 'explicit unsigned offline executable fixture', perm: 0o755)
      tree = C.tree_digest(app)
      candidate = C.candidate_identity_for_app!(app, config: binding.config, expected_tree_sha256: tree)
      verification = binding.report_fields.merge('schema' => 'beluga.mac-client-update-trial-verification.v1',
        'status' => 'VERIFIED_UPDATE_TRIAL_APP', 'version' => binding.config['version'], 'build' => binding.config['build'],
        'appSHA256' => tree, 'candidateIdentity' => candidate, 'liveInstalled' => false, 'microphonePCMProven' => false)
      logs = C::AdmittedTrialBuild::PRODUCTS.to_h do |product|
        path = File.join(File.dirname(app), "#{product}-build.log")
        File.write(path, 'explicit offline build-log fixture', perm: 0o600)
        [product, { 'path' => path, 'sha256' => Digest::SHA256.file(path).hexdigest }]
      end
      report = verification.merge(fixture[:source]).merge('schema' => 'beluga.mac-client-update-trial-build.v1',
        'status' => 'SIGNED_VERIFIED_UPDATE_TRIAL_NOT_NOTARIZED', 'app' => app,
        'identitySHA1' => TRIAL_SIGNING_IDENTITY, 'toolchain' => 'explicit offline Swift version fixture',
        'testedToolchain' => binding.tested_toolchain, 'buildLogs' => logs)
      report_path = File.join(File.dirname(app), 'trial-build.json')
      File.write(report_path, JSON.generate(report), perm: 0o600)
      output, mount, tools = %w[output mount tools].map { |name| File.join(fixture[:directory], name) }
      [output, mount, tools].each { |path| Dir.mkdir(path, 0o700) }
      signer, reader = %w[sign_update generate_keys].map do |name|
        path = File.join(tools, name)
        File.write(path, 'explicit never-executed Sparkle fixture', perm: 0o755)
        path
      end
      tool_info = File.join(fixture[:directory], 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/Resources/Info.plist')
      FileUtils.mkdir_p(File.dirname(tool_info))
      File.write(tool_info, 'explicit distribution-plist double', perm: 0o644)
      requirement = "identifier \"#{C::BUNDLE_ID}\" and anchor apple generic and certificate leaf = H\"#{TRIAL_SIGNING_IDENTITY}\" and certificate leaf[subject.OU] = \"#{C::TEAM}\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
      fixture.merge!(binding: binding, app: app, verification: verification, report_path: report_path,
        options: { app: app, output: output, identity: TRIAL_SIGNING_IDENTITY, profile: 'offline-notary', tools: tools, account: binding.signing_account },
        signer: signer, reader: reader, tool_info: tool_info, mount: mount,
        dmg: File.join(output, binding.payload_name), appcast: File.join(output, 'appcast.xml'),
        signature: Base64.strict_encode64('s' * 64), commands: [], events: [],
        app_signature_command: ['/usr/bin/codesign', '--verify', '--strict', "-R=#{requirement}", app],
        mounted_signature_command: ['/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', File.join(mount, 'Beluga Host.app')],
        app_info: C.plist(File.join(app, 'Contents/Info.plist')))
      yield fixture
    end
  end

  def with_trial_package_commands(fixture)
    app, binding, options = fixture.values_at(:app, :binding, :options)
    dmg, signer, reader, mount, appcast = fixture.values_at(:dmg, :signer, :reader, :mount, :appcast)
    account, signature = binding.signing_account, fixture[:signature]
    staged_app = File.join(options[:output], 'image-root/Beluga Host.app')
    native_verify = lambda do |path, authority|
      assert_equal app, path
      assert_same binding, authority
      C.require!(C.tree_digest(path) == fixture[:verification]['appSHA256'], 'offline app changed')
      fixture[:verification]
    end
    run = lambda do |*args, **_keywords|
      fixture[:commands] << args.dup
      result = case args
      when fixture[:app_signature_command], fixture[:mounted_signature_command],
           ['/usr/bin/codesign', '--sign', TRIAL_SIGNING_IDENTITY, '--timestamp', dmg],
           ['/usr/bin/codesign', '--verify', '--strict', '--verbose=2', dmg],
           ['/usr/bin/xcrun', 'stapler', 'staple', dmg], ['/usr/bin/xcrun', 'stapler', 'validate', dmg],
           ['/usr/sbin/spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg],
           ['/usr/bin/hdiutil', 'verify', dmg], ['/usr/bin/hdiutil', 'detach', mount]
        ''
      when [reader, '--account', account, '-p'] then fixture.fetch(:lookup_key, binding.config['publicEDKey'])
      when ['/usr/bin/plutil', '-extract', 'BelugaPairedPhoneCatalogVersion', 'raw', '-expect', 'integer', '-n', File.join(mount, 'Beluga Host.app/Contents/Info.plist')]
        fixture[:app_info].fetch('BelugaPairedPhoneCatalogVersion').to_s
      when ['/usr/bin/ditto', '--noqtn', app, staged_app]
        FileUtils.cp_r(app, staged_app, preserve: true)
        ''
      when ['/usr/bin/hdiutil', 'create', '-volname', "Beluga #{binding.config['version']}", '-srcfolder', File.dirname(staged_app), '-fs', 'APFS', '-format', 'ULFO', dmg]
        File.write(dmg, 'explicit offline DMG command double', perm: 0o600)
        ''
      when ['/usr/bin/xcrun', 'notarytool', 'submit', dmg, '--keychain-profile', options[:profile], '--wait', '--timeout', '20m', '--output-format', 'json']
        JSON.generate('status' => 'Accepted', 'id' => TRIAL_NOTARY_ID)
      when ['/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', mount, dmg]
        FileUtils.cp_r(staged_app, File.join(mount, 'Beluga Host.app'), preserve: true)
        File.symlink('/Applications', File.join(mount, 'Applications'))
        ''
      when [signer, '--account', account, '-p', dmg] then signature
      when [signer, '--account', account, '--verify', dmg, signature] then ''
      when [signer, '--account', account, appcast]
        File.write(appcast, File.binread(appcast) + "<!-- explicit offline feed-signature double -->\n")
        ''
      when [signer, '--account', account, '--verify', appcast]
        assert_includes File.binread(appcast), '<!-- explicit offline feed-signature double -->'
        ''
      else flunk "unrecognized native command in offline test: #{args.inspect}"
      end
      fixture[:after_command]&.call(args)
      result
    end
    plist = lambda do |path|
      case path
      when fixture[:tool_info] then { 'CFBundleShortVersionString' => C::SPARKLE_VERSION, 'CFBundleVersion' => '2064' }
      when File.join(mount, 'Beluga Host.app/Contents/Info.plist') then fixture[:app_info]
      else flunk "unrecognized plist double: #{path}"
      end
    end
    tool_check = lambda { |path| assert_equal options[:tools], path; fixture[:events] << :tools }
    signature_check = lambda do |path, **keywords|
      assert_equal dmg, path
      assert_equal({ identity: TRIAL_SIGNING_IDENTITY, identifier: File.basename(dmg, '.dmg') }, keywords)
      fixture[:events] << :dmg_signature
    end
    C.stub(:verify_trial_app!, native_verify) do
      C.stub(:tools!, tool_check) do
        C.stub(:plist, plist) do
          C.stub(:private_package_mount!, mount) do
            C.stub(:verify_dmg_signature!, signature_check) do
              C.stub(:run, run) { yield }
            end
          end
        end
      end
    end
  end
end
