# frozen_string_literal: true
require_relative 'update-trial-profile'
require_relative 'retained-beluga-mac-client'

module BelugaMacClient
  class AdmittedUpdateTrial
    attr_reader :config, :build_source, :source, :slot, :report_fields,
                :trial_id, :namespace_url, :payload_name, :payload_url, :signing_account, :tested_toolchain

    def self.open(path, digest, slot:, approved_namespace:, approved_public_key:, receipt: MicrophoneReceipt.new)
      BelugaMacClient.require!(receipt.instance_of?(MicrophoneReceipt), 'trial admission requires the production receipt validator')
      receipt.verify!
      reader = RetainedEvidence::Reader.new
      info = BelugaMacClient.regular!(path)
      BelugaMacClient.require!(info.uid == Process.uid && (info.mode & 0o077).zero?, 'trial manifest must be owner-private')
      bytes = reader.read(path, expected: digest, limit: UpdateTrialProfile::MAXIMUM_MANIFEST_BYTES)
      source = BelugaMacClient.source!
      release_bytes = reader.read(CONFIG_PATH, limit: 16 * 1024, private_parent: false)
      production = BelugaMacClient.config!
      receipt_binding = receipt.evidence_binding
      toolchain = receipt.tested_toolchain
      BelugaMacClient.require!(toolchain.instance_of?(TestedToolchain), 'trial admission requires the tested toolchain')
      toolchain.verify!
      profile = UpdateTrialProfile.parse(bytes, expected_manifest_sha256: digest,
        production_config: production, trusted_source: source,
        source_release_sha256: Digest::SHA256.hexdigest(release_bytes),
        receipt_sha256: receipt_binding.fetch('sha256'), tested_toolchain: toolchain.binding,
        approved_namespace: approved_namespace, approved_public_key: approved_public_key)
      admitted = new(reader, receipt, receipt_binding, toolchain, source, production, profile, slot)
      admitted.verify!
      admitted
    end

    def verify!
      @receipt.verify!
      @reader.verify!
      @toolchain.verify!
      BelugaMacClient.require!(@receipt.evidence_binding == @receipt_binding &&
        @toolchain.binding == @toolchain_binding && BelugaMacClient.source! == @source &&
        BelugaMacClient.config! == @production, 'trial source, receipt, configuration or toolchain changed')
      true
    end

    def receipt_for_build
      verify!
      @receipt
    end

    def inspect
      '#<BelugaMacClient::AdmittedUpdateTrial>'
    end
    alias to_s inspect

    private

    def initialize(reader, receipt, receipt_binding, toolchain, source, production, profile, slot)
      @reader, @receipt, @toolchain = reader, receipt, toolchain
      @receipt_binding = RetainedEvidence.freeze_data(Marshal.load(Marshal.dump(receipt_binding)))
      @toolchain_binding = RetainedEvidence.freeze_data(Marshal.load(Marshal.dump(toolchain.binding)))
      @source = RetainedEvidence.freeze_data(Marshal.load(Marshal.dump(source)))
      @production = RetainedEvidence.freeze_data(Marshal.load(Marshal.dump(production)))
      @config = profile.config(slot)
      @build_source = profile.build_source(slot)
      @slot = slot.dup.freeze
      @trial_id, @namespace_url = profile.trial_id, profile.namespace_url
      @payload_name, @payload_url = profile.payload_name(slot), profile.payload_url(slot)
      @signing_account = "beluga-update-trial-#{@trial_id}".freeze
      @tested_toolchain = @toolchain_binding
      @report_fields = RetainedEvidence.freeze_data({
        'validationBinding' => @build_source.fetch('validationBinding'),
        'productionPromotionAllowed' => false, 'published' => false
      })
      freeze
    end

    private_class_method :new
  end

  def self.trial_artifact_binding!(binding)
    require!(binding.instance_of?(AdmittedUpdateTrial), 'trial artifact requires filesystem-admitted evidence')
    binding.verify!
    binding
  end

  def self.release_info(config)
    {
      'CFBundleShortVersionString' => config['version'], 'CFBundleVersion' => config['build'].to_s,
      'SUFeedURL' => config['feedURL'], 'SUPublicEDKey' => config['publicEDKey'],
      'SUVerifyUpdateBeforeExtraction' => true, 'SURequireSignedFeed' => true,
      'SUAllowsAutomaticUpdates' => false, 'BelugaUpdateOwnershipProtocol' => 1,
      'BelugaPairedPhoneCatalogVersion' => PAIRED_PHONE_CATALOG_VERSION
    }
  end

  # Used by the real builder; tests exercise these exact staged files before any signing.
  def self.stage_release_metadata!(app, source:, trial_binding: nil)
    trial_artifact_binding!(trial_binding) unless trial_binding.nil?
    if trial_binding
      binding = trial_artifact_binding!(trial_binding)
      require!(source == binding.source, 'trial staging source differs')
      config = binding.config
      release_bytes = JSON.pretty_generate(config) + "\n"
      provenance = binding.build_source
    else
      require!(source == source!, 'production staging source differs')
      config = config!
      release_bytes = File.binread(CONFIG_PATH)
      provenance = source
    end
    canonical!(app)
    source_bytes = JSON.pretty_generate(provenance) + "\n"
    ['', BROKER].each do |relative|
      resources = canonical!(File.join(app, relative, 'Contents/Resources'))
      File.write(File.join(resources, 'Release.json'), release_bytes, mode: 'wx', perm: 0o644)
      File.write(File.join(resources, 'BuildSource.json'), source_bytes, mode: 'wx', perm: 0o644)
    end
    info = File.join(app, 'Contents/Info.plist')
    FileUtils.cp(File.join(ROOT, 'macOS/BelugaHost/Info.plist'), info)
    release_info(config).each { |key, value| plist_set(info, key, value) }
    broker = File.join(app, BROKER, 'Contents/Info.plist')
    FileUtils.cp(File.join(ROOT, 'macOS/BelugaUpdater/Info.plist'), broker)
    broker_info(config).each { |key, value| plist_set(broker, key, value) }
    trial_artifact_binding!(trial_binding) if trial_binding
    config
  end
end
