# frozen_string_literal: true
require_relative 'verify-beluga-mac-client'

module BelugaMacClient
  class AdmittedTrialBuild
    REPORT_KEYS = %w[schema status version build appSHA256 candidateIdentity liveInstalled microphonePCMProven validationBinding productionPromotionAllowed published commit tree app identitySHA1 toolchain testedToolchain buildLogs].sort.freeze
    PRODUCTS = %w[CaptureServer OpensteamerMediaBridge BelugaUpdater].freeze
    attr_reader :verification, :provenance

    def self.open(app, trial_binding:, identity:)
      binding = BelugaMacClient.trial_artifact_binding!(trial_binding)
      BelugaMacClient.canonical!(app)
      BelugaMacClient.require!(identity.is_a?(String) && /\A[0-9A-F]{40}\z/.match?(identity), 'trial build identity is malformed')
      verification = BelugaMacClient.verify_trial_app!(app, binding)
      reader = RetainedEvidence::Reader.new
      path = File.join(File.dirname(app), 'trial-build.json')
      info = BelugaMacClient.regular!(path)
      BelugaMacClient.require!((info.mode & 0o077).zero?, 'trial build report must be owner-private')
      bytes = reader.read(path, limit: 1024 * 1024)
      report = JSON.parse(bytes, object_class: UniqueObject)
      BelugaMacClient.require!(report.is_a?(Hash) && report.keys.sort == REPORT_KEYS, 'trial build report fields differ')
      expected = verification.merge(binding.source).merge('schema' => 'beluga.mac-client-update-trial-build.v1',
        'status' => 'SIGNED_VERIFIED_UPDATE_TRIAL_NOT_NOTARIZED', 'app' => app, 'identitySHA1' => identity,
        'testedToolchain' => binding.tested_toolchain)
      BelugaMacClient.require!(report['build'].is_a?(Integer) &&
        expected.all? { |key, value| report[key] == value }, 'trial build report differs from verified app/source/receipt/toolchain')
      BelugaMacClient.candidate_identity!(report['candidateIdentity'], config: binding.config)
      BelugaMacClient.require!(report['candidateIdentity']['bundleTreeSHA256'] == verification['appSHA256'], 'trial candidate tree differs')
      requirement = "identifier \"#{BUNDLE_ID}\" and anchor apple generic and certificate leaf = H\"#{identity}\" and certificate leaf[subject.OU] = \"#{TEAM}\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
      BelugaMacClient.run('/usr/bin/codesign', '--verify', '--strict', "-R=#{requirement}", app)
      BelugaMacClient.require!(report['toolchain'].is_a?(String) && !report['toolchain'].empty? &&
        report['toolchain'].bytesize <= 8192, 'trial build toolchain description is malformed')
      logs = report['buildLogs']
      BelugaMacClient.require!(logs.is_a?(Hash) && logs.keys.sort == PRODUCTS.sort, 'trial build log inventory differs')
      PRODUCTS.each do |product|
        log = logs[product]
        BelugaMacClient.require!(log.is_a?(Hash) && log.keys.sort == %w[path sha256] &&
          log['path'] == File.join(File.dirname(app), "#{product}-build.log") &&
          log['sha256'].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(log['sha256']), 'trial build log binding differs')
        reader.read(log['path'], expected: log['sha256'], limit: 16 * 1024 * 1024)
      end
      reader.tree(app, verification.fetch('appSHA256'), kind: :app)
      admitted = new(binding, reader, app, verification, path, Digest::SHA256.hexdigest(bytes))
      admitted.verify!
      admitted
    rescue JSON::ParserError
      raise Refusal, 'invalid trial build report JSON'
    end

    def verify!
      BelugaMacClient.trial_artifact_binding!(@binding)
      production_report = File.join(File.dirname(@app), 'build.json')
      BelugaMacClient.require!(!File.exist?(production_report) && !File.symlink?(production_report), 'trial package cannot mix production build evidence')
      @reader.verify!
      true
    end

    private

    def initialize(binding, reader, app, verification, path, digest)
      @binding, @reader, @app = binding, reader, app.dup.freeze
      @verification = RetainedEvidence.freeze_data(Marshal.load(Marshal.dump(verification)))
      @provenance = RetainedEvidence.freeze_data({ 'kind' => 'successful-trial-build', 'path' => path, 'sha256' => digest })
      freeze
    end

    private_class_method :new
  end

  def self.trial_package_options!(options, binding)
    admitted = trial_artifact_binding!(binding)
    require!(options.keys.sort == %i[account app identity output profile tools], 'trial packaging forbids retained/resume/unknown options')
    require!(options[:account] == admitted.signing_account, 'trial signing account must match the admitted trial UUID')
    admitted
  end

  def self.trial_appcast(binding, size, signature, now = Time.now, candidate_identity:)
    admitted = trial_artifact_binding!(binding)
    xml = appcast_xml(admitted.config, admitted.payload_name, size, signature, now,
      candidate_identity: candidate_identity, url: admitted.payload_url, link: admitted.namespace_url)
    trial_artifact_binding!(admitted)
    xml
  end
end
