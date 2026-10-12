# frozen_string_literal: true

require 'base64'
require 'digest'
require 'json'

# Public-data parsing only. AdmittedUpdateTrial supplies filesystem, source,
# receipt and toolchain authority before a slot reaches artifact production.
require_relative 'build-beluga-mac-client-contract'

module BelugaMacClient

  class UpdateTrialProfile
    MAXIMUM_MANIFEST_BYTES = 16 * 1024
    CONFIG_KEYS = %w[schema version build minimumSystemVersion bundleIdentifier teamIdentifier sparkleVersion repository feedURL publicEDKey].sort.each(&:freeze).freeze
    PROFILE_KEYS = %w[schema purpose productionPromotionAllowed trialID source sourceReleaseSHA256 microphoneReceiptSHA256 testedToolchain namespaceURL appcastURL payloadBaseURL publicEDKey slots].sort.each(&:freeze).freeze
    SOURCE_KEYS = %w[commit tree].each(&:freeze).freeze
    SLOT_KEYS = %w[build version].each(&:freeze).freeze
    TOOLCHAIN_KEYS = %w[developer_directory tools].each(&:freeze).freeze
    BUNDLE_ID = 'com.elamin.AudioStreamer.CaptureServer'.freeze
    BROKER_ID = 'com.elamin.beluga.Updater'.freeze
    TEAM = 'MSMG8CJLB3'.freeze
    STABLE_FEED = 'https://github.com/ahmed-ela/Beluga/releases/download/mac-update-stable/appcast.xml'.freeze
    PRODUCTION_PAYLOAD_NAMESPACE = 'https://github.com/ahmed-ela/Beluga/releases/download/'.freeze
    CONTRACT = {
      'bundleIdentifier' => BUNDLE_ID, 'brokerBundleIdentifier' => BROKER_ID,
      'teamIdentifier' => TEAM, 'minimumSystemVersion' => '14.0',
      'architecture' => 'arm64', 'sparkleVersion' => '2.10.0',
      'updaterOwnershipProtocolVersion' => 1, 'pairedPhoneCatalogVersion' => 1,
      'candidateIdentitySchema' => 'beluga.update-candidate.v2',
      'bundleTreeAlgorithm' => 'beluga.bundle-tree-json-v1'
    }.each { |key, value| key.freeze; value.freeze }.freeze

    class UniqueObject < Hash
      def []=(key, value)
        raise Refusal, 'duplicate JSON field' if key?(key)
        super
      end
    end

    attr_reader :manifest_sha256, :trial_id, :namespace_url, :appcast_url,
                :payload_base_url, :public_ed_key, :source, :tested_toolchain,
                :source_release_sha256, :receipt_sha256

    def self.parse(bytes, expected_manifest_sha256:, production_config:,
                   trusted_source:, source_release_sha256:, receipt_sha256:,
                   tested_toolchain:, approved_namespace:, approved_public_key:)
      check(bytes.is_a?(String) && !bytes.empty? && bytes.bytesize <= MAXIMUM_MANIFEST_BYTES,
            'manifest byte bound differs')
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      check(text.valid_encoding?, 'manifest is not UTF-8')
      digest!(expected_manifest_sha256)
      actual_digest = Digest::SHA256.hexdigest(bytes)
      check(actual_digest == expected_manifest_sha256, 'manifest digest differs')
      value = JSON.parse(text, object_class: UniqueObject, max_nesting: 8, allow_nan: false)
      object!(value, PROFILE_KEYS)
      check(value['schema'] == 'beluga.update-trial-profile.v1' &&
            value['purpose'] == 'native-update-validation' &&
            value['productionPromotionAllowed'].equal?(false), 'profile purpose differs')

      production = copy(production_config)
      production_config!(production)
      trusted = copy(trusted_source)
      source!(trusted)
      source!(value['source'])
      check(value['source'] == trusted, 'source binding differs')
      digest!(source_release_sha256)
      digest!(receipt_sha256)
      digest!(value['sourceReleaseSHA256'])
      digest!(value['microphoneReceiptSHA256'])
      check(value['sourceReleaseSHA256'] == source_release_sha256 &&
            value['microphoneReceiptSHA256'] == receipt_sha256, 'receipt/config binding differs')
      tools = copy(tested_toolchain)
      toolchain!(tools)
      toolchain!(value['testedToolchain'])
      check(value['testedToolchain'] == tools, 'tested toolchain binding differs')

      trial_id = value['trialID']
      check(trial_id.is_a?(String) &&
            /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.match?(trial_id) &&
            trial_id.delete('-') != '0' * 32, 'trial UUID is not canonical')
      approved = copy(approved_namespace)
      namespace = url!(approved, directory: true)
      check(namespace.fetch(:path).split('/').include?(trial_id), 'namespace lacks exact trial UUID')
      check(value['namespaceURL'] == approved, 'approved namespace differs')
      check(value['appcastURL'] == approved + 'appcast.xml' &&
            value['payloadBaseURL'] == approved + 'payloads/', 'derived trial destinations differ')
      url!(value['appcastURL'], directory: false)
      url!(value['payloadBaseURL'], directory: true)
      [STABLE_FEED, PRODUCTION_PAYLOAD_NAMESPACE].each do |production_url|
        other = url!(production_url, directory: production_url.end_with?('/'))
        check(!overlap?(namespace, other), 'trial overlaps production destination')
      end
      approved_key = copy(approved_public_key)
      public_key!(approved_key)
      public_key!(value['publicEDKey'])
      check(value['publicEDKey'] == approved_key &&
            approved_key != production['publicEDKey'], 'approved independent public key differs')

      object!(value['slots'], %w[new old])
      old_slot = slot!(value['slots']['old'])
      new_slot = slot!(value['slots']['new'])
      check(new_slot['build'] > old_slot['build'], 'trial builds must strictly increase')
      check((version_parts(new_slot['version']) <=> version_parts(old_slot['version'])) >= 0,
            'trial version rolls back')
      new(value, production: production, manifest_sha256: actual_digest)
    rescue JSON::ParserError, JSON::NestingError
      raise Refusal, 'invalid bounded JSON manifest'
    end

    def config(slot)
      @configs.fetch(valid_slot!(slot))
    end

    def config_sha256(slot)
      @config_digests.fetch(valid_slot!(slot))
    end

    def build_source(slot)
      @build_sources.fetch(valid_slot!(slot))
    end

    def payload_name(slot)
      @payload_names.fetch(valid_slot!(slot))
    end

    def payload_url(slot)
      @payload_urls.fetch(valid_slot!(slot))
    end

    def production_promotion_allowed?
      false
    end

    def published?
      false
    end

    def inspect
      '#<BelugaMacClient::UpdateTrialProfile data-only>'
    end
    alias to_s inspect

    def self.canonical_json(value)
      JSON.generate(sort_keys(value))
    end

    private

    def initialize(value, production:, manifest_sha256:)
      @manifest_sha256 = self.class.copy(manifest_sha256)
      @trial_id = self.class.copy(value.fetch('trialID'))
      @namespace_url = self.class.copy(value.fetch('namespaceURL'))
      @appcast_url = self.class.copy(value.fetch('appcastURL'))
      @payload_base_url = self.class.copy(value.fetch('payloadBaseURL'))
      @public_ed_key = self.class.copy(value.fetch('publicEDKey'))
      @source = self.class.copy(value.fetch('source'))
      @tested_toolchain = self.class.copy(value.fetch('testedToolchain'))
      @source_release_sha256 = self.class.copy(value.fetch('sourceReleaseSHA256'))
      @receipt_sha256 = self.class.copy(value.fetch('microphoneReceiptSHA256'))
      @configs, @config_digests, @build_sources, @payload_names, @payload_urls = {}, {}, {}, {}, {}
      %w[old new].each do |slot|
        selected = production.merge(value.fetch('slots').fetch(slot)).merge(
          'feedURL' => @appcast_url, 'publicEDKey' => @public_ed_key
        )
        self.class.object!(selected, CONFIG_KEYS)
        @configs[slot] = self.class.copy(selected)
        @config_digests[slot] = Digest::SHA256.hexdigest(self.class.canonical_json(selected)).freeze
        binding = {
          'schema' => 'beluga.update-trial-binding.v1', 'trialID' => @trial_id,
          'manifestSHA256' => @manifest_sha256, 'slot' => slot,
          'slotConfigSHA256' => @config_digests.fetch(slot),
          'sourceReleaseSHA256' => @source_release_sha256,
          'microphoneReceiptSHA256' => @receipt_sha256
        }
        @build_sources[slot] = self.class.copy(@source.merge('validationBinding' => binding))
        @payload_names[slot] = "Beluga-Mac-#{selected.fetch('version')}-#{selected.fetch('build')}.dmg".freeze
        payload_url = @payload_base_url + @payload_names.fetch(slot)
        self.class.url!(payload_url, directory: false)
        @payload_urls[slot] = payload_url.freeze
      end
      [@configs, @config_digests, @build_sources, @payload_names, @payload_urls].each do |map|
        map.keys.each(&:freeze)
        map.freeze
      end
      freeze
    end

    def valid_slot!(slot)
      self.class.check(slot.is_a?(String) && %w[old new].include?(slot), 'unknown trial slot')
      slot
    end

    class << self
      def check(condition, message)
        raise Refusal, message unless condition
      end

      def object!(value, keys)
        check(value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) } &&
              value.keys.sort == keys, 'JSON object fields differ')
        value
      end

      def digest!(value)
        check(value.is_a?(String) && value.valid_encoding? && value.ascii_only? &&
              /\A[0-9a-f]{64}\z/.match?(value), 'digest is not canonical SHA-256')
      end

      def source!(value)
        object!(value, SOURCE_KEYS)
        check(value.values.all? { |item| item.is_a?(String) && /\A[0-9a-f]{40}\z/.match?(item) && item != '0' * 40 },
              'source identity is not canonical')
      end

      def public_key!(value)
        check(value.is_a?(String) && value.bytesize == 44, 'public key length differs')
        raw = Base64.strict_decode64(value)
        check(raw.bytesize == 32 && raw.bytes.any? { |byte| byte != 0 } &&
              Base64.strict_encode64(raw) == value, 'public key is not canonical nonzero Ed25519')
      rescue ArgumentError
        raise Refusal, 'invalid canonical public key'
      end

      def version_parts(value)
        check(value.is_a?(String) && value.bytesize <= 64 &&
              /\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/.match?(value), 'version is not canonical')
        parts = value.split('.').map(&:to_i)
        check(parts.all? { |part| part <= 2**32 - 1 }, 'version exceeds runtime bounds')
        parts
      end

      def slot!(value)
        object!(value, SLOT_KEYS)
        version_parts(value['version'])
        check(value['build'].instance_of?(Integer) && value['build'] >= 100 &&
              value['build'] <= 2**63 - 1, 'build is not a bounded native integer')
        value
      end

      def production_config!(value)
        object!(value, CONFIG_KEYS)
        slot!('version' => value['version'], 'build' => value['build'])
        expected = {
          'schema' => 'beluga.mac-client-release.v1', 'minimumSystemVersion' => '14.0',
          'bundleIdentifier' => BUNDLE_ID, 'teamIdentifier' => TEAM,
          'sparkleVersion' => '2.10.0', 'repository' => 'ahmed-ela/Beluga', 'feedURL' => STABLE_FEED
        }
        check(expected.all? { |key, item| value[key] == item }, 'production fixed contract differs')
        public_key!(value['publicEDKey'])
      end

      def toolchain!(value)
        object!(value, TOOLCHAIN_KEYS)
        directory = value['developer_directory']
        check(directory.is_a?(String) && directory.bytesize <= 1024 && directory.start_with?('/') &&
              directory.valid_encoding? && !directory.match?(/[\x00-\x1f\x7f\\]/) &&
              directory.split('/', -1).drop(1).none? { |part| part.empty? || %w[. ..].include?(part) },
              'toolchain directory text is not canonical')
        paths = [directory + '/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift',
                 directory + '/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang',
                 directory + '/usr/bin/xcodebuild'].sort
        object!(value['tools'], paths)
        value['tools'].values.each { |digest| digest!(digest) }
      end

      def url!(value, directory:)
        check(value.is_a?(String) && value.bytesize <= 1536 && value.ascii_only?, 'URL text exceeds finite grammar')
        match = /\Ahttps:\/\/([a-z0-9.-]+)(?::443)?(\/[A-Za-z0-9._~\/-]*)\z/.match(value)
        check(match, 'URL is not finite canonical HTTPS')
        host, path = match[1], match[2]
        check(!host.end_with?('.invalid') && !host.end_with?('.example') &&
              host != 'localhost', 'native updater refuses reserved host')
        labels = host.split('.', -1)
        check(host.bytesize <= 253 && labels.length >= 2 && labels.any? { |label| label.match?(/[a-z]/) } &&
              labels.all? { |label| /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/.match?(label) }, 'URL host differs')
        check(path.bytesize <= 1024 && path.end_with?('/') == directory, 'URL path form differs')
        pieces = path.split('/', -1).drop(1)
        pieces.pop if directory
        check(!pieces.empty? && pieces.none? { |piece| piece.empty? || %w[. ..].include?(piece) }, 'URL path components differ')
        { host: host, port: 443, path: path }
      end

      def overlap?(left, right)
        return false unless left[:host] == right[:host] && left[:port] == right[:port]
        a = left[:path].delete_suffix('/')
        b = right[:path].delete_suffix('/')
        a == b || a.start_with?(b + '/') || b.start_with?(a + '/')
      end

      def copy(value, depth = 0)
        check(depth <= 4, 'supplied context nesting exceeds fixed model')
        case value
        when Hash
          check(value.size <= 32 && value.keys.all? { |key| key.is_a?(String) }, 'context object exceeds fixed model')
          value.to_h { |key, item| [copy(key, depth + 1), copy(item, depth + 1)] }.freeze
        when String
          text = value.dup.force_encoding(Encoding::UTF_8)
          check(text.bytesize <= 4096 && text.valid_encoding?, 'supplied context text exceeds fixed model')
          text.freeze
        when Integer, TrueClass, FalseClass, NilClass then value
        else raise Refusal, 'unsupported supplied context type'
        end
      end

      def sort_keys(value)
        value.is_a?(Hash) ? value.keys.sort.to_h { |key| [key, sort_keys(value.fetch(key))] } : value
      end
    end

    private_class_method :new
  end
end
