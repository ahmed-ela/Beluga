# frozen_string_literal: true

# Offline inputs only. This does not alter Pins or expose a production cutover endpoint.
require_relative "opensteamer-host-v91-cutover-controller"

module OpenSteamerHostSuccessorInputs
  Legacy = OpenSteamerV91Cutover
  Failure = Legacy::Failure
  Util = Legacy::Util

  module Checks
    module_function

    def shape!(object, keys, label)
      Util.fail!("#{label} fields differ") unless object.is_a?(Hash) && object.keys.sort == keys.sort
    end

    def text!(value, label)
      Util.fail!("#{label} is malformed") unless value.is_a?(String) &&
        !value.empty? && !value.match?(/[\x00-\x1f\x7f]/)
    end

    def hash!(value, length, label)
      Util.fail!("#{label} is malformed") unless value.is_a?(String) &&
        value.match?(/\A[0-9a-f]{#{length}}\z/)
    end

    def absolute!(path, label)
      text!(path, label)
      Util.fail!("#{label} is not a normalized absolute path") unless
        path.start_with?("/") && File.expand_path(path) == path && !path.end_with?("/")
    end

    # Admission precedes reads/copies/creation. A lexical denylist is insufficient on
    # case-insensitive APFS and through firmlinks. Only the reviewed artifact volume
    # is admitted, and every existing ancestor is checked without following aliases.
    def artifact_path!(path, label)
      absolute!(path, label)
      Util.fail!("#{label} must be below the approved artifact root, outside installed/runtime roots") unless
        path.start_with?("/Volumes/t7/")
      protected_ids = ["/Applications", Legacy::Pins::RUNTIME_ROOT].each_with_object([]) do |root, ids|
        next unless File.exist?(root)
        stat = File.stat(root)
        ids << [stat.dev, stat.ino]
      end
      ancestor = path
      loop do
        if File.exist?(ancestor) || File.symlink?(ancestor)
          stat = File.lstat(ancestor)
          Util.fail!("#{label} traverses an alias") if stat.symlink? || File.realpath(ancestor) != ancestor
          Util.fail!("#{label} aliases an installed/runtime root") if protected_ids.include?([stat.dev, stat.ino])
        end
        break if ancestor == "/Volumes/t7"
        ancestor = File.dirname(ancestor)
      end
      path
    end

    def descriptor!(value, label)
      return if value.nil?
      shape!(value, %w[path sha256], label)
      artifact_path!(value.fetch("path"), "#{label} path")
      hash!(value.fetch("sha256"), 64, "#{label} SHA-256")
    end

    def file!(descriptor, label, mode: nil)
      Util.fail!("#{label} is missing; an independently sourced record is required") unless descriptor
      path = descriptor.fetch("path")
      artifact_path!(path, label)
      Util.fail!("#{label} traverses an alias") unless File.realpath(path) == path
      Util.exact_file!(path, descriptor.fetch("sha256"), label, mode: mode, owner: Process.euid)
      path
    rescue Errno::ENOENT
      Util.fail!("#{label} file is missing")
    end

    def freeze_tree(value)
      case value
      when Hash then value.each { |key, child| key.freeze; freeze_tree(child) }
      when Array then value.each { |child| freeze_tree(child) }
      end
      value.freeze
    end
  end

  class Profile
    SCHEMA = "opensteamer.host-successor-input-profile.v1"
    attr_reader :data, :sha256

    def initialize(path, expected_sha256:)
      Checks.artifact_path!(path, "profile path")
      Checks.hash!(expected_sha256, 64, "profile approval digest")
      bytes = File.binread(path, 65_537)
      Util.fail!("profile exceeds 64 KiB") if bytes.bytesize > 65_536
      @sha256 = Digest::SHA256.hexdigest(bytes)
      Util.fail!("profile approval digest differs") unless @sha256 == expected_sha256
      @data = JSON.parse(bytes, object_class: Util::DuplicateRejectingHash)
      validate!
      Checks.freeze_tree(@data)
    rescue JSON::ParserError => error
      Util.fail!("profile is not strict JSON: #{error.message}")
    end

    def missing_evidence
      missing = []
      %w[copyManifest buildEvidence].each do |key|
        missing << "candidate.#{key}" unless @data.fetch("candidate")[key]
      end
      %w[receipt copyManifest].each do |key|
        missing << "predecessor.#{key}" unless @data.fetch("predecessor")[key]
      end
      %w[bundleVerifier reference].each { |key| missing << key unless @data[key] }
      missing.freeze
    end

    def require_deployment_binding!
      missing = missing_evidence
      Util.fail!("missing independent evidence: #{missing.join(', ')}") unless missing.empty?
      # A hash-pinned file is not proof of a successful previous deployment. No adapter for
      # the current predecessor's original receipt schema has been independently reviewed.
      Util.fail!("successor execution is not implemented; predecessor receipt and generation adapter require review")
    end

    private

    def validate!
      Checks.shape!(@data, %w[schema namespace source candidate predecessor bundleVerifier reference], "profile")
      Util.fail!("profile schema differs") unless @data.fetch("schema") == SCHEMA
      namespace = @data.fetch("namespace")
      Util.fail!("namespace must be a fresh successor label") unless namespace.is_a?(String) &&
        namespace.match?(/\Ahost-[a-z0-9]+(?:-[a-z0-9]+)*\z/) && namespace.bytesize <= 80
      source = @data.fetch("source")
      Checks.shape!(source, %w[commit tree branch upstream], "source")
      %w[commit tree].each { |key| Checks.hash!(source[key], 40, "source #{key}") }
      %w[branch upstream].each { |key| Checks.text!(source[key], "source #{key}") }
      Util.fail!("source upstream differs") unless source["upstream"] == "origin/#{source['branch']}"
      candidate = @data.fetch("candidate")
      Checks.shape!(candidate, %w[appPath executableSHA256 copyManifest buildEvidence], "candidate")
      Checks.artifact_path!(candidate["appPath"], "candidate app")
      path = candidate.fetch("appPath")
      Util.fail!("prebuilt import must not read an installed/runtime app") if
        path.start_with?("/Applications/", "#{Legacy::Pins::RUNTIME_ROOT}/")
      Util.fail!("candidate basename differs") unless File.basename(path) == "Beluga Host.app"
      Checks.hash!(candidate["executableSHA256"], 64, "candidate executable")
      %w[copyManifest buildEvidence].each { |key| Checks.descriptor!(candidate[key], "candidate #{key}") }
      predecessor = @data.fetch("predecessor")
      Checks.shape!(predecessor, %w[executableSHA256 receipt copyManifest], "predecessor")
      Checks.hash!(predecessor["executableSHA256"], 64, "predecessor executable")
      Util.fail!("candidate equals predecessor") if predecessor["executableSHA256"] == candidate["executableSHA256"]
      %w[receipt copyManifest].each { |key| Checks.descriptor!(predecessor[key], "predecessor #{key}") }
      %w[bundleVerifier reference].each { |key| Checks.descriptor!(@data[key], key) }
    end
  end

  # Outputs reviewed invocation data, not a running process or a replacement for the verifier.
  class VerifierAdapter
    def self.arguments(profile)
      data = profile.data
      verifier = Checks.file!(data["bundleVerifier"], "bundle verifier", mode: 0o755)
      reference = Checks.file!(data["reference"], "designated requirement reference", mode: 0o755)
      Util.fail!("reference differs from approved compatibility reference") unless
        data.fetch("reference").fetch("sha256") == Legacy::Pins::APPROVED_PREDECESSOR_REFERENCE_SHA256
      [verifier, "--media-integration-v1", data.fetch("candidate").fetch("appPath"),
       Legacy::Pins::TEAM_ID, reference].freeze
    end
  end

  # Validate existing prebuilt evidence without rebuilding, copying, signing, or launching code.
  # The returned plan is NOT deployment authorization; the production entrypoint remains absent.
  class PrebuiltImport
    def initialize(profile)
      @profile = profile
    end

    def verify!(source_repository:)
      candidate = @profile.data.fetch("candidate")
      Checks.artifact_path!(candidate.fetch("appPath"), "candidate app")
      @profile.verify_candidate_evidence! if @profile.respond_to?(:verify_candidate_evidence!)
      manifest = Checks.file!(candidate["copyManifest"], "candidate copy manifest")
      build_evidence = Checks.file!(candidate["buildEvidence"], "candidate build evidence")
      source = @profile.data.fetch("source")
      tree = Util.capture!("/usr/bin/git", "-C", source_repository, "rev-parse", "#{source.fetch('commit')}^{tree}").strip
      Util.fail!("source commit/tree binding differs") unless tree == source.fetch("tree")
      app = candidate.fetch("appPath")
      Util.fail!("candidate app traverses an alias") unless File.realpath(app) == app
      before = File.lstat(app)
      Legacy::CopyManifest.new(app).verify!(manifest)
      Util.exact_file!(File.join(app, "Contents/MacOS/CaptureServer"), candidate.fetch("executableSHA256"),
                       "prebuilt candidate executable", mode: 0o755, owner: Process.euid)
      Checks.file!(candidate["copyManifest"], "candidate copy manifest")
      Checks.file!(candidate["buildEvidence"], "candidate build evidence")
      after = File.lstat(app)
      Util.fail!("candidate root identity changed") unless [before.dev, before.ino] == [after.dev, after.ino]
      Checks.freeze_tree({
        "profileSHA256" => @profile.sha256,
        "sourceCommit" => source.fetch("commit"), "sourceTree" => tree,
        "candidateApp" => app, "copyManifest" => manifest, "buildEvidence" => build_evidence,
        "status" => "ARTIFACT_INPUTS_ONLY_NOT_DEPLOYMENT_READY"
      })
    rescue Errno::ENOENT
      Util.fail!("candidate app is missing")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  warn "This is an offline input library, not a preflight or execution command."
  exit 64
end
