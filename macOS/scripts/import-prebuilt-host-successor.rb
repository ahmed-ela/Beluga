# frozen_string_literal: true
require_relative "opensteamer-host-successor-contract"

module OpenSteamerHostSuccessor
  class PrebuiltCapsuleImporter
    def initialize(contract)
      @contract = contract
    end

    def import!(root)
      Checks.artifact_path!(root, "fresh prebuilt capsule")
      Util.fail!("prebuilt capsule path was already consumed") if File.exist?(root) || File.symlink?(root)
      parent = File.dirname(root)
      Util.fail!("prebuilt capsule parent is aliased") unless File.realpath(parent) == parent
      input = OpenSteamerHostSuccessorInputs::PrebuiltImport.new(@contract)
      input.verify!(source_repository: Legacy::Pins::TOOLING_ROOT)
      @tooling = Legacy::ToolingProof.verify!
      @root = root
      Checks.artifact_path!(root, "fresh prebuilt capsule")
      Dir.mkdir(root, 0o700)
      %w[candidate deployment source trusted-reference v91-screen-oracle-handoff].each do |name|
        Dir.mkdir(File.join(root, name), 0o700)
      end
      evidence_input = Checks.file!(@contract.profile.fetch("candidate").fetch("buildEvidence"), "reviewed prebuilt build evidence")
      write!(File.join(root, "prebuilt-build-evidence.txt"), File.binread(evidence_input), 0o600)
      log_input = Checks.file!(@contract.build_attestation.fetch("buildLog"), "reviewed prebuilt build log", mode: 0o600)
      write!(File.join(root, "prebuilt-build-log.txt"), File.binread(log_input), 0o600)
      export_source!
      candidate = File.join(root, "candidate/Beluga Host.app")
      FileUtils.cp_r(@contract.profile.fetch("candidate").fetch("appPath"), candidate, preserve: true)
      reference = File.join(root, "trusted-reference/CaptureServer")
      reference_input = Checks.file!(@contract.profile.fetch("reference"), "approved reference", mode: 0o755)
      write!(reference, File.binread(reference_input), 0o755)
      Legacy::PredecessorReferenceFingerprint.verify!(reference)
      launch_input = Checks.file!(@contract.profile.fetch("launchSnapshot"), "unchanged launch snapshot", mode: 0o600)
      write!(File.join(root, "deployment/org.example.opensteamer.worldwide.plist"), File.binread(launch_input), 0o600)
      Legacy::LaunchContract.verify!(File.join(root, "deployment/org.example.opensteamer.worldwide.plist"))
      Legacy::CopyManifest.new(candidate).verify!(@contract.profile.fetch("candidate").fetch("copyManifest").fetch("path"))
      verify_candidate_code!(candidate, reference)
      write_manifests!(candidate)
      payload = make_payload(candidate)
      write_metadata!(payload)
      payload_path = File.join(root, "v91-deployment-payload-manifest.json")
      write_json!(payload_path, payload)
      payload_sha = Util.sha256(payload_path)
      sidecar!(payload_path, payload_sha)
      input.verify!(source_repository: Legacy::Pins::TOOLING_ROOT)
      capsule = Legacy::Capsule.new(root, payload.fetch("handoffSHA256"), payload_sha, tooling: @tooling)
      capsule.verify!
      { "capsule" => root, "profileSHA256" => @contract.profile_sha,
        "handoffSHA256" => payload.fetch("handoffSHA256"), "payloadSHA256" => payload_sha,
        "status" => "SEALED_PREBUILT_ARTIFACT_NOT_DEPLOYED" }
    end

    private

    def export_source!
      source = @contract.profile.fetch("source")
      Tempfile.create(["successor-source-", ".tar"], File.dirname(@root)) do |archive|
        Util.capture!("/usr/bin/git", "-C", Legacy::Pins::TOOLING_ROOT, "archive", "--format=tar",
                      "--output=#{archive.path}", source.fetch("commit"))
        previous_umask = File.umask(0o022)
        begin
          Util.capture!("/usr/bin/tar", "-xf", archive.path, "-C", File.join(@root, "source"))
        ensure
          File.umask(previous_umask)
        end
      end
      File.chmod(0o700, File.join(@root, "source"))
    end

    def verify_candidate_code!(candidate, reference)
      verifier = File.join(@root, "source/macOS/scripts/verify-beluga-host-bundle.sh")
      output, error, status = Open3.capture3(
        { "HOME" => "/Users/ahmed", "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL" => "C",
          "OPENSTEAMER_EXPECTED_ARCHITECTURES" => "arm64" },
        verifier, "--media-integration-v1", candidate, Legacy::Pins::TEAM_ID, reference,
        unsetenv_others: true
      )
      Util.fail!("prebuilt candidate bundle verification failed: #{error.strip}") unless status.success?
      { "Contents/MacOS/CaptureServer" => ["executableCDHash", Legacy::Pins::EXECUTABLE_IDENTIFIER],
        "Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC" =>
          ["frameworkCDHash", Legacy::Pins::FRAMEWORK_IDENTIFIER] }.each do |relative, (key, identifier)|
        stdout, stderr, result = Open3.capture3("/usr/bin/codesign", "--display", "--verbose=4", File.join(candidate, relative))
        Util.fail!("candidate signing identity could not be read") unless result.success?
        identity = Util.exact_code_identity_values(stdout.b + stderr.b)
        Util.fail!("candidate signing identity differs from approved profile") unless
          identity == { identifier: [identifier], team_identifier: [Legacy::Pins::TEAM_ID],
                        cdhash: [@contract.profile.fetch("candidate").fetch(key)] }
      end
      output
    end

    def write_manifests!(candidate)
      source_manifest, = Legacy::TreeManifest.new(File.join(@root, "source"), :source).render
      tree_manifest, = Legacy::TreeManifest.new(candidate, :candidate).render
      copy_manifest, = Legacy::CopyManifest.new(candidate).render
      write!(File.join(@root, "v91-source-export-tree-manifest.txt"), source_manifest, 0o600)
      write!(File.join(@root, "v91-candidate-app-tree-manifest.txt"), tree_manifest, 0o600)
      write!(File.join(@root, "v91-candidate-app-copy-manifest.txt"), copy_manifest, 0o600)
      Util.fail!("imported candidate differs from approved complete copy manifest") unless
        Util.sha256_text(copy_manifest) == @contract.profile.fetch("candidate").fetch("copyManifest").fetch("sha256")
    end

    def make_payload(candidate)
      source = @contract.profile.fetch("source")
      inputs = @contract.profile.fetch("candidate")
      payload = {
        "schema" => Legacy::Pins.fetch(:PAYLOAD_SCHEMA),
        "sourceCommit" => source.fetch("commit"), "sourceTree" => source.fetch("tree"),
        "sourceBranch" => source.fetch("branch"), "sourceUpstream" => source.fetch("upstream"),
        "sourceExportRelativePath" => "source",
        "sourceTreeManifestRelativePath" => "v91-source-export-tree-manifest.txt",
        "candidateAppRelativePath" => "candidate/Beluga Host.app",
        "candidateAppTreeManifestRelativePath" => "v91-candidate-app-tree-manifest.txt",
        "candidateAppCopyManifestRelativePath" => "v91-candidate-app-copy-manifest.txt",
        "candidateExecutableRelativePath" => "candidate/Beluga Host.app/Contents/MacOS/CaptureServer",
        "candidateExecutableSHA256" => inputs.fetch("executableSHA256"),
        "candidateMediaFrameworkExecutableRelativePath" => "candidate/Beluga Host.app/Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC",
        "candidateMediaFrameworkExecutableSHA256" => inputs.fetch("frameworkSHA256"),
        "candidateInfoPlistRelativePath" => "candidate/Beluga Host.app/Contents/Info.plist",
        "candidateInfoPlistSHA256" => inputs.fetch("infoPlistSHA256"),
        "candidateLaunchPlistRelativePath" => "deployment/org.example.opensteamer.worldwide.plist",
        "candidateLaunchPlistSHA256" => Legacy::Pins::LAUNCH_AGENT_SHA256,
        "capsuleMetadataRelativePath" => "trusted-v91-host-oracle-capsule-metadata.json",
        "handoffRelativePath" => "v91-screen-oracle-handoff/v91-screen-oracle-host-identity-handoff.json",
        "hostIdentityManifestRelativePath" => "v91-screen-oracle-handoff/sealed-live-mac-host-identity.json",
        "designatedRequirementReferenceRelativePath" => "trusted-reference/CaptureServer",
        "toolingBranch" => source.fetch("branch"), "toolingUpstream" => source.fetch("upstream"),
        "toolingCommit" => @tooling.fetch(:commit), "toolingTree" => @tooling.fetch(:tree),
        "toolingRemoteURL" => Legacy::Pins::TOOLING_REMOTE_URL,
        "assemblerScriptRelativePath" => "macOS/scripts/import-prebuilt-host-successor.rb",
        "assemblerScriptGitBlob" => @tooling.fetch(:blobs).fetch("macOS/scripts/import-prebuilt-host-successor.rb"),
        "successorProfileSHA256" => @contract.profile_sha,
        "artifactBuildEvidenceSHA256" => inputs.fetch("buildEvidence").fetch("sha256"),
        "artifactBuildLogSHA256" => @contract.build_attestation.fetch("buildLog").fetch("sha256")
      }
      {
        "SHA256" => :SHA256, "FileSize" => :FILE_SIZE,
        "CodeSignatureDataOffset" => :CODE_SIGNATURE_DATA_OFFSET,
        "CodeSignatureDataSize" => :CODE_SIGNATURE_DATA_SIZE,
        "UnsignedPrefixSHA256" => :UNSIGNED_PREFIX_SHA256, "CDHash" => :CDHASH,
        "CodeDirectorySHA256" => :CODE_DIRECTORY_SHA256, "TeamIdentifier" => :TEAM_ID,
        "Identifier" => :IDENTIFIER, "DesignatedRequirement" => :DESIGNATED_REQUIREMENT
      }.each do |suffix, pin|
        payload["designatedRequirementReference#{suffix}"] =
          Legacy::Pins.const_get("APPROVED_PREDECESSOR_REFERENCE_#{pin}", false).to_s
      end
      %w[sourceTreeManifest candidateAppTreeManifest candidateAppCopyManifest].each do |prefix|
        payload["#{prefix}SHA256"] = Util.sha256(File.join(@root, payload.fetch("#{prefix}RelativePath")))
      end
      payload
    end

    def write_metadata!(payload)
      metadata = { "schema" => Legacy::Pins::CAPSULE_SCHEMA }
      (Legacy::Pins::CAPSULE_KEYS - ["schema"]).each { |key| metadata[key] = payload.fetch(key) }
      write_json!(File.join(@root, payload.fetch("capsuleMetadataRelativePath")), metadata)
      payload["capsuleMetadataSHA256"] = Util.sha256(File.join(@root, payload.fetch("capsuleMetadataRelativePath")))
      candidate = @contract.profile.fetch("candidate")
      identity = {
        "schema" => Legacy::Pins::IDENTITY_SCHEMA,
        "executablePath" => Legacy::Pins::LIVE_EXECUTABLE,
        "executableSHA256" => candidate.fetch("executableSHA256"),
        "executableCDHash" => candidate.fetch("executableCDHash"),
        "executableIdentifier" => Legacy::Pins::EXECUTABLE_IDENTIFIER,
        "executableTeamIdentifier" => Legacy::Pins::TEAM_ID,
        "mediaFrameworkExecutablePath" => Legacy::Pins::LIVE_FRAMEWORK_IDENTITY_PATH,
        "mediaFrameworkExecutableSHA256" => candidate.fetch("frameworkSHA256"),
        "mediaFrameworkExecutableCDHash" => candidate.fetch("frameworkCDHash"),
        "mediaFrameworkExecutableIdentifier" => Legacy::Pins::FRAMEWORK_IDENTIFIER,
        "mediaFrameworkExecutableTeamIdentifier" => Legacy::Pins::TEAM_ID
      }
      identity_path = File.join(@root, payload.fetch("hostIdentityManifestRelativePath"))
      write_json!(identity_path, identity)
      payload["hostIdentityManifestSHA256"] = Util.sha256(identity_path)
      sidecar!(identity_path, payload.fetch("hostIdentityManifestSHA256"))
      handoff = {
        "schema" => Legacy::Pins::HANDOFF_SCHEMA,
        "expectedTeamIdentifier" => Legacy::Pins::TEAM_ID,
        "hostIdentityManifestBasename" => File.basename(identity_path),
        "hostIdentityManifestSHA256Basename" => File.basename(identity_path) + ".sha256"
      }
      (Legacy::Pins::HANDOFF_KEYS - handoff.keys).each { |key| handoff[key] = payload.fetch(key) }
      handoff_path = File.join(@root, payload.fetch("handoffRelativePath"))
      write_json!(handoff_path, handoff)
      payload["handoffSHA256"] = Util.sha256(handoff_path)
      sidecar!(handoff_path, payload.fetch("handoffSHA256"))
    end

    def sidecar!(path, digest)
      write!(path + ".sha256", "#{digest}\n", 0o600)
    end

    def write_json!(path, object)
      write!(path, JSON.pretty_generate(object) + "\n", 0o600)
    end

    def write!(path, bytes, mode)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, mode) do |file|
        file.write(bytes)
        file.flush
        file.fsync
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise OpenSteamerV91Cutover::Failure, "usage: importer <profile> <profile-sha256> <fresh-capsule>" unless ARGV.length == 3
    contract = OpenSteamerHostSuccessor::ReleaseContract.new(ARGV[0], ARGV[1])
    OpenSteamerV91Cutover::Pins.bind_contract!(contract)
    puts JSON.pretty_generate(OpenSteamerHostSuccessor::PrebuiltCapsuleImporter.new(contract).import!(ARGV[2]))
  rescue OpenSteamerV91Cutover::Failure => error
    warn "prebuilt-host-successor: #{error.message}"
    exit 1
  end
end
