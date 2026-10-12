# frozen_string_literal: true
# Artifact-only recovery on the trusted release Mac. No compilation, signing,
# installation, Keychain access, or retrospective fabrication of build success.
require_relative 'retained-beluga-mac-client-model'
require_relative '../../scripts/microphone-regression-gate'

module BelugaMacClient
  def self.package_evidence_mode!(app, retained_path, retained_sha)
    supplied = !retained_path.nil? || !retained_sha.nil?
    require!(!supplied || (retained_path.is_a?(String) && !retained_path.empty? &&
      retained_sha.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(retained_sha)), 'retained manifest and SHA must be supplied together')
    build = File.join(File.dirname(app), 'build.json')
    exists = File.exist?(build) || File.symlink?(build)
    require!(supplied != exists, 'choose exactly one successful build report or retained admission')
    supplied ? :retained : :build
  end

  module RetainedEvidence
    # These are the only non-product inputs eligible for this reviewed seam.
    # The manifest additionally pins the exact complete diff and blob identities.
    TOOLING_PATHS = %w[
      MAC_CLIENT_ROADMAP.md
      macOS/scripts/build-beluga-mac-client-contract.rb
      macOS/scripts/verify-beluga-mac-client.rb
      macOS/scripts/package-beluga-mac-client.rb
      macOS/scripts/verify-beluga-mac-client-tests.rb
      macOS/scripts/retained-beluga-mac-client.rb
      macOS/scripts/retained-beluga-mac-client-model.rb
      macOS/scripts/retained-beluga-mac-client-tests.rb
      scripts/microphone-regression-gate.rb
      scripts/test-validate-microphone-regressions.rb
    ].freeze
    FAILURE = "build-beluga-mac-client: hardened runtime/secure timestamp required\n".freeze
    BUILDER = 'macOS/scripts/build-beluga-mac-client.rb'.freeze

    def self.completed_product_log!(bytes, product)
      text = BelugaMacClient.utf8_text(bytes, 'retained product log')
      terminals = text.lines.map(&:chomp).select { |line| line.start_with?('Build of product') }
      pattern = /\ABuild of product '#{Regexp.escape(product)}' complete! \([0-9]+(?:\.[0-9]+)?s\)\z/
      BelugaMacClient.require!(terminals.length == 1 && pattern.match?(terminals.first), 'retained exact product compilation terminal is absent or ambiguous')
      true
    end

    def self.freeze_data(value)
      case value
      when Hash then value.each { |key, item| freeze_data(key); freeze_data(item) }
      when Array then value.each { |item| freeze_data(item) }
      end
      value.freeze
    end

    def self.fresh_inputs!(source_inventory, tools)
      BelugaMacClient.require!(MicrophoneRegressionGate.source_identity(ROOT) == source_inventory, 'retained product/tooling input inventory changed')
      tools.each { |path, digest| BelugaMacClient.require!(MicrophoneRegressionGate.sha(path) == digest, 'retained tested tool bytes changed') }
      true
    rescue RuntimeError
      raise Refusal, 'retained product/tooling inputs are unsafe'
    end

    def self.inventory!(value)
      BelugaMacClient.require!(value.is_a?(Hash) && value.keys.sort == %w[files sha256] && value['files'].is_a?(Array), 'retained source inventory schema differs')
      files = value['files']
      BelugaMacClient.require!(files.all? { |row| row.is_a?(Array) && row.length == 4 && row[0].is_a?(String) &&
        !row[0].empty? && !row[0].start_with?('/') && (row[0].split('/') & %w[. ..]).empty? &&
        row[1] == 'file' && row[2].is_a?(Integer) && (0..0o777).cover?(row[2]) &&
        row[3].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(row[3]) }, 'retained source inventory entry differs')
      names = files.map(&:first)
      BelugaMacClient.require!(names == names.uniq.sort && Digest::SHA256.hexdigest(JSON.generate(files)) == value['sha256'], 'retained source inventory digest/order differs')
      files.to_h { |row| [row.first, row] }
    end

    # Read actual permission tuples from each sealed receipt. Git only records
    # executable/non-executable, so it cannot supply the original 0600/0644 bits.
    def self.equivalent_inputs!(original, current, delta, blobs)
      old = inventory!(original)
      now = inventory!(current)
      paths = delta.map { |entry| entry.fetch('path') }
      BelugaMacClient.require!(!paths.empty? && paths == paths.uniq.sort && (paths - TOOLING_PATHS).empty?, 'retained product contains an unreviewed source delta')
      delta.each do |entry|
        path = entry.fetch('path')
        %w[original current].zip([old, now]).each do |prefix, rows|
          mode = entry.fetch(prefix + 'Mode')
          oid = entry.fetch(prefix + 'BlobSHA1')
          if mode == 0
            BelugaMacClient.require!(oid == '0' * 40 && !rows.key?(path), 'absent tooling blob differs from inventory')
          else
            row = rows.fetch(path) { raise Refusal, 'tooling blob absent from receipt' }
            BelugaMacClient.require!([100644, 100755].include?(mode) && (row[2] & 0o111 == 0 ? 100644 : 100755) == mode &&
              Digest::SHA256.hexdigest(blobs.fetch(oid)) == row[3], 'tooling blob or permission differs from receipt')
          end
        end
      end
      BelugaMacClient.require!(old.reject { |path, _| paths.include?(path) } == now.reject { |path, _| paths.include?(path) }, 'product, ignored dependency, or resource inputs changed')
      true
    end

    class Reader
      def initialize
        @files = {}
        @directories = {}
        @trees = {}
      end

      def directory(path, private_root: false)
        BelugaMacClient.canonical!(path)
        info = File.lstat(path)
        BelugaMacClient.require!(info.directory? && info.uid == Process.uid && (info.mode & 0o022).zero? &&
          (!private_root || info.mode & 0o777 == 0o700), 'retained evidence directory is unsafe')
        record = [info.dev, info.ino, info.uid, info.gid, info.mode]
        BelugaMacClient.require!(!@directories.key?(path) || @directories[path] == record, 'retained evidence directory replaced')
        @directories[path] = record
      end

      def read(path, expected: nil, limit: 8 * 1024 * 1024, private_parent: true)
        directory(File.dirname(path), private_root: private_parent)
        stat = BelugaMacClient.regular!(path)
        BelugaMacClient.require!(stat.uid == Process.uid && stat.size <= limit, 'retained evidence owner or size differs')
        before = BelugaMacClient.snapshot(path)
        bytes = File.binread(path, limit + 1) || ''.b
        BelugaMacClient.require!(bytes.bytesize <= limit && before == BelugaMacClient.snapshot(path) &&
          before.last == Digest::SHA256.hexdigest(bytes) && (!expected || before.last == expected), 'retained evidence changed')
        BelugaMacClient.require!(!@files.key?(path) || @files[path] == before, 'retained evidence replaced')
        @files[path] = before
        bytes
      end

      def json(binding)
        JSON.parse(read(binding.fetch('path'), expected: binding.fetch('sha256')), object_class: UniqueObject)
      end

      def tree(path, expected, kind:)
        directory(path)
        digest = kind == :app ? BelugaMacClient.tree_digest(path) : MicrophoneRegressionGate.tree_identity(path)
        BelugaMacClient.require!(digest == expected, 'retained artifact tree changed')
        @trees[path] = [expected, kind]
      rescue RuntimeError
        raise Refusal, 'retained artifact tree is malformed'
      end

      def verify!
        @directories.keys.each { |path| directory(path) }
        @files.each { |path, record| BelugaMacClient.require!(BelugaMacClient.snapshot(path) == record, 'retained evidence identity changed') }
        @trees.each { |path, (digest, kind)| tree(path, digest, kind: kind) }
        true
      end
    end

    def self.git(*args)
      BelugaMacClient.run('/usr/bin/git', '-C', ROOT, *args)
    end

    def self.delta!(original, current)
      BelugaMacClient.require!(git('rev-parse', original.fetch('commit') + '^{tree}').strip == original.fetch('tree'), 'original Git source tree differs')
      git('merge-base', '--is-ancestor', original.fetch('commit'), current.fetch('commit'))
      fields = git('diff', '--raw', '--no-renames', '--no-abbrev', '-z', original.fetch('commit'), current.fetch('commit'), '--').split("\0")
      BelugaMacClient.require!(fields.length.even?, 'raw retained Git delta is malformed')
      fields.each_slice(2).map do |header, path|
        match = /\A:(000000|100644|100755) (000000|100644|100755) ([0-9a-f]{40}) ([0-9a-f]{40}) [AMD]\z/.match(header)
        BelugaMacClient.require!(match && TOOLING_PATHS.include?(path), 'retained product diff is outside reviewed tooling paths')
        { 'path' => path, 'originalMode' => match[1].to_i, 'currentMode' => match[2].to_i,
          'originalBlobSHA1' => match[3], 'currentBlobSHA1' => match[4] }
      end.sort_by { |entry| entry.fetch('path') }
    end

    def self.historical!(reader, binding, current)
      old = reader.json(binding)
      BelugaMacClient.require!(old['schema'] == MicrophoneRegressionGate::SCHEMA && old['status'] == 'passed' &&
        old['scope'] == 'offline-source-only' && old['root'] == ROOT && old['tools'] == current['tools'] &&
        old.dig('invocation', 'developer_directory') == current.dig('invocation', 'developer_directory') &&
        old['created_at'].is_a?(Integer) && old['created_at'] <= current['created_at'], 'historical receipt identity/toolchain differs')
      phases = old.fetch('phases')
      BelugaMacClient.require!(phases.map { |entry| entry['name'] } == MicrophoneRegressionGate::PHASES, 'historical phases differ')
      phases.each do |entry|
        name = entry.fetch('name')
        BelugaMacClient.require!(entry['log'] == name + '.log', 'historical phase escapes retained evidence')
        reader.read(File.join(File.dirname(binding['path']), entry['log']), expected: entry.fetch('sha256'), limit: 32 * 1024 * 1024)
      end
      expected_artifacts = %w[simulator-result driver-bundle-1 driver-bundle-2 simulator-app]
      expected_artifacts << 'mac-xunit' if old['mac_format'] == 'xunit'
      BelugaMacClient.require!(old.fetch('artifacts').map { |entry| entry['name'] } == expected_artifacts, 'historical artifacts differ')
      old.fetch('artifacts').each do |entry|
        path = entry.fetch('path')
        BelugaMacClient.require!(path.is_a?(String) && !path.empty? && !path.start_with?('/') && (path.split('/') & %w[. ..]).empty?, 'historical artifact path escapes evidence')
        path = File.join(File.dirname(binding['path']), path)
        if entry['tree'] == true
          reader.tree(path, entry.fetch('sha256'), kind: :historical)
        else
          BelugaMacClient.require!(entry['tree'] == false, 'historical artifact kind differs')
          reader.read(path, expected: entry.fetch('sha256'))
        end
      end
      old
    end
  end

  # Only this filesystem collector can construct a source-binding accepted by
  # verify_app!. A data-only manifest parser is deliberately not that authority.
  class AdmittedRetainedProduct
    attr_reader :product_source, :provenance

    def self.open(path, digest, receipt:, app:, identity:)
      BelugaMacClient.require!(receipt.instance_of?(MicrophoneReceipt), 'retained admission requires the production current receipt validator')
      receipt.verify!
      reader = RetainedEvidence::Reader.new
      bytes = reader.read(path, expected: digest, limit: 256 * 1024)
      declared = JSON.parse(bytes, object_class: UniqueObject)
      BelugaMacClient.require!(declared.is_a?(Hash), 'retained manifest must be an object')
      # Shape admission only. Independent collection/equality occurs below.
      context = declared.reject { |key, _| %w[schema authority].include?(key) }
      shape = RetainedProductBinding.parse(bytes, expected_manifest_sha256: digest, collected_context: context)
      current_source = BelugaMacClient.source!
      current_binding = receipt.evidence_binding
      current = reader.json(current_binding)
      old = RetainedEvidence.historical!(reader, declared.fetch('originalReceipt'), current)
      delta = RetainedEvidence.delta!(declared.fetch('originalProduct'), current_source)
      blobs = delta.flat_map { |entry| %w[originalBlobSHA1 currentBlobSHA1].map { |key| entry.fetch(key) } }.uniq.reject { |oid| oid == '0' * 40 }
        .to_h { |oid| [oid, RetainedEvidence.git('cat-file', 'blob', oid)] }
      RetainedEvidence.equivalent_inputs!(old.fetch('source'), current.fetch('source'), delta, blobs)
      failed = declared.fetch('failedBuild')
      output = File.dirname(app)
      reader.directory(output, private_root: true)
      BelugaMacClient.require!(!File.exist?(File.join(output, 'build.json')) && !File.symlink?(File.join(output, 'build.json')), 'retained and successful build authority cannot coexist')
      builder_sha = Digest::SHA256.hexdigest(RetainedEvidence.git('show', declared.dig('originalProduct', 'commit') + ':' + RetainedEvidence::BUILDER))
      BelugaMacClient.require!(builder_sha == Digest::SHA256.file(File.join(ROOT, RetainedEvidence::BUILDER)).hexdigest &&
        failed['builderScriptSHA256'] == builder_sha, 'actual builder input changed')
      scratch = failed.fetch('environment').fetch('TMPDIR')
      env = receipt.tested_toolchain.build_environment(temporary_directory: scratch)
      argv = ['/usr/bin/ruby', RetainedEvidence::BUILDER, '--output', output, '--scratch', scratch, '--identity', identity]
      BelugaMacClient.require!(failed['argv'] == argv && failed['environment'] == env, 'retained build invocation/environment differs')
      failed.fetch('logs').each do |entry|
        expected_path = File.join(output, entry.fetch('product') + '-build.log')
        BelugaMacClient.require!(entry['path'] == expected_path, 'retained product log differs')
        log = reader.read(entry['path'], expected: entry['sha256'])
        RetainedEvidence.completed_product_log!(log, entry['product'])
      end
      failure = reader.read(failed.dig('failureLog', 'path'), expected: failed.dig('failureLog', 'sha256'))
      BelugaMacClient.require!(failure == RetainedEvidence::FAILURE, 'retained attempt has a different failure terminal')
      observation = reader.json(failed.fetch('observerAttestation'))
      expected_observation = {
        'schema' => 'beluga.retained-build-observation.v1', 'authority' => 'trusted-root-observed-failed-build',
        'scope' => 'retrospective-observation-not-successful-build', 'workingDirectory' => ROOT,
        'originalProduct' => declared['originalProduct'], 'originalReceipt' => declared['originalReceipt'],
        'app' => declared['app'], 'identitySHA1' => identity,
        'failedBuild' => failed.reject { |key, _| key == 'observerAttestation' }
      }
      BelugaMacClient.require!(observation == expected_observation, 'independent retrospective observation differs or asserts build success')
      reader.tree(app, declared.dig('app', 'treeSHA256'), kind: :app)
      observed = context.merge('currentTooling' => current_source, 'currentReceipt' => current_binding,
        'gitDelta' => delta, 'identitySHA1' => identity, 'app' => { 'path' => app, 'treeSHA256' => BelugaMacClient.tree_digest(app) })
      RetainedProductBinding.parse(bytes, expected_manifest_sha256: digest, collected_context: observed)
      reader.verify!
      BelugaMacClient.require!(BelugaMacClient.source! == current_source, 'current source changed during retained admission')
      binding = new(reader, receipt, current_source, shape, path, digest, app, current)
      binding.verify!(app)
      binding
    rescue KeyError, TypeError, JSON::ParserError
      raise Refusal, 'retained evidence is incomplete or malformed'
    end

    def initialize(reader, receipt, current_source, shape, path, digest, app, current)
      @reader, @receipt = reader, receipt
      @current_source, @app = RetainedProductBinding.copy(current_source), RetainedProductBinding.copy(app)
      @product_source = shape.original_product
      @input_inventory = RetainedEvidence.freeze_data(current.fetch('source'))
      @tested_tools = RetainedEvidence.freeze_data(current.fetch('tools'))
      @provenance = RetainedProductBinding.copy({ 'kind' => 'retained-artifact', 'manifest' => { 'path' => path, 'sha256' => digest },
        'originalProduct' => @product_source, 'currentTooling' => @current_source,
        'originalReceipt' => shape.original_receipt, 'currentReceipt' => receipt.evidence_binding,
        'originalBuildSucceeded' => false })
      freeze
    end
    private_class_method :new

    def verify!(app)
      BelugaMacClient.require!(app == @app && BelugaMacClient.source! == @current_source, 'retained source/app boundary changed')
      BelugaMacClient.require!(!File.exist?(File.join(File.dirname(app), 'build.json')) && !File.symlink?(File.join(File.dirname(app), 'build.json')), 'ambiguous retained/build authority')
      @receipt.evidence_binding
      RetainedEvidence.fresh_inputs!(@input_inventory, @tested_tools)
      @reader.verify!
    end
  end
end
