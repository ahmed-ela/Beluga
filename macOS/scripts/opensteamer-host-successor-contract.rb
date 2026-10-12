# frozen_string_literal: true
require_relative "opensteamer-host-successor-inputs"

module OpenSteamerHostSuccessor
  Legacy = OpenSteamerV91Cutover
  Checks = OpenSteamerHostSuccessorInputs::Checks
  Util = Legacy::Util

  class ReleaseContract
    PROFILE_SCHEMA = "opensteamer.reviewed-host-successor-profile.v1"
    BASELINE_SCHEMA = "opensteamer.independently-reviewed-current-host-baseline.v1"
    BUILD_SCHEMA = "opensteamer.independently-reviewed-prebuilt-host.v1"
    MODE = "independently-reviewed-current-baseline"
    PREDECESSOR_VERIFIERS = {
      "macOS/scripts/verify-beluga-host-bundle.sh" => "e8a486a8e7360e5d3c8517e237e046fc21b3ccc2a3eb5e14ccd5d40135742e0c",
      "macOS/scripts/verify-opensteamer-media-v1-predecessor.sh" => "8975832e9db849d62b57a2ef25c604afd4e63a8dedd238d62536c01edbe27f20"
    }.freeze
    STATE_NAMES = {
      "V90_STOPPED" => "PREDECESSOR_STOPPED", "V90_HELD" => "PREDECESSOR_HELD",
      "V91_PUBLISHED" => "CANDIDATE_PUBLISHED", "V91_BOOTSTRAPPED" => "CANDIDATE_BOOTSTRAPPED",
      "V91_COMMIT_IRREVERSIBLE" => "CANDIDATE_COMMIT_IRREVERSIBLE", "COMMITTED_V91" => "COMMITTED_CANDIDATE",
      "COMMITTED_V91_UNVERIFIED" => "COMMITTED_CANDIDATE_UNVERIFIED",
      "V91_STOPPED" => "CANDIDATE_STOPPED", "FAILED_V91_ARCHIVED" => "FAILED_CANDIDATE_ARCHIVED",
      "V90_RESTORED" => "PREDECESSOR_RESTORED", "V90_BOOTSTRAPPED" => "PREDECESSOR_BOOTSTRAPPED",
      "ROLLED_BACK_EXACT_V90" => "ROLLED_BACK_EXACT_PREDECESSOR"
    }.freeze
    TOOL_FILES = Legacy::Pins::TOOLING_FILES.merge(
      "macOS/scripts/opensteamer-host-successor-inputs.rb" => 0o644,
      "macOS/scripts/opensteamer-host-successor-contract.rb" => 0o644,
      "macOS/scripts/import-prebuilt-host-successor.rb" => 0o644,
      "macOS/scripts/verify-beluga-host-bundle.sh" => 0o755,
      "macOS/scripts/verify-opensteamer-media-v1-predecessor.sh" => 0o755
    ).freeze
    attr_reader :profile, :baseline, :build_attestation, :pins, :namespace, :profile_sha, :profile_path
    alias data profile
    alias sha256 profile_sha

    def initialize(path, expected_sha)
      Checks.artifact_path!(path, "profile path")
      Checks.hash!(expected_sha, 64, "profile approval digest")
      @profile_path = path.dup.freeze
      @profile_sha = expected_sha.dup.freeze
      @profile = read_record!({ "path" => path, "sha256" => expected_sha }, "successor profile")
      Checks.shape!(@profile, %w[schema namespace source candidate baseline reference launchSnapshot], "successor profile")
      Util.fail!("successor profile schema differs") unless @profile["schema"] == PROFILE_SCHEMA
      @namespace = @profile.fetch("namespace")
      Util.fail!("successor namespace is malformed") unless @namespace.is_a?(String) &&
        @namespace.match?(/\Ahost-[a-z0-9]+(?:-[a-z0-9]+)*\z/) && @namespace.bytesize <= 64
      source = @profile.fetch("source")
      Checks.shape!(source, %w[commit tree branch upstream], "source")
      %w[commit tree].each { |key| Checks.hash!(source[key], 40, "source #{key}") }
      %w[branch upstream].each { |key| Checks.text!(source[key], "source #{key}") }
      Util.fail!("source upstream differs") unless source["upstream"] == "origin/#{source['branch']}"
      candidate = @profile.fetch("candidate")
      Checks.shape!(candidate, %w[appPath executableSHA256 frameworkSHA256 infoPlistSHA256 executableCDHash frameworkCDHash copyManifest buildEvidence], "candidate")
      Checks.artifact_path!(candidate["appPath"], "candidate app")
      Util.fail!("candidate must be a private prebuilt Beluga app") unless
        File.basename(candidate["appPath"]) == "Beluga Host.app" &&
        !candidate["appPath"].start_with?("/Applications/", Legacy::Pins::RUNTIME_ROOT + "/")
      %w[executableSHA256 frameworkSHA256 infoPlistSHA256].each { |key| Checks.hash!(candidate[key], 64, key) }
      %w[executableCDHash frameworkCDHash].each { |key| Checks.hash!(candidate[key], 40, key) }
      %w[copyManifest buildEvidence].each { |key| require_descriptor!(candidate[key], "candidate #{key}") }
      %w[baseline reference launchSnapshot].each { |key| require_descriptor!(@profile[key], key) }
      Util.fail!("compatibility reference differs") unless
        @profile["reference"]["sha256"] == Legacy::Pins::APPROVED_PREDECESSOR_REFERENCE_SHA256
      Util.fail!("launch contract differs") unless
        @profile["launchSnapshot"]["sha256"] == Legacy::Pins::LAUNCH_AGENT_SHA256
      @baseline = read_record!(@profile.fetch("baseline"), "reviewed current baseline")
      validate_baseline!
      Util.fail!("candidate equals predecessor") if candidate["executableSHA256"] == @baseline["executableSHA256"]
      @build_attestation = read_record!(candidate.fetch("buildEvidence"), "reviewed candidate build attestation")
      validate_build_attestation!
      @pins = build_pins
      Checks.freeze_tree(@profile)
      Checks.freeze_tree(@baseline)
      Checks.freeze_tree(@build_attestation)
      Checks.freeze_tree(@pins)
      freeze
    end

    def verify_candidate_evidence!
      Checks.file!(@profile.fetch("candidate").fetch("buildEvidence"), "reviewed candidate build attestation", mode: 0o600)
      Checks.file!(@build_attestation.fetch("buildLog"), "reviewed candidate build log", mode: 0o600)
      true
    end

    def verify_baseline_evidence!
      Checks.file!({ "path" => @profile_path, "sha256" => @profile_sha }, "successor profile", mode: 0o600)
      Checks.file!(@profile.fetch("baseline"), "reviewed current baseline", mode: 0o600)
      Checks.file!(@baseline.fetch("copyManifest"), "reviewed predecessor copy manifest", mode: 0o600)
      Checks.file!(@baseline.fetch("bundleVerifier"), "reviewed predecessor verifier", mode: 0o755)
      Util.directory!(@baseline.fetch("observerDirectory"), "reviewed predecessor observer directory", mode: 0o700, owner: Process.euid)
      Legacy::Pins::V90_HELPERS.each do |name, digest|
        Util.exact_file!(File.join(@baseline.fetch("observerDirectory"), name), digest,
                         "trusted predecessor observer #{name}", mode: 0o500, owner: Process.euid)
      end
      true
    end

    def validate_payload_binding!(payload, identity: nil)
      candidate = @profile.fetch("candidate")
      {
        "successorProfileSHA256" => @profile_sha,
        "artifactBuildEvidenceSHA256" => candidate.fetch("buildEvidence").fetch("sha256"),
        "artifactBuildLogSHA256" => @build_attestation.fetch("buildLog").fetch("sha256"),
        "candidateExecutableSHA256" => candidate.fetch("executableSHA256"),
        "candidateMediaFrameworkExecutableSHA256" => candidate.fetch("frameworkSHA256"),
        "candidateInfoPlistSHA256" => candidate.fetch("infoPlistSHA256"),
        "candidateAppCopyManifestSHA256" => candidate.fetch("copyManifest").fetch("sha256")
      }.each do |key, value|
        Util.fail!("sealed artifact differs from approved successor profile: #{key}") unless payload[key] == value
      end
      if identity
        Util.fail!("sealed code identity differs from approved successor profile") unless
          identity["executableCDHash"] == candidate.fetch("executableCDHash") &&
          identity["mediaFrameworkExecutableCDHash"] == candidate.fetch("frameworkCDHash")
      end
      true
    end

    def state_out(state)
      STATE_NAMES.fetch(state, state)
    end

    def state_in(state)
      Util.fail!("successor journal contains a legacy generation label") if STATE_NAMES.key?(state)
      STATE_NAMES.key(state) || state
    end

    def record_out(text)
      map_record(text, true)
    end

    def record_in(text)
      map_record(text, false)
    end

    private

    # This explicit review attestation is not manufactured by the importer. Its
    # approved digest binds the review; the underlying build log stays separately
    # retained. Neither an opaque log nor later sealing-tool provenance establishes
    # which source produced already-built bytes.
    def validate_build_attestation!
      Checks.shape!(@build_attestation, %w[schema review sourceCommit sourceTree executableSHA256 frameworkSHA256 infoPlistSHA256 executableCDHash frameworkCDHash copyManifestSHA256 buildLog], "reviewed candidate build attestation")
      Util.fail!("candidate build attestation lacks independent source-build review") unless
        @build_attestation["schema"] == BUILD_SCHEMA &&
        @build_attestation["review"] == "independently-reviewed-source-build"
      candidate = @profile.fetch("candidate")
      expected = { "sourceCommit" => @profile.fetch("source").fetch("commit"),
                   "sourceTree" => @profile.fetch("source").fetch("tree"),
                   "copyManifestSHA256" => candidate.fetch("copyManifest").fetch("sha256") }
      %w[executableSHA256 frameworkSHA256 infoPlistSHA256 executableCDHash frameworkCDHash].each do |key|
        expected[key] = candidate.fetch(key)
      end
      expected.each do |key, value|
        Util.fail!("candidate build attestation differs from approved source/artifact: #{key}") unless @build_attestation[key] == value
      end
      require_descriptor!(@build_attestation["buildLog"], "reviewed candidate build log")
      verify_candidate_evidence!
    end

    def require_descriptor!(value, label)
      Util.fail!("#{label} is missing") unless value
      Checks.descriptor!(value, label)
    end

    def read_record!(descriptor, label)
      path = Checks.file!(descriptor, label, mode: 0o600)
      bytes = File.binread(path, 65_537)
      Util.fail!("#{label} exceeds 64 KiB") if bytes.bytesize > 65_536
      Util.fail!("#{label} changed while reading") unless Digest::SHA256.hexdigest(bytes) == descriptor.fetch("sha256")
      JSON.parse(bytes, object_class: Util::DuplicateRejectingHash)
    rescue JSON::ParserError => error
      Util.fail!("#{label} is malformed JSON: #{error.message}")
    end

    def validate_baseline!
      Checks.shape!(@baseline, %w[schema mode sourceBuildProvenance executableSHA256 frameworkSHA256 infoPlistSHA256 executableCDHash designatedRequirement launchPlistSHA256 copyManifest bundleVerifier observerDirectory], "baseline")
      Util.fail!("baseline is not independently reviewed current signed bytes") unless
        @baseline["schema"] == BASELINE_SCHEMA && @baseline["mode"] == MODE &&
        @baseline["sourceBuildProvenance"] == "unestablished"
      %w[executableSHA256 frameworkSHA256 infoPlistSHA256 launchPlistSHA256].each do |key|
        Checks.hash!(@baseline[key], 64, "baseline #{key}")
      end
      Checks.hash!(@baseline["executableCDHash"], 40, "baseline CDHash")
      Util.fail!("baseline changed the preserved signing requirement") unless
        @baseline["designatedRequirement"] == Legacy::Pins::APPROVED_PREDECESSOR_REFERENCE_DESIGNATED_REQUIREMENT
      Util.fail!("baseline changed the preserved launch contract") unless
        @baseline["launchPlistSHA256"] == Legacy::Pins::LAUNCH_AGENT_SHA256
      %w[copyManifest bundleVerifier].each { |key| require_descriptor!(@baseline[key], "baseline #{key}") }
      verifier = @baseline.fetch("bundleVerifier")
      Util.fail!("baseline verifier must match an exact reviewed tracked predecessor verifier") unless
        PREDECESSOR_VERIFIERS.any? do |relative, digest|
          verifier["path"] == File.join(Legacy::Pins::TOOLING_ROOT, relative) && verifier["sha256"] == digest
        end
      Checks.absolute!(@baseline["observerDirectory"], "baseline observer directory")
      Util.fail!("baseline observer directory differs from immutable trusted observer evidence") unless
        @baseline["observerDirectory"] == Legacy::Pins::OBSERVER_EVIDENCE
    end

    def build_pins
      source = @profile.fetch("source")
      runtime = Legacy::Pins::RUNTIME_ROOT
      {
        SOURCE_BRANCH: source.fetch("branch"), SOURCE_UPSTREAM: source.fetch("upstream"),
        SOURCE_COMMIT: source.fetch("commit"), SOURCE_TREE: source.fetch("tree"), TOOLING_FILES: TOOL_FILES,
        V90_CDHASH: @baseline.fetch("executableCDHash"),
        V90_DESIGNATED_REQUIREMENT: @baseline.fetch("designatedRequirement"),
        V90_EXECUTABLE_SHA256: @baseline.fetch("executableSHA256"),
        V90_FRAMEWORK_SHA256: @baseline.fetch("frameworkSHA256"),
        V90_INFO_PLIST_SHA256: @baseline.fetch("infoPlistSHA256"),
        V90_APP_MANIFEST_SHA256: @baseline.fetch("copyManifest").fetch("sha256"),
        V90_BUNDLE_VERIFIER_SOURCE: @baseline.fetch("bundleVerifier").fetch("path"),
        V90_BUNDLE_VERIFIER_SHA256: @baseline.fetch("bundleVerifier").fetch("sha256"),
        V90_COMMITTED_COPY_MANIFEST: @baseline.fetch("copyManifest").fetch("path"),
        OBSERVER_EVIDENCE: @baseline.fetch("observerDirectory"), V90_HELPERS: Legacy::Pins::V90_HELPERS,
        V91_UPDATE_ROOT: "#{runtime}/paired-host-updates-#{@namespace}",
        V91_PENDING_POINTER: "#{runtime}/pending-paired-host-update-#{@namespace}",
        V91_ACTIVE_POINTER: "#{runtime}/active-paired-host-update-#{@namespace}",
        V91_LOCK: "#{runtime}/paired-host-update-#{@namespace}.lock",
        V91_JOURNAL_HEADER: "OPENSTEAMER_PAIRED_HOST_UPDATE_SUCCESSOR_#{@profile_sha}",
        PAYLOAD_SCHEMA: "opensteamer.prebuilt-host-successor-payload.v1",
        PAYLOAD_KEYS: Legacy::Pins::PAYLOAD_KEYS + %w[successorProfileSHA256 artifactBuildEvidenceSHA256 artifactBuildLogSHA256]
      }
    end

    def map_record(text, outgoing)
      text.lines.map do |line|
        key, value = line.chomp.split("=", 2)
        next line unless value
        translated = case key
        when "terminal_required", "point_of_no_return"
          value.split(",", -1).map { |state| outgoing ? state_out(state) : state_in(state) }.join(",")
        when "target"
          mapping = { "v91" => "candidate", "exact-v90" => "exact-predecessor" }
          if outgoing
            mapping.fetch(value, value)
          else
            Util.fail!("successor proof contains legacy target") if mapping.key?(value)
            mapping.key(value) || value
          end
        else value
        end
        "#{key}=#{translated}#{line.end_with?("\n") ? "\n" : ""}"
      end.join
    end
  end
end
