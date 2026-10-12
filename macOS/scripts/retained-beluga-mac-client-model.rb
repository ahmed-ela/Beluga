# frozen_string_literal: true

require_relative 'build-beluga-mac-client-contract'

# Data parsing alone is not filesystem or artifact admission.
module BelugaMacClient

  class RetainedProductBinding
    MAXIMUM_MANIFEST_BYTES = 32 * 1024
    SCHEMA = 'beluga.mac-client-retained-admission.v1'.freeze
    AUTHORITY = 'trusted-root-observed-failed-build'.freeze
    BUILDER = 'macOS/scripts/build-beluga-mac-client.rb'.freeze
    PRODUCTS = %w[CaptureServer OpensteamerMediaBridge BelugaUpdater].each(&:freeze).freeze
    CONTEXT_KEYS = %w[originalProduct currentTooling originalReceipt currentReceipt app identitySHA1 gitDelta failedBuild].sort.each(&:freeze).freeze
    MANIFEST_KEYS = (CONTEXT_KEYS + %w[schema authority]).sort.each(&:freeze).freeze
    FAILED_KEYS = %w[builderScriptSHA256 argv environment logs failureLog observerAttestation originalFinalChecksCompleted successfulBuildReport stage].sort.each(&:freeze).freeze
    ENVIRONMENT_KEYS = %w[PATH HOME DEVELOPER_DIR TMPDIR LC_ALL MACOSX_DEPLOYMENT_TARGET SWIFT_TREAT_WARNINGS_AS_ERRORS].sort.each(&:freeze).freeze
    DELTA_KEYS = %w[path originalMode currentMode originalBlobSHA1 currentBlobSHA1].sort.each(&:freeze).freeze

    class UniqueObject < Hash
      def []=(key, value)
        raise Refusal, 'duplicate JSON field' if key?(key)
        super
      end
    end

    attr_reader :manifest_sha256, :original_product, :current_tooling,
                :original_receipt, :current_receipt, :app, :identity_sha1,
                :git_delta, :failed_build

    def self.parse(bytes, expected_manifest_sha256:, collected_context:)
      check(bytes.is_a?(String) && !bytes.empty? && bytes.bytesize <= MAXIMUM_MANIFEST_BYTES,
            'manifest byte bound differs')
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      check(text.valid_encoding?, 'manifest is not UTF-8')
      digest!(expected_manifest_sha256, 64, uppercase: false)
      digest = Digest::SHA256.hexdigest(bytes)
      check(digest == expected_manifest_sha256, 'manifest digest differs')
      manifest = JSON.parse(text, object_class: UniqueObject, max_nesting: 8, allow_nan: false)
      object!(manifest, MANIFEST_KEYS)
      check(manifest['schema'] == SCHEMA && manifest['authority'] == AUTHORITY,
            'retained admission schema/authority differs')
      claimed = CONTEXT_KEYS.to_h { |key| [key, manifest.fetch(key)] }
      validate_context!(claimed)
      collected = copy(collected_context)
      validate_context!(collected)
      check(claimed == collected, 'independently collected binding differs')
      new(collected, digest)
    rescue JSON::ParserError, JSON::NestingError
      raise Refusal, 'invalid bounded JSON manifest'
    end

    # Only this source can be passed onward as expected PRODUCT provenance.
    # It is not current tooling and is not a new build or verification report.
    def expected_product_source
      @original_product
    end

    def successful_build_report?
      false
    end

    def original_final_checks_completed?
      false
    end

    def retrospective_observer_claim?
      true
    end

    def inspect
      '#<BelugaMacClient::RetainedProductBinding data-only>'
    end
    alias to_s inspect

    private

    def initialize(context, digest)
      @manifest_sha256 = self.class.copy(digest)
      @original_product = context.fetch('originalProduct')
      @current_tooling = context.fetch('currentTooling')
      @original_receipt = context.fetch('originalReceipt')
      @current_receipt = context.fetch('currentReceipt')
      @app = context.fetch('app')
      @identity_sha1 = context.fetch('identitySHA1')
      @git_delta = context.fetch('gitDelta')
      @failed_build = context.fetch('failedBuild')
      freeze
    end

    class << self
      def check(condition, message)
        raise Refusal, message unless condition
      end

      def object!(value, keys)
        check(value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) } &&
              value.keys.sort == keys, 'data object fields differ')
      end

      def text!(value)
        check(value.is_a?(String) && !value.empty? && value.bytesize <= 4096 &&
              value.valid_encoding? && !value.match?(/[\x00-\x1f\x7f]/), 'text field is not bounded')
      end

      def digest!(value, length, uppercase: false)
        check(value.is_a?(String) && value.valid_encoding? && value.ascii_only? &&
              value.bytesize == length, 'digest shape differs')
        pattern = uppercase ? /\A[0-9A-F]+\z/ : /\A[0-9a-f]+\z/
        check(pattern.match?(value) && value != '0' * length, 'digest is not canonical nonzero')
      end

      def source!(value)
        object!(value, %w[commit tree])
        value.values.each { |item| digest!(item, 40) }
      end

      def evidence!(value)
        object!(value, %w[path sha256])
        text!(value['path'])
        digest!(value['sha256'], 64)
      end

      def validate_context!(context)
        object!(context, CONTEXT_KEYS)
        source!(context['originalProduct'])
        source!(context['currentTooling'])
        check(context['originalProduct']['commit'] != context['currentTooling']['commit'] &&
              context['originalProduct']['tree'] != context['currentTooling']['tree'],
              'original product and current tooling must remain distinct')
        evidence!(context['originalReceipt'])
        evidence!(context['currentReceipt'])
        check(context['originalReceipt']['path'] != context['currentReceipt']['path'] &&
              context['originalReceipt']['sha256'] != context['currentReceipt']['sha256'],
              'original and current receipt evidence must remain distinct')
        object!(context['app'], %w[path treeSHA256])
        text!(context['app']['path'])
        digest!(context['app']['treeSHA256'], 64)
        digest!(context['identitySHA1'], 40, uppercase: true)
        delta!(context['gitDelta'])
        failed_build!(context['failedBuild'], app: context['app'], identity: context['identitySHA1'])
        paths = [context['originalReceipt']['path'], context['currentReceipt']['path'], context['app']['path']] +
                context['failedBuild']['logs'].map { |log| log['path'] } +
                [context['failedBuild']['failureLog']['path'], context['failedBuild']['observerAttestation']['path']]
        check(paths.uniq == paths, 'distinct evidence roles reuse one path')
      end

      def delta!(entries)
        check(entries.is_a?(Array) && !entries.empty? && entries.length <= 64,
              'reviewed delta is not bounded nonempty entries')
        entries.each do |entry|
          object!(entry, DELTA_KEYS)
          path = entry['path']
          text!(path)
          check(path.ascii_only? && /\A[A-Za-z0-9._\/-]+\z/.match?(path) &&
                !path.start_with?('/') &&
                path.split('/', -1).none? { |part| part.empty? || %w[. ..].include?(part) },
                'delta path text is not a unique relative Git name')
          %w[original current].each do |side|
            mode = entry[side + 'Mode']
            blob = entry[side + 'BlobSHA1']
            check(mode.instance_of?(Integer) && [0, 100644, 100755].include?(mode),
                  'delta mode is not a native regular-file mode')
            if mode == 0
              check(blob == '0' * 40, 'absent Git side must use exact zero OID')
            else
              digest!(blob, 40)
            end
          end
          check(entry['originalMode'] != entry['currentMode'] ||
                entry['originalBlobSHA1'] != entry['currentBlobSHA1'], 'delta entry has no change')
          check(entry['originalMode'] != 0 || entry['currentMode'] != 0, 'delta has two absent sides')
        end
        paths = entries.map { |entry| entry['path'] }
        check(paths == paths.sort && paths.uniq == paths, 'delta paths must be sorted and duplicate-free')
      end

      def failed_build!(value, app:, identity:)
        object!(value, FAILED_KEYS)
        digest!(value['builderScriptSHA256'], 64)
        check(value['originalFinalChecksCompleted'].equal?(false) &&
              value['successfulBuildReport'].equal?(false) &&
              value['stage'] == 'artifact-verification', 'unobserved build success/final checks must not be asserted')
        argv = value['argv']
        check(argv.is_a?(Array) && argv.length == 8, 'official outer invocation shape differs')
        argv.each { |argument| text!(argument) }
        check(argv[0] == '/usr/bin/ruby' &&
              (argv[1] == BUILDER || (argv[1].start_with?('/') && argv[1].end_with?('/' + BUILDER))) &&
              [argv[2], argv[4], argv[6]] == %w[--output --scratch --identity] &&
              argv[7] == identity, 'official builder arguments differ')
        check(!argv[3].end_with?('/') && app['path'] == argv[3] + '/Beluga Host.app',
              'app locator differs from observed builder output')
        environment = value['environment']
        object!(environment, ENVIRONMENT_KEYS)
        environment.values.each { |item| text!(item) }
        check(environment['LC_ALL'] == 'C' && environment['MACOSX_DEPLOYMENT_TARGET'] == '14.0' &&
              environment['SWIFT_TREAT_WARNINGS_AS_ERRORS'] == 'YES' &&
              environment['TMPDIR'] == argv[5] &&
              environment['PATH'] == environment['DEVELOPER_DIR'] +
                '/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin',
              'pinned scrubbed Swift-child environment differs')
        logs = value['logs']
        check(logs.is_a?(Array) && logs.length == 3, 'exact three product logs required')
        logs.each_with_index do |log, index|
          object!(log, %w[path product sha256])
          check(log['product'] == PRODUCTS[index] &&
                log['path'] == argv[3] + '/' + PRODUCTS[index] + '-build.log', 'fixed product/log locator differs')
          digest!(log['sha256'], 64)
        end
        evidence!(value['failureLog'])
        evidence!(value['observerAttestation'])
      end

      def copy(value, depth = 0, budget = [0])
        budget[0] += 1
        check(depth <= 8 && budget[0] <= 2048, 'collected data exceeds fixed model bounds')
        case value
        when Hash
          check(value.size <= 32 && value.keys.all? { |key| key.is_a?(String) }, 'collected object exceeds fixed model')
          value.to_h { |key, item| [copy(key, depth + 1, budget), copy(item, depth + 1, budget)] }.freeze
        when Array
          check(value.length <= 64, 'collected array exceeds fixed model')
          value.map { |item| copy(item, depth + 1, budget) }.freeze
        when String
          text = value.dup.force_encoding(Encoding::UTF_8)
          text!(text)
          text.freeze
        when Integer, TrueClass, FalseClass, NilClass then value
        else raise Refusal, 'unsupported collected data type'
        end
      end
    end

    private_class_method :new
  end
end
