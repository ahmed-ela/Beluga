#!/usr/bin/ruby
# frozen_string_literal: true

# Transactional V91 host cutover controller.
#
# Preflight and self-test are observation-only. Execute is deliberately separate and accepts only
# a sealed artifact plus two independently transported SHA-256 digests. Each attempt has a fresh
# transaction; artifact build provenance and current deployment tooling are verified separately.

require "digest"
require "fiddle/import"
require "fileutils"
require "find"
require "json"
require "open3"
require "pathname"
require "rexml/document"
require "securerandom"
require "shellwords"
require "tempfile"
require "tmpdir"

module OpenSteamerV91Cutover
  class Failure < StandardError; end
  class CommittedButUnverified < Failure; end
  class JournalPersistenceUnverified < Failure; end

  module DarwinRename
    extend Fiddle::Importer
    dlload Fiddle.dlopen(nil)
    extern "int renamex_np(const char *, const char *, unsigned int)"
  end

  module Pins
    extend self

    RELEASE_KEYS = %i[
      SOURCE_BRANCH SOURCE_UPSTREAM SOURCE_COMMIT SOURCE_TREE TOOLING_FILES
      V90_CDHASH V90_DESIGNATED_REQUIREMENT V90_EXECUTABLE_SHA256
      V90_FRAMEWORK_SHA256 V90_INFO_PLIST_SHA256 V90_APP_MANIFEST_SHA256
      V90_BUNDLE_VERIFIER_SOURCE V90_BUNDLE_VERIFIER_SHA256 V90_COMMITTED_COPY_MANIFEST
      OBSERVER_EVIDENCE V90_HELPERS V91_UPDATE_ROOT V91_PENDING_POINTER
      V91_ACTIVE_POINTER V91_LOCK V91_JOURNAL_HEADER PAYLOAD_KEYS PAYLOAD_SCHEMA
    ].freeze

    def bind_contract!(contract)
      raise Failure, "release contract was already bound" if @contract
      raise Failure, "release pins were already observed; late binding is forbidden" if @pins_observed
      raise Failure, "release contract must be a verified immutable successor contract" unless
        defined?(OpenSteamerHostSuccessor::ReleaseContract) &&
        contract.instance_of?(OpenSteamerHostSuccessor::ReleaseContract) && contract.frozen?
      raise Failure, "release contract pin set differs" unless contract.pins.keys.sort == RELEASE_KEYS.sort
      @contract = contract
    end

    def fetch(name)
      @pins_observed = true
      @contract && RELEASE_KEYS.include?(name) ? @contract.pins.fetch(name) : const_get(name, false)
    end

    def contract
      @contract
    end

    def release_name
      @contract ? @contract.namespace : "v91"
    end

    def candidate_basename
      @contract ? "Beluga Host.app" : "opensteamer Host.app"
    end

    def candidate_verifier_relative
      @contract ? "macOS/scripts/verify-beluga-host-bundle.sh" : "macOS/scripts/verify-mac-host-bundle.sh"
    end

    def candidate_verifier_flags
      @contract ? ["--media-integration-v1"] : []
    end

    def state_out(state)
      @contract ? @contract.state_out(state) : state
    end

    def state_in(state)
      @contract ? @contract.state_in(state) : state
    end

    def record_out(text)
      @contract ? @contract.record_out(text) : text
    end

    def record_in(text)
      @contract ? @contract.record_in(text) : text
    end

    SOURCE_BRANCH = "fix/screen-quality-small-step"
    SOURCE_UPSTREAM = "origin/fix/screen-quality-small-step"
    SOURCE_COMMIT = "0af3846c4c9c81411e87d6ab997fac55dddc1e5d"
    SOURCE_TREE = "d820ce85893abafabecde33735763d5082bc31d3"
    TOOLING_ROOT = "/Volumes/t7/beluga-quality-step.idpzQO/source"
    TOOLING_REMOTE_URL = "https://github.com/ahmedelami/opensteamer.git"
    TOOLING_FILES = {
      "macOS/scripts/assemble-v91-sealed-host-oracle-capsule.sh" => 0o755,
      "macOS/scripts/opensteamer-host-v91-cutover-controller.rb" => 0o644,
      "macOS/scripts/opensteamer-v91-coreaudio-route-monitor.swift" => 0o644,
      "macOS/scripts/prepare-v91-sealed-host-oracle-handoff.sh" => 0o755,
      "macOS/scripts/run-opensteamer-host-v91-cutover.sh" => 0o755,
      "macOS/scripts/verify-mac-host-bundle.sh" => 0o755,
      "macOS/scripts/verify-v91-secondary-viewer-readiness.sh" => 0o755
    }.freeze

    TEAM_ID = "MSMG8CJLB3"
    EXECUTABLE_IDENTIFIER = "com.elamin.AudioStreamer.CaptureServer"
    FRAMEWORK_IDENTIFIER = "io.livekit.LiveKitWebRTC"
    V90_CDHASH = "129f2fc407d401ff29621ff940e726579baeaf18"
    V90_DESIGNATED_REQUIREMENT = 'identifier "com.elamin.AudioStreamer.CaptureServer" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: Ahmed Elamin (92LVX32M8K)" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */'
    APPROVED_PREDECESSOR_REFERENCE_SHA256 = "553892526e1f9de1e6d67b5556b3c2c008d9b48bbd553eb799c2260ee184ac66"
    APPROVED_PREDECESSOR_REFERENCE_FILE_SIZE = 11_442_304
    APPROVED_PREDECESSOR_REFERENCE_CODE_SIGNATURE_DATA_OFFSET = 11_401_072
    APPROVED_PREDECESSOR_REFERENCE_CODE_SIGNATURE_DATA_SIZE = 41_232
    APPROVED_PREDECESSOR_REFERENCE_UNSIGNED_PREFIX_SHA256 = "a7885a8d1ffef70f5a747eaed984a6cb70fe382491fcc6fbf8505aa0ad47ff5b"
    APPROVED_PREDECESSOR_REFERENCE_CDHASH = "e41c23322912104a648e791bfb0d3a5714323b26"
    APPROVED_PREDECESSOR_REFERENCE_CODE_DIRECTORY_SHA256 = "e41c23322912104a648e791bfb0d3a5714323b26b1b299ae5f0cfa225f68aba0"
    APPROVED_PREDECESSOR_REFERENCE_TEAM_ID = TEAM_ID
    APPROVED_PREDECESSOR_REFERENCE_IDENTIFIER = EXECUTABLE_IDENTIFIER
    APPROVED_PREDECESSOR_REFERENCE_DESIGNATED_REQUIREMENT = V90_DESIGNATED_REQUIREMENT
    LIVE_APP = "/Applications/opensteamer Host.app"
    LIVE_EXECUTABLE = "#{LIVE_APP}/Contents/MacOS/CaptureServer"
    LIVE_FRAMEWORK_IDENTITY_PATH = "#{LIVE_APP}/Contents/Frameworks/LiveKitWebRTC.framework/LiveKitWebRTC"
    LIVE_FRAMEWORK = "#{LIVE_APP}/Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC"
    LIVE_INFO_PLIST = "#{LIVE_APP}/Contents/Info.plist"
    PREDECESSOR_IDENTITY_PATHS = [
      LIVE_APP, LIVE_EXECUTABLE, LIVE_FRAMEWORK, LIVE_INFO_PLIST
    ].freeze
    LAUNCH_LABEL = "gui/501/org.example.opensteamer.worldwide"
    LAUNCH_AGENT = "/Users/ahmed/Library/LaunchAgents/org.example.opensteamer.worldwide.plist"
    LAUNCH_AGENT_SHA256 = "e8242cfa600bb5e62695cd954bcf59ce76a3884c5d4394accef4215ec642ee7a"
    LAUNCH_ARGUMENTS = [
      LIVE_EXECUTABLE,
      "--worldwide",
      "--allow-remote-control",
      "--virtual-phone-display",
      "--secondary-test-viewer",
      "--duration",
      "0",
      "--verbose",
      "--rendezvous-url",
      "wss://audiostreamer-rendezvous.elaminahmed03.workers.dev"
    ].freeze
    LAUNCH_ENVIRONMENT = { "OSLogRateLimit" => "64" }.freeze
    LAUNCH_STDOUT = "/var/tmp/opensteamer-worldwide-host.log"
    LAUNCH_STDERR = "/var/tmp/opensteamer-worldwide-host.err.log"

    # Trusted product bytes are immutable; process/start/nonce/inodes are captured per attempt.
    V90_EXECUTABLE_SHA256 = "f83ce7986aee069d3b7dac27ed6bdcdfa621695fc12d0fd9a240737fa57a3209"
    V90_FRAMEWORK_SHA256 = "f59d4ec6e70e3278c762134a6ef5648b9d00606c950d8366a4d395cd2e5e265a"
    V90_INFO_PLIST_SHA256 = "d9834328709efc82d553c7c507043fa6a342e3bc3873b9f7a8b9133dac3bb80f"
    V90_SOURCE_COMMIT = "92d08a1c434eefef40901333f6d924dc8851a162"
    V90_SOURCE_TREE = "00ace7a5f69afffdbe7abfdc5c27b1708ab0908c"

    RUNTIME_ROOT = "/Users/ahmed/Library/Application Support/opensteamer"
    V91_UPDATE_ROOT = "#{RUNTIME_ROOT}/paired-host-updates-v91"
    V91_PENDING_POINTER = "#{RUNTIME_ROOT}/pending-paired-host-update-v91"
    V91_ACTIVE_POINTER = "#{RUNTIME_ROOT}/active-paired-host-update-v91"
    V91_LOCK = "#{RUNTIME_ROOT}/paired-host-update-v91.lock"
    V91_JOURNAL_HEADER = "OPENSTEAMER_PAIRED_HOST_UPDATE_V91"

    APP_ROOT_ALLOWED_XATTRS = { "com.apple.macl" => ("00" * 72) }.freeze

    ROUTE_MONITOR_SOURCE = File.expand_path("opensteamer-v91-coreaudio-route-monitor.swift", __dir__)
    ROUTE_MONITOR_SOURCE_SHA256 = "b7ffc3c939ff2b19d1f85305335b3363555a967a76b38b034db377209f88bf86"
    SWIFTC = "/Volumes/t7/opensteamer-space-recovery-20260804/nonrepo/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
    SWIFTC_LINK_TARGET = "swift-frontend"
    SWIFTC_SHA256 = "2ed38571e92c0283091838c1649e27650ad9c99950288e883c7b2dc6c4ce89fb"
    SWIFTC_IDENTITY = [16_777_240, 15_755_469].freeze
    MACOS_SDK = "/Volumes/t7/opensteamer-space-recovery-20260804/nonrepo/Xcode-26.6.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk"
    MACOS_SDK_LINK_TARGET = "MacOSX.sdk"
    MACOS_SDK_IDENTITY = [16_777_240, 15_672_618].freeze
    MACOS_SDK_SETTINGS_SHA256 = "f8d005f09381389167f9e0aeaa169bc9e7dff162ef22ca2fd8e98df7ff1acafe"
    ROUTE_MONITOR_READY = "READY input=BlackHole2ch_UID output=BuiltInSpeakerDevice system=BuiltInSpeakerDevice"
    ROUTE_MONITOR_RESULT = "RESULT notifications=0 teardown=clean input=BlackHole2ch_UID output=BuiltInSpeakerDevice system=BuiltInSpeakerDevice"
    LAUNCHER_ATTESTATION = "opensteamer-v91-pinned-launcher-v1"
    DYNAMIC_CODESIGN_VERIFY_ARGUMENTS = ["--verify"].freeze
    READINESS_SOURCE_MODE = 0o755
    READINESS_STAGED_MODE = 0o500

    V90_POINTER = "#{RUNTIME_ROOT}/active-paired-host-update-v90"
    V90_POINTER_SHA256 = "bba26e9fe72799cbb1d75abbb6dd2299ff7377b3366f94a615b496bd4b693158"
    V90_EVIDENCE = "#{RUNTIME_ROOT}/paired-host-updates-v90/paired-v90-update-1790273646-83304-497866f7-25e2-4701-b155-442ca77d541c"
    V90_EVIDENCE_IDENTITY = [16_777_232, 35_708_281].freeze
    V90_JOURNAL_SHA256 = "79e8f192b9be3d34691a102fdb7f1f00a8ddebc757d1ebd1b8778267a5005b97"
    V90_RESULT_SHA256 = "c4d5f59786643a3dc5111ee4ed5a0f9277820e8b955d583a67c5433bfb99ac80"
    V90_COMMIT_PROOF_SHA256 = "7c748e138dcb33e7fca13df04cddb40c610d2f7b391eab992507d1f4e9cef582"
    V90_APP_MANIFEST_SHA256 = "c73d15ffab6a7a09b348a6eeb67d657e355ab6b8ff586084271ce4d1120faf28"
    V90_TERMINAL = "2026-09-24T18:19:11Z STATE COMMITTED_V90"
    OBSERVER_EVIDENCE = "#{V90_EVIDENCE}/pinned-v86-observer-tools"
    V90_BUNDLE_VERIFIER_SOURCE = File.expand_path("verify-mac-host-bundle.sh", __dir__)
    V90_BUNDLE_VERIFIER_SHA256 = "02a348a88d25b76ab95d45620d823339212bb53ee0f39bfb3a52f04240d3d745"
    V90_COMMITTED_COPY_MANIFEST = "#{V90_EVIDENCE}/v90-candidate-app-copy-manifest.txt"

    LIVE_LOCK_PATH = "/Users/ahmed/Library/Application Support/com.elamin.AudioStreamer.CaptureServer.runtime/worldwide-host.lock"
    LIVE_DISPLAY_MODE = "1080x1920@1080x1920 60.00Hz"
    ROUTES = {
      "output" => '{"name": "Mac mini Speakers", "type": "output", "id": "102", "uid": "BuiltInSpeakerDevice"}',
      "system" => '{"name": "Mac mini Speakers", "type": "system", "id": "102", "uid": "BuiltInSpeakerDevice"}',
      "input" => '{"name": "BlackHole 2ch", "type": "input", "id": "61", "uid": "BlackHole2ch_UID"}'
    }.freeze

    V90_HELPERS = {
      "SwitchAudioSource" => "9a29148a58b91c6ac13281b3cc1915922bdadd00ab09b3267271e5925d52fb64",
      "controller" => "0beb8e96aabd059ee5f108dfd05d7d5d99fa52b58f56ab942a31ee8efd33f528",
      "probe-worldwide-lock-v23" => "602c4578dcaec75629126d799056591dd0cea80c2f1ccaae5d91b0c341867e4f",
      "select-live-display-mode-v23" => "ee67b4797787098ea1073e4b579355366f534d865ff233a8b780ec5552c8f2a3",
      "verify-live-display-topology-v23" => "1502e07358f2316f4dee1fb12ce380cc5e9588cd6393ea3f34656ab80e9db292",
      "verify-live-mac-host-process.sh" => "0e56403570362c6d59ea86dc10d3cc53d7a5461d4a2f6c78d6e6c86dd13a4b41",
      "verify-media-v1-host-bundle.sh" => "e8a486a8e7360e5d3c8517e237e046fc21b3ccc2a3eb5e14ccd5d40135742e0c"
    }.freeze

    PAYLOAD_SCHEMA = "opensteamer.v91-deployment-payload-manifest.v2"
    CAPSULE_SCHEMA = "opensteamer.v91-host-oracle-capsule-metadata.v1"
    HANDOFF_SCHEMA = "opensteamer.v91-screen-oracle-host-identity-handoff.v1"
    IDENTITY_SCHEMA = "opensteamer.sealed-live-mac-host-identity.v1"

    PAYLOAD_KEYS = %w[
      schema sourceCommit sourceTree sourceBranch sourceUpstream sourceExportRelativePath
      sourceTreeManifestRelativePath sourceTreeManifestSHA256 candidateAppRelativePath
      candidateAppTreeManifestRelativePath candidateAppTreeManifestSHA256
      candidateExecutableRelativePath candidateExecutableSHA256
      candidateMediaFrameworkExecutableRelativePath candidateMediaFrameworkExecutableSHA256
      candidateInfoPlistRelativePath candidateInfoPlistSHA256 candidateLaunchPlistRelativePath
      candidateLaunchPlistSHA256 capsuleMetadataRelativePath capsuleMetadataSHA256
      handoffRelativePath handoffSHA256 hostIdentityManifestRelativePath
      hostIdentityManifestSHA256 designatedRequirementReferenceRelativePath
      designatedRequirementReferenceSHA256 candidateAppCopyManifestRelativePath
      designatedRequirementReferenceFileSize
      designatedRequirementReferenceCodeSignatureDataOffset
      designatedRequirementReferenceCodeSignatureDataSize
      designatedRequirementReferenceUnsignedPrefixSHA256
      designatedRequirementReferenceCDHash designatedRequirementReferenceCodeDirectorySHA256
      designatedRequirementReferenceTeamIdentifier designatedRequirementReferenceIdentifier
      designatedRequirementReferenceDesignatedRequirement
      candidateAppCopyManifestSHA256 toolingBranch toolingUpstream toolingCommit toolingTree
      toolingRemoteURL assemblerScriptRelativePath assemblerScriptGitBlob
    ].freeze
    CAPSULE_KEYS = %w[
      schema candidateAppRelativePath candidateExecutableSHA256
      candidateMediaFrameworkExecutableSHA256 designatedRequirementReferenceRelativePath
      designatedRequirementReferenceSHA256
    ].freeze
    HANDOFF_KEYS = %w[
      schema capsuleMetadataSHA256 candidateAppRelativePath candidateExecutableSHA256
      candidateMediaFrameworkExecutableSHA256 designatedRequirementReferenceRelativePath
      designatedRequirementReferenceSHA256 expectedTeamIdentifier hostIdentityManifestBasename
      hostIdentityManifestSHA256 hostIdentityManifestSHA256Basename
    ].freeze
    IDENTITY_KEYS = %w[
      schema executablePath executableSHA256 executableCDHash executableIdentifier
      executableTeamIdentifier mediaFrameworkExecutablePath mediaFrameworkExecutableSHA256
      mediaFrameworkExecutableCDHash mediaFrameworkExecutableIdentifier
      mediaFrameworkExecutableTeamIdentifier
    ].freeze

    ALLOWED_CANDIDATE_SYMLINKS = {
      "Contents/Frameworks/LiveKitWebRTC.framework/Headers" => "Versions/Current/Headers",
      "Contents/Frameworks/LiveKitWebRTC.framework/LiveKitWebRTC" => "Versions/Current/LiveKitWebRTC",
      "Contents/Frameworks/LiveKitWebRTC.framework/Modules" => "Versions/Current/Modules",
      "Contents/Frameworks/LiveKitWebRTC.framework/Resources" => "Versions/Current/Resources",
      "Contents/Frameworks/LiveKitWebRTC.framework/Versions/Current" => "A"
    }.freeze
  end

  module Util
    extend self

    SHA256 = /\A[0-9a-f]{64}\z/.freeze
    RELATIVE = /\A[^\x00-\x1f\x7f]+\z/.freeze

    class DuplicateRejectingHash < Hash
      def []=(key, value)
        raise Failure, "JSON contains duplicate key #{key.inspect}" if key?(key)
        super
      end
    end

    def fail!(message)
      raise Failure, message
    end

    def sha256(path)
      Digest::SHA256.file(path).hexdigest
    rescue SystemCallError => error
      fail!("could not hash #{path}: #{error.message}")
    end

    def sha256_text(text)
      Digest::SHA256.hexdigest(text.b)
    end

    def exact_prefixed_values(text, prefix)
      binary_prefix = prefix.b
      text.b.lines.map do |line|
        stripped = line.strip
        stripped.delete_prefix(binary_prefix) if stripped.start_with?(binary_prefix)
      end.compact
    end

    def exact_code_identity_values(text)
      {
        identifier: exact_prefixed_values(text, "Identifier="),
        team_identifier: exact_prefixed_values(text, "TeamIdentifier="),
        cdhash: exact_prefixed_values(text, "CDHash=").map(&:downcase)
      }
    end

    def assert_sha!(value, label)
      fail!("#{label} is not a lowercase SHA-256") unless SHA256.match?(value.to_s)
    end

    def strict_json(path, keys, schema)
      text = File.binread(path)
      object = JSON.parse(text, object_class: DuplicateRejectingHash, array_class: Array)
      fail!("#{path} is not a flat JSON object") unless object.is_a?(Hash)
      fail!("#{path} fields differ from strict schema") unless object.keys.sort == keys.sort
      fail!("#{path} contains non-string values") unless object.values.all? { |value| value.is_a?(String) }
      fail!("#{path} has wrong schema") unless object.fetch("schema") == schema
      object
    rescue JSON::ParserError => error
      fail!("#{path} is not strict JSON: #{error.message}")
    end

    def relative_path!(value, label)
      candidate = value.to_s
      clean = Pathname.new(candidate).cleanpath.to_s
      fail!("#{label} is not a normalized relative path") unless
        RELATIVE.match?(candidate) && !candidate.start_with?("/") && clean == candidate &&
        candidate != "." && !candidate.end_with?("/") && !candidate.include?("//")
      candidate
    end

    def inside(root, relative, label)
      relative_path!(relative, label)
      joined = File.join(root, relative)
      expanded = File.expand_path(joined)
      fail!("#{label} escapes capsule") unless expanded.start_with?(root + File::SEPARATOR)
      joined
    end

    def regular_file!(path, label, mode: nil, owner: nil, links: 1)
      stat = File.lstat(path)
      fail!("#{label} is not a regular non-symlink file") unless stat.file?
      fail!("#{label} has wrong owner") if owner && stat.uid != owner
      fail!("#{label} has wrong mode") if mode && (stat.mode & 0o7777) != mode
      fail!("#{label} has wrong hard-link count") if links && stat.nlink != links
      clean_node_metadata!(path, label)
      stat
    rescue Errno::ENOENT
      fail!("#{label} is missing")
    end

    def directory!(path, label, mode: nil, owner: nil)
      stat = File.lstat(path)
      fail!("#{label} is not a real directory") unless stat.directory?
      fail!("#{label} has wrong owner") if owner && stat.uid != owner
      fail!("#{label} has wrong mode") if mode && (stat.mode & 0o7777) != mode
      clean_node_metadata!(path, label)
      stat
    rescue Errno::ENOENT
      fail!("#{label} is missing")
    end

    def exact_file!(path, expected_sha, label, **metadata)
      regular_file!(path, label, **metadata)
      assert_sha!(expected_sha, "#{label} expected digest")
      fail!("#{label} digest mismatch") unless sha256(path) == expected_sha
    end

    def bsd_flags(path, label)
      value = capture!("/usr/bin/stat", "-f", "%f", path).strip
      Integer(value, 10)
    rescue ArgumentError
      fail!("#{label} BSD flags are malformed")
    end

    def clean_node_metadata!(path, label)
      listing = capture!("/bin/ls", "-lde", path).lines.first.to_s
      fail!("#{label} has an ACL") if listing.split.first.to_s.include?("+")
      stdout, stderr, status = Open3.capture3("/usr/bin/xattr", path)
      fail!("could not inspect #{label} xattrs: #{stderr.strip}") unless status.success?
      fail!("#{label} has extended attributes") unless stdout.empty?
      fail!("#{label} has nonzero BSD flags") unless bsd_flags(path, label).zero?
      true
    end

    def sidecar!(committed, sidecar, expected, label)
      exact_file!(committed, expected, label, mode: 0o600, owner: Process.euid)
      regular_file!(sidecar, "#{label} sidecar", mode: 0o600, owner: Process.euid)
      fail!("#{label} sidecar is not canonical") unless File.binread(sidecar) == "#{expected}\n"
    end

    def capture!(*command, stdin_data: nil)
      stdout, stderr, status = Open3.capture3(*command, stdin_data: stdin_data)
      fail!("command failed: #{command.shelljoin}: #{stderr.strip}") unless status.success?
      stdout
    end

    def canonical_absolute!(path, label)
      fail!("#{label} is not canonical absolute path") unless
        path.start_with?("/") && File.expand_path(path) == path && File.realpath(path) == path
      path
    rescue Errno::ENOENT
      fail!("#{label} is missing")
    end
  end

  # The retained predecessor is copied out of its original app bundle before cutover. A standalone
  # copy is intentionally not treated as full-bundle resource proof because its Info.plist and
  # sealed resources remain behind. Revalidate the copied code object without weakening its
  # identity: exact bytes, unsigned Mach-O prefix, embedded signature extent, CodeDirectory digest,
  # TeamIdentifier, identifier, and designated requirement are all independently pinned.
  module PredecessorReferenceFingerprint
    extend self

    MACH_HEADER_64_SIZE = 32
    MH_MAGIC_64 = 0xfeedfacf
    CPU_TYPE_ARM64 = 0x0100000c
    LC_CODE_SIGNATURE = 0x1d

    def verify!(path, label: "capsule predecessor reference")
      stat, data = read_snapshot(path, label)
      Util.fail!("#{label} size differs from approved predecessor") unless
        stat.size == Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_FILE_SIZE)
      Util.fail!("#{label} full-file digest differs from approved predecessor") unless
        Digest::SHA256.hexdigest(data) == Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_SHA256)

      data_offset, data_size = signature_layout(data)
      Util.fail!("#{label} LC_CODE_SIGNATURE layout differs from approved predecessor") unless
        data_offset == Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_CODE_SIGNATURE_DATA_OFFSET) &&
        data_size == Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_CODE_SIGNATURE_DATA_SIZE) &&
        data_offset + data_size == data.bytesize
      prefix = data.byteslice(0, data_offset)
      Util.fail!("#{label} unsigned-prefix digest differs from approved predecessor") unless
        prefix && Digest::SHA256.hexdigest(prefix) == Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_UNSIGNED_PREFIX_SHA256)

      metadata = combined_codesign!("--display", "--verbose=6", path)
      exact_field!(metadata, "Identifier=", Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_IDENTIFIER), label)
      exact_field!(metadata, "TeamIdentifier=", Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_TEAM_ID), label)
      exact_field!(metadata, "CDHash=", Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_CDHASH), label)
      exact_field!(
        metadata,
        "CandidateCDHashFull sha256=",
        Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_CODE_DIRECTORY_SHA256),
        label
      )

      requirements = combined_codesign!("--display", "--requirements", "-", path)
      designated = requirements.lines.map { |line| line.strip.sub(/\A# /, "") }
                               .select { |line| line.start_with?("designated => ") }
      expected = "designated => #{Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_DESIGNATED_REQUIREMENT)}"
      Util.fail!("#{label} designated requirement differs from approved predecessor") unless
        designated == [expected]
      final_stat, final_data = read_snapshot(path, label)
      Util.fail!("#{label} identity or bytes changed during fingerprint verification") unless
        [final_stat.dev, final_stat.ino, final_stat.size] == [stat.dev, stat.ino, stat.size] &&
        Digest::SHA256.hexdigest(final_data) == Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_SHA256)
      true
    rescue Errno::ENOENT, Errno::EACCES => error
      Util.fail!("could not fingerprint #{label}: #{error.message}")
    end

    def signature_layout(data)
      Util.fail!("predecessor reference is too short for a Mach-O header") if
        data.bytesize < MACH_HEADER_64_SIZE
      magic, cpu_type, _cpu_subtype, _file_type, command_count, commands_size,
        _flags, _reserved = data.byteslice(0, MACH_HEADER_64_SIZE).unpack("V8")
      Util.fail!("predecessor reference is not a thin 64-bit Mach-O") unless magic == MH_MAGIC_64
      Util.fail!("predecessor reference is not arm64") unless cpu_type == CPU_TYPE_ARM64
      command_end = MACH_HEADER_64_SIZE + commands_size
      Util.fail!("predecessor reference load-command extent is invalid") if
        command_end > data.bytesize || command_count.zero?

      cursor = MACH_HEADER_64_SIZE
      signatures = []
      command_count.times do
        Util.fail!("predecessor reference has a truncated load command") if cursor + 8 > command_end
        command, command_size = data.byteslice(cursor, 8).unpack("V2")
        Util.fail!("predecessor reference has an invalid load-command size") if
          command_size < 8 || (command_size % 8) != 0 || cursor + command_size > command_end
        if command == LC_CODE_SIGNATURE
          Util.fail!("predecessor LC_CODE_SIGNATURE has an invalid size") unless command_size == 16
          signatures << data.byteslice(cursor + 8, 8).unpack("V2")
        end
        cursor += command_size
      end
      Util.fail!("predecessor reference load-command count/size mismatch") unless cursor == command_end
      Util.fail!("predecessor reference must contain exactly one LC_CODE_SIGNATURE") unless
        signatures.length == 1
      signatures.fetch(0)
    end

    private

    def read_snapshot(path, label)
      before = Util.regular_file!(path, label, mode: 0o755, owner: Process.euid, links: 1)
      opened = nil
      data = nil
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        opened = file.stat
        Util.fail!("#{label} changed while opening") unless
          opened.file? &&
          [opened.dev, opened.ino, opened.size, opened.nlink] ==
            [before.dev, before.ino, before.size, 1]
        data = file.read
        Util.fail!("#{label} short read") unless data.bytesize == opened.size
      end
      after = File.lstat(path)
      Util.fail!("#{label} changed while reading") unless
        after.file? && [after.dev, after.ino, after.size, after.nlink] ==
          [opened.dev, opened.ino, opened.size, 1]
      [opened, data]
    end

    def combined_codesign!(*arguments)
      stdout, stderr, status = Open3.capture3("/usr/bin/codesign", *arguments)
      Util.fail!("codesign metadata inspection failed: #{stderr.strip}") unless status.success?
      stdout.b + stderr.b
    end

    def exact_field!(metadata, prefix, expected, label)
      values = Util.exact_prefixed_values(metadata, prefix)
      Util.fail!("#{label} #{prefix.delete_suffix('=')} differs from approved predecessor") unless
        values == [expected]
    end
  end

  # Live invocations are accepted only from the canonical clean worktree whose HEAD is the
  # single fresh remote branch tip. Each runtime tool must be byte-identical to its tracked HEAD
  # blob. Later boundaries recheck the same local proof, not the unchanged remote branch.
  module ToolingProof
    extend self

    def verify!(remote: true)
      root = Pins.fetch(:TOOLING_ROOT)
      Util.fail!("tooling root is not canonical") unless
        File.expand_path(root) == root && File.realpath(root) == root
      Util.directory!(root, "V91 tooling root", mode: 0o755, owner: Process.euid)

      branch = git!("symbolic-ref", "--short", "HEAD").strip
      upstream = git!("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}").strip
      Util.fail!("tooling branch differs from pinned V91 branch") unless branch == Pins.fetch(:SOURCE_BRANCH)
      Util.fail!("tooling upstream differs from pinned V91 upstream") unless upstream == Pins.fetch(:SOURCE_UPSTREAM)

      fetch_urls = git!("remote", "get-url", "--all", "origin").lines.map(&:chomp)
      push_urls = git!("remote", "get-url", "--push", "--all", "origin").lines.map(&:chomp)
      Util.fail!("tooling origin fetch URL differs") unless fetch_urls == [Pins.fetch(:TOOLING_REMOTE_URL)]
      Util.fail!("tooling origin push URL differs") unless push_urls == [Pins.fetch(:TOOLING_REMOTE_URL)]

      head = git!("rev-parse", "HEAD").strip
      tree = git!("rev-parse", "HEAD^{tree}").strip
      upstream_head = git!("rev-parse", "@{u}").strip
      [head, tree, upstream_head].each do |object_id|
        Util.fail!("tooling Git identity is malformed") unless object_id.match?(/\A[0-9a-f]{40}\z/)
      end
      Util.fail!("tooling HEAD differs from local upstream") unless head == upstream_head
      Util.fail!("tooling worktree is not clean") unless
        git!("status", "--porcelain=v1", "--untracked-files=all").empty?

      if remote
        remote_tip = git!("ls-remote", "--exit-code", "--refs", "--heads", "origin", "refs/heads/#{branch}")
        Util.fail!("tooling remote branch lookup is not a single exact record") unless
          remote_tip.lines.map(&:chomp) == ["#{head}\trefs/heads/#{branch}"]
      end

      blobs = {}
      Pins.fetch(:TOOLING_FILES).each do |relative, mode|
        path = File.join(root, relative)
        Util.fail!("tooling file path is not canonical: #{relative}") unless File.realpath(path) == path
        Util.regular_file!(
          path,
          "tracked V91 tooling file #{relative}",
          mode: mode,
          owner: Process.euid,
          links: 1
        )
        tracked = git!("ls-files", "--error-unmatch", "--", relative).lines.map(&:chomp)
        Util.fail!("V91 tooling file is not uniquely tracked: #{relative}") unless tracked == [relative]
        working_blob = git!("hash-object", "--no-filters", "--", relative).strip
        head_blob = git!("rev-parse", "HEAD:#{relative}").strip
        Util.fail!("V91 tooling blob identity is malformed: #{relative}") unless
          working_blob.match?(/\A[0-9a-f]{40}\z/) && head_blob.match?(/\A[0-9a-f]{40}\z/)
        Util.fail!("V91 tooling bytes differ from tracked HEAD: #{relative}") unless working_blob == head_blob
        blobs[relative] = head_blob
      end

      {
        commit: head,
        tree: tree,
        blobs: blobs.freeze,
        launcher_blob: blobs.fetch("macOS/scripts/run-opensteamer-host-v91-cutover.sh"),
        assembler_blob: blobs.fetch("macOS/scripts/assemble-v91-sealed-host-oracle-capsule.sh")
      }
    rescue Errno::ENOENT
      Util.fail!("canonical V91 tooling path is missing")
    end

    def verify_unchanged!(proof)
      Util.fail!("deployment tooling changed during this invocation") unless verify!(remote: false) == proof
      proof
    end

    def verify_build_provenance!(payload, proof)
      BuildProvenance.verify!(payload, proof, git: method(:git!))
    end

    def readiness_observer!(proof)
      TrackedToolSnapshot.read!(
        Pins.fetch(:TOOLING_ROOT),
        "macOS/scripts/verify-v91-secondary-viewer-readiness.sh",
        proof,
        mode: Pins.fetch(:READINESS_SOURCE_MODE)
      )
    end

    def verify_launcher_environment!(proof)
      expected = {
        "OPENSTEAMER_V91_LAUNCHER_ATTESTATION" => Pins.fetch(:LAUNCHER_ATTESTATION),
        "OPENSTEAMER_V91_LAUNCHER_PATH" => File.join(
          Pins.fetch(:TOOLING_ROOT),
          "macOS/scripts/run-opensteamer-host-v91-cutover.sh"
        ),
        "OPENSTEAMER_V91_TOOLING_COMMIT" => proof.fetch(:commit),
        "OPENSTEAMER_V91_TOOLING_TREE" => proof.fetch(:tree),
        "OPENSTEAMER_V91_LAUNCHER_BLOB" => proof.fetch(:launcher_blob),
        "OPENSTEAMER_V91_ASSEMBLER_BLOB" => proof.fetch(:assembler_blob)
      }
      expected.each do |key, value|
        Util.fail!("live V91 launcher attestation mismatch: #{key}") unless ENV[key] == value
      end
      true
    end

    private

    def git!(*arguments)
      Util.capture!("/usr/bin/git", "-C", Pins.fetch(:TOOLING_ROOT), *arguments)
    end
  end

  module BuildProvenance
    extend self

    def verify!(payload, deployment, git:)
      build_commit = payload.fetch("toolingCommit")
      source_commit = payload.fetch("sourceCommit")
      assembler = payload.fetch("assemblerScriptRelativePath")
      %w[toolingCommit toolingTree assemblerScriptGitBlob sourceCommit sourceTree].each do |key|
        Util.fail!("build provenance #{key} is not a lowercase Git object id") unless
          payload.fetch(key).match?(/\A[0-9a-f]{40}\z/)
      end
      Util.fail!("build provenance assembler path differs") unless
        assembler == (Pins.contract ? "macOS/scripts/import-prebuilt-host-successor.rb" : "macOS/scripts/assemble-v91-sealed-host-oracle-capsule.sh")
      {
        "#{source_commit}^{commit}" => source_commit,
        "#{source_commit}^{tree}" => payload.fetch("sourceTree"),
        "#{build_commit}^{commit}" => build_commit,
        "#{build_commit}^{tree}" => payload.fetch("toolingTree"),
        "#{build_commit}:#{assembler}" => payload.fetch("assemblerScriptGitBlob")
      }.each do |revision, expected|
        Util.fail!("historical build provenance differs: #{revision}") unless
          git.call("rev-parse", "--verify", revision).strip == expected
      end
      Util.fail!("historical assembler is not a Git blob") unless
        git.call("cat-file", "-t", payload.fetch("assemblerScriptGitBlob")).strip == "blob"
      git.call("merge-base", "--is-ancestor", source_commit, build_commit)
      git.call("merge-base", "--is-ancestor", build_commit, deployment.fetch(:commit))
      true
    end
  end

  module TrackedToolSnapshot
    extend self

    def read!(root, relative, proof, mode:)
      path = File.join(root, relative)
      Util.fail!("tracked observer path is not canonical") unless File.realpath(path) == path
      before = Util.regular_file!(path, "tracked readiness observer", mode: mode, owner: Process.euid, links: 1)
      data = nil
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        opened = file.stat
        Util.fail!("tracked observer changed while opening") unless
          [opened.dev, opened.ino, opened.size, opened.nlink] == [before.dev, before.ino, before.size, 1]
        data = file.read
      end
      after = Util.regular_file!(path, "tracked readiness observer", mode: mode, owner: Process.euid, links: 1)
      Util.fail!("tracked observer changed while reading") unless
        [after.dev, after.ino, after.size] == [before.dev, before.ino, data.bytesize]
      blob = Digest::SHA1.hexdigest("blob #{data.bytesize}\0".b + data)
      Util.fail!("readiness observer differs from verified deployment tooling") unless
        proof.fetch(:blobs).fetch(relative) == blob
      {
        "deploymentToolingCommit" => proof.fetch(:commit),
        "deploymentToolingTree" => proof.fetch(:tree),
        "readinessScriptRelativePath" => relative,
        "readinessScriptGitBlob" => blob,
        "readinessScriptSHA256" => Digest::SHA256.hexdigest(data),
        "bytes" => data
      }
    rescue Errno::ENOENT
      Util.fail!("tracked readiness observer is missing")
    end
  end

  class TreeManifest
    include Util

    def initialize(root, kind)
      @root = root
      @kind = kind
    end

    def verify!(manifest_path)
      expected = File.binread(manifest_path)
      actual, symlinks = render
      Util.fail!("#{@kind} tree manifest does not exactly match filesystem") unless actual == expected
      if @kind == :candidate
        Util.fail!("candidate aliases differ from reviewed five-link set") unless symlinks == Pins.fetch(:ALLOWED_CANDIDATE_SYMLINKS)
      else
        Util.fail!("source export contains a symbolic link") unless symlinks.empty?
      end
      true
    end

    def render
      Util.directory!(@root, "#{@kind} tree root")
      entries = []
      enumerate(@root, "", entries)
      Util.fail!("#{@kind} tree is empty") if entries.empty?
      symlinks = {}
      records = entries.sort_by { |relative, _| relative.b }.map do |relative, path|
        Util.relative_path!(relative, "#{@kind} tree entry")
        stat = File.lstat(path)
        assert_clean_metadata!(path, relative)
        flags = Util.bsd_flags(path, "#{@kind} tree entry #{relative}")
        Util.fail!("unsafe BSD flags in #{@kind} tree: #{relative}") unless flags.zero?
        metadata = format("%04o:%d:%d:%d:%d:%d", stat.mode & 0o7777, stat.uid, stat.gid, stat.nlink, stat.size, flags)
        if stat.symlink?
          target = File.readlink(path)
          Util.fail!("unsafe symlink target") if target.empty? || target.match?(/[\x00-\x1f\x7f]/)
          Util.fail!("hard-linked symbolic link in candidate tree") unless stat.nlink == 1
          symlinks[relative] = target
          assert_reviewed_alias_resolution!(relative, path, target)
          "L\t#{metadata}\t#{Util.sha256_text(target)}\t#{target}\t#{relative}\n"
        elsif stat.file?
          Util.fail!("hard-linked file in #{@kind} tree") unless stat.nlink == 1
          "F\t#{metadata}\t#{Util.sha256(path)}\t#{relative}\n"
        elsif stat.directory?
          "D\t#{metadata}\t#{relative}\n"
        else
          Util.fail!("unsupported file type in #{@kind} tree: #{relative}")
        end
      end
      [records.join, symlinks]
    end

    private

    def enumerate(directory, prefix, entries)
      Dir.children(directory).each do |name|
        Util.fail!("unsafe tree name") if name.match?(/[\x00-\x1f\x7f]/)
        relative = prefix.empty? ? name : File.join(prefix, name)
        path = File.join(directory, name)
        stat = File.lstat(path)
        entries << [relative, path]
        enumerate(path, relative, entries) if stat.directory?
      end
    end

    def assert_clean_metadata!(path, relative)
      listing = Util.capture!("/bin/ls", "-lde", path).lines.first.to_s
      Util.fail!("ACL in #{@kind} tree: #{relative}") if listing.split.first.to_s.include?("+")
      command = ["/usr/bin/xattr"]
      command << "-s" if File.lstat(path).symlink?
      stdout, stderr, status = Open3.capture3(*command, path)
      Util.fail!("could not inspect xattrs for #{relative}: #{stderr.strip}") unless status.success?
      Util.fail!("xattrs in #{@kind} tree: #{relative}") unless stdout.empty?
    end

    def assert_reviewed_alias_resolution!(relative, path, target)
      return unless @kind == :candidate
      Util.fail!("candidate tree has unreviewed symlink") unless Pins.fetch(:ALLOWED_CANDIDATE_SYMLINKS)[relative] == target
      resolved = File.realpath(File.join(File.dirname(path), target))
      Util.fail!("candidate alias escapes app") unless resolved.start_with?(File.realpath(@root) + "/")
      if relative == "Contents/Frameworks/LiveKitWebRTC.framework/LiveKitWebRTC"
        Util.fail!("candidate framework alias is not executable code") unless File.file?(resolved) && File.executable?(resolved)
      else
        Util.fail!("candidate framework alias is not a directory") unless File.directory?(resolved)
      end
    rescue Errno::ENOENT
      Util.fail!("candidate alias is dangling: #{relative}")
    end
  end

  class CopyManifest
    def self.capture_published_root_xattrs!(root)
      names = Util.capture!("/usr/bin/xattr", root).lines.map(&:chomp).reject(&:empty?).sort
      allowed = names.empty? ? {} : Pins.fetch(:APP_ROOT_ALLOWED_XATTRS)
      captured = allowed.transform_values { |value| value.dup.freeze }.freeze
      new(root, allowed_root_xattrs: captured).send(:verify_root!)
      captured
    end

    def initialize(root, allowed_root_xattrs: {})
      @root = root
      @allowed_root_xattrs = allowed_root_xattrs
      @allowed_root_xattrs.each do |name, hex|
        Util.fail!("invalid allowed candidate-root xattr name") if
          name.empty? || name.match?(/[\x00-\x1f\x7f]/)
        Util.fail!("invalid allowed candidate-root xattr value") unless
          hex.match?(/\A(?:[0-9a-f]{2})*\z/)
      end
    end

    def verify!(manifest_path)
      expected = File.binread(manifest_path)
      actual, aliases = render
      Util.fail!("candidate copy-stable manifest mismatch") unless actual == expected
      Util.fail!("candidate copy aliases differ from reviewed set") unless aliases == Pins.fetch(:ALLOWED_CANDIDATE_SYMLINKS)
      true
    end

    def render
      verify_root!
      entries = []
      enumerate(@root, "", entries)
      aliases = {}
      records = entries.sort_by { |relative, _| relative.b }.map do |relative, path|
        Util.relative_path!(relative, "candidate copy entry")
        stat = File.lstat(path)
        assert_clean_metadata!(path, relative)
        flags = Util.bsd_flags(path, "candidate copy entry #{relative}")
        Util.fail!("unsafe BSD flags in candidate copy: #{relative}") unless flags.zero?
        mode = format("%04o", stat.mode & 0o7777)
        if stat.symlink?
          target = File.readlink(path)
          aliases[relative] = target
          Util.fail!("candidate copy has unreviewed symlink") unless Pins.fetch(:ALLOWED_CANDIDATE_SYMLINKS)[relative] == target
          Util.fail!("candidate copy has hard-linked symlink") unless stat.nlink == 1
          assert_alias_resolution!(relative, path, target)
          "L\t#{Util.sha256_text(target)}\t#{target}\t#{relative}\n"
        elsif stat.file?
          Util.fail!("candidate copy contains hard-linked file") unless stat.nlink == 1
          "F\t#{mode}:#{stat.size}\t#{Util.sha256(path)}\t#{relative}\n"
        elsif stat.directory?
          "D\t#{mode}\t#{relative}\n"
        else
          Util.fail!("candidate copy contains unsupported file type: #{relative}")
        end
      end
      [records.join, aliases]
    end

    private

    def verify_root!
      stat = File.lstat(@root)
      Util.fail!("candidate copy root is not a real directory") unless stat.directory?
      Util.fail!("candidate copy root has wrong owner") unless stat.uid == Process.euid
      Util.fail!("candidate copy root has wrong mode") unless (stat.mode & 0o7777) == 0o755
      listing = Util.capture!("/bin/ls", "-lde", @root).lines.first.to_s
      Util.fail!("candidate copy root has an ACL") if listing.split.first.to_s.include?("+")
      Util.fail!("candidate copy root has nonzero BSD flags") unless
        Util.bsd_flags(@root, "candidate copy root").zero?
      stdout, stderr, status = Open3.capture3("/usr/bin/xattr", @root)
      Util.fail!("could not inspect candidate copy root xattrs: #{stderr.strip}") unless status.success?
      names = stdout.lines.map(&:chomp).reject(&:empty?).sort
      Util.fail!("candidate copy root xattrs differ from exact allowance") unless
        names == @allowed_root_xattrs.keys.sort
      @allowed_root_xattrs.each do |name, expected_hex|
        encoded, encoded_stderr, encoded_status = Open3.capture3(
          "/usr/bin/xattr", "-px", name, @root
        )
        Util.fail!("could not read candidate copy root xattr #{name}: #{encoded_stderr.strip}") unless
          encoded_status.success?
        actual_hex = encoded.gsub(/[[:space:]]/, "").downcase
        Util.fail!("candidate copy root xattr #{name} changed") unless actual_hex == expected_hex
      end
      true
    rescue Errno::ENOENT
      Util.fail!("candidate copy root is missing")
    end

    def enumerate(directory, prefix, entries)
      Dir.children(directory).each do |name|
        Util.fail!("unsafe candidate copy name") if name.match?(/[\x00-\x1f\x7f]/)
        relative = prefix.empty? ? name : File.join(prefix, name)
        path = File.join(directory, name)
        stat = File.lstat(path)
        entries << [relative, path]
        enumerate(path, relative, entries) if stat.directory?
      end
    end

    def assert_clean_metadata!(path, relative)
      listing = Util.capture!("/bin/ls", "-lde", path).lines.first.to_s
      Util.fail!("ACL in candidate copy: #{relative}") if listing.split.first.to_s.include?("+")
      command = ["/usr/bin/xattr"]
      command << "-s" if File.lstat(path).symlink?
      stdout, stderr, status = Open3.capture3(*command, path)
      Util.fail!("could not inspect candidate copy xattrs: #{stderr.strip}") unless status.success?
      Util.fail!("xattrs in candidate copy: #{relative}") unless stdout.empty?
    end

    def assert_alias_resolution!(relative, path, target)
      resolved = File.realpath(File.join(File.dirname(path), target))
      Util.fail!("candidate alias escapes app") unless resolved.start_with?(File.realpath(@root) + "/")
      if relative == "Contents/Frameworks/LiveKitWebRTC.framework/LiveKitWebRTC"
        Util.fail!("candidate copy framework alias is not executable code") unless File.file?(resolved) && File.executable?(resolved)
      else
        Util.fail!("candidate copy framework alias is not a directory") unless File.directory?(resolved)
      end
    rescue Errno::ENOENT
      Util.fail!("candidate copy alias is dangling: #{relative}")
    end
  end

  module LaunchContract
    extend self

    def verify!(path)
      root = REXML::Document.new(File.binread(path)).root
      Util.fail!("launch plist root is invalid") unless root && root.name == "plist"
      dict = root.elements.to_a.reject { |node| node.is_a?(REXML::Text) }.first
      value = parse_node(dict)
      expected = {
        "Label" => "org.example.opensteamer.worldwide",
        "ProgramArguments" => Pins.fetch(:LAUNCH_ARGUMENTS),
        "RunAtLoad" => true,
        "KeepAlive" => true,
        "ThrottleInterval" => 10,
        "StandardOutPath" => Pins.fetch(:LAUNCH_STDOUT),
        "StandardErrorPath" => Pins.fetch(:LAUNCH_STDERR),
        "EnvironmentVariables" => Pins.fetch(:LAUNCH_ENVIRONMENT)
      }
      Util.fail!("launch plist differs from exact ten-argument V91 contract") unless value == expected
      true
    rescue REXML::ParseException => error
      Util.fail!("launch plist is malformed: #{error.message}")
    end

    def parse_node(node)
      Util.fail!("unexpected empty plist value") unless node
      case node.name
      when "dict"
        children = node.elements.to_a
        Util.fail!("plist dict has odd child count") unless children.length.even?
        result = {}
        children.each_slice(2) do |key, value|
          Util.fail!("plist dict key is malformed") unless key.name == "key"
          Util.fail!("plist contains duplicate key #{key.text.inspect}") if result.key?(key.text)
          result[key.text] = parse_node(value)
        end
        result
      when "array"
        node.elements.to_a.map { |child| parse_node(child) }
      when "string" then node.text.to_s
      when "integer"
        Integer(node.text, 10)
      when "true" then true
      when "false" then false
      else Util.fail!("unsupported plist node #{node.name}")
      end
    rescue ArgumentError
      Util.fail!("plist integer is malformed")
    end
  end

  class Capsule
    attr_reader :root, :payload, :paths, :identity, :tooling

    def initialize(root, external_handoff_sha, external_payload_sha, tooling: nil)
      @root = root.sub(%r{/+\z}, "")
      @external_handoff_sha = external_handoff_sha
      @external_payload_sha = external_payload_sha
      @paths = {}
      @tooling = tooling
    end

    def verify!
      Util.assert_sha!(@external_handoff_sha, "external handoff digest")
      Util.assert_sha!(@external_payload_sha, "external payload digest")
      OpenSteamerHostSuccessor::Checks.artifact_path!(@root, "successor capsule") if Pins.contract
      Util.canonical_absolute!(@root, "capsule root")
      Util.directory!(@root, "capsule root", mode: 0o700, owner: Process.euid)
      reject_forbidden_root!

      payload_path = File.join(@root, "v91-deployment-payload-manifest.json")
      Util.sidecar!(payload_path, payload_path + ".sha256", @external_payload_sha, "payload manifest")
      @payload = Util.strict_json(payload_path, Pins.fetch(:PAYLOAD_KEYS), Pins.fetch(:PAYLOAD_SCHEMA))
      validate_fixed_payload!
      resolve_payload_paths!
      validate_capsule_shape!

      Util.exact_file!(@paths.fetch(:source_tree_manifest), @payload.fetch("sourceTreeManifestSHA256"), "source tree manifest", mode: 0o600, owner: Process.euid)
      Util.exact_file!(@paths.fetch(:candidate_tree_manifest), @payload.fetch("candidateAppTreeManifestSHA256"), "candidate tree manifest", mode: 0o600, owner: Process.euid)
      Util.exact_file!(@paths.fetch(:candidate_copy_manifest), @payload.fetch("candidateAppCopyManifestSHA256"), "candidate copy manifest", mode: 0o600, owner: Process.euid)
      Util.directory!(@paths.fetch(:source), "source export", mode: 0o700, owner: Process.euid)
      Util.directory!(@paths.fetch(:candidate), "candidate app", mode: 0o755, owner: Process.euid)
      TreeManifest.new(@paths.fetch(:source), :source).verify!(@paths.fetch(:source_tree_manifest))
      TreeManifest.new(@paths.fetch(:candidate), :candidate).verify!(@paths.fetch(:candidate_tree_manifest))
      CopyManifest.new(@paths.fetch(:candidate)).verify!(@paths.fetch(:candidate_copy_manifest))

      validate_direct_bytes!
      validate_metadata!
      validate_handoff!
      validate_identity!
      LaunchContract.verify!(@paths.fetch(:launch_plist))
      true
    end

    def fingerprint
      @payload.values_at(*Pins.fetch(:PAYLOAD_KEYS)).join("\0")
    end

    private

    def reject_forbidden_root!
      forbidden = ["/Applications", Pins.fetch(:RUNTIME_ROOT)]
      lowered = @root.downcase
      Util.fail!("capsule is inside installed/protected runtime") if forbidden.any? do |prefix|
        lowered == prefix.downcase || lowered.start_with?(prefix.downcase + "/")
      end
    end

    def validate_fixed_payload!
      fixed = {
        "sourceCommit" => Pins.fetch(:SOURCE_COMMIT),
        "sourceTree" => Pins.fetch(:SOURCE_TREE),
        "sourceBranch" => Pins.fetch(:SOURCE_BRANCH),
        "sourceUpstream" => Pins.fetch(:SOURCE_UPSTREAM),
        "sourceExportRelativePath" => "source",
        "sourceTreeManifestRelativePath" => "v91-source-export-tree-manifest.txt",
        "candidateAppRelativePath" => "candidate/#{Pins.candidate_basename}",
        "candidateAppTreeManifestRelativePath" => "v91-candidate-app-tree-manifest.txt",
        "candidateAppCopyManifestRelativePath" => "v91-candidate-app-copy-manifest.txt",
        "candidateExecutableRelativePath" => "candidate/#{Pins.candidate_basename}/Contents/MacOS/CaptureServer",
        "candidateMediaFrameworkExecutableRelativePath" => "candidate/#{Pins.candidate_basename}/Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC",
        "candidateInfoPlistRelativePath" => "candidate/#{Pins.candidate_basename}/Contents/Info.plist",
        "candidateLaunchPlistRelativePath" => "deployment/org.example.opensteamer.worldwide.plist",
        "capsuleMetadataRelativePath" => "trusted-v91-host-oracle-capsule-metadata.json",
        "handoffRelativePath" => "v91-screen-oracle-handoff/v91-screen-oracle-host-identity-handoff.json",
        "hostIdentityManifestRelativePath" => "v91-screen-oracle-handoff/sealed-live-mac-host-identity.json",
        "designatedRequirementReferenceRelativePath" => "trusted-reference/CaptureServer",
        "designatedRequirementReferenceSHA256" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_SHA256),
        "designatedRequirementReferenceFileSize" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_FILE_SIZE).to_s,
        "designatedRequirementReferenceCodeSignatureDataOffset" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_CODE_SIGNATURE_DATA_OFFSET).to_s,
        "designatedRequirementReferenceCodeSignatureDataSize" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_CODE_SIGNATURE_DATA_SIZE).to_s,
        "designatedRequirementReferenceUnsignedPrefixSHA256" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_UNSIGNED_PREFIX_SHA256),
        "designatedRequirementReferenceCDHash" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_CDHASH),
        "designatedRequirementReferenceCodeDirectorySHA256" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_CODE_DIRECTORY_SHA256),
        "designatedRequirementReferenceTeamIdentifier" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_TEAM_ID),
        "designatedRequirementReferenceIdentifier" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_IDENTIFIER),
        "designatedRequirementReferenceDesignatedRequirement" => Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_DESIGNATED_REQUIREMENT),
        "toolingBranch" => Pins.fetch(:SOURCE_BRANCH),
        "toolingUpstream" => Pins.fetch(:SOURCE_UPSTREAM),
        "toolingRemoteURL" => "https://github.com/ahmedelami/opensteamer.git",
        "assemblerScriptRelativePath" => "macOS/scripts/assemble-v91-sealed-host-oracle-capsule.sh"
      }
      if Pins.contract
        fixed["assemblerScriptRelativePath"] = "macOS/scripts/import-prebuilt-host-successor.rb"
        fixed["successorProfileSHA256"] = Pins.contract.profile_sha
        fixed["artifactBuildEvidenceSHA256"] = Pins.contract.profile.fetch("candidate").fetch("buildEvidence").fetch("sha256")
        fixed["artifactBuildLogSHA256"] = Pins.contract.build_attestation.fetch("buildLog").fetch("sha256")
        Pins.contract.validate_payload_binding!(@payload)
      end
      fixed.each do |key, expected|
        Util.fail!("payload #{key} differs from fixed V91 contract") unless @payload.fetch(key) == expected
      end
      Pins.fetch(:PAYLOAD_KEYS).grep(/SHA256\z/).each { |key| Util.assert_sha!(@payload.fetch(key), "payload #{key}") }
      %w[toolingCommit toolingTree assemblerScriptGitBlob].each do |key|
        Util.fail!("payload #{key} is not a lowercase Git object id") unless @payload.fetch(key).match?(/\A[0-9a-f]{40}\z/)
      end
      @tooling = @tooling ? ToolingProof.verify_unchanged!(@tooling) : ToolingProof.verify!
      ToolingProof.verify_build_provenance!(@payload, @tooling)
      Util.assert_sha!(Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_SHA256), "compiled approved predecessor-reference digest")
      Util.fail!("predecessor reference lacks explicit compiled approval") unless
        @payload.fetch("designatedRequirementReferenceSHA256") == Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_SHA256)
      Util.fail!("payload handoff digest differs from external transport") unless @payload.fetch("handoffSHA256") == @external_handoff_sha
      Util.fail!("candidate launch plist is not byte-identical to pinned live contract") unless @payload.fetch("candidateLaunchPlistSHA256") == Pins.fetch(:LAUNCH_AGENT_SHA256)
    end

    def resolve_payload_paths!
      mapping = {
        source: "sourceExportRelativePath",
        source_tree_manifest: "sourceTreeManifestRelativePath",
        candidate: "candidateAppRelativePath",
        candidate_tree_manifest: "candidateAppTreeManifestRelativePath",
        candidate_copy_manifest: "candidateAppCopyManifestRelativePath",
        executable: "candidateExecutableRelativePath",
        framework: "candidateMediaFrameworkExecutableRelativePath",
        info_plist: "candidateInfoPlistRelativePath",
        launch_plist: "candidateLaunchPlistRelativePath",
        metadata: "capsuleMetadataRelativePath",
        handoff: "handoffRelativePath",
        identity: "hostIdentityManifestRelativePath",
        reference: "designatedRequirementReferenceRelativePath"
      }
      mapping.each { |name, key| @paths[name] = Util.inside(@root, @payload.fetch(key), "payload #{key}") }
      Util.fail!("source plist cannot be used as deployment plist") if @paths[:launch_plist].start_with?(@paths[:source] + "/")
    end

    def validate_capsule_shape!
      expected_top = [
        "candidate", "deployment", "source", "trusted-reference",
        "trusted-v91-host-oracle-capsule-metadata.json", "v91-candidate-app-tree-manifest.txt",
        "v91-candidate-app-copy-manifest.txt",
        "v91-deployment-payload-manifest.json", "v91-deployment-payload-manifest.json.sha256",
        "v91-screen-oracle-handoff", "v91-source-export-tree-manifest.txt"
      ]
      expected_top.concat(%w[prebuilt-build-evidence.txt prebuilt-build-log.txt]) if Pins.contract
      Util.fail!("capsule top-level names differ from strict layout") unless Dir.children(@root).sort == expected_top.sort
      {
        File.join(@root, "candidate") => [Pins.candidate_basename],
        File.join(@root, "deployment") => ["org.example.opensteamer.worldwide.plist"],
        File.join(@root, "trusted-reference") => ["CaptureServer"],
        File.join(@root, "v91-screen-oracle-handoff") => [
          "sealed-live-mac-host-identity.json",
          "sealed-live-mac-host-identity.json.sha256",
          "v91-screen-oracle-host-identity-handoff.json",
          "v91-screen-oracle-host-identity-handoff.json.sha256"
        ]
      }.each do |directory, children|
        Util.directory!(directory, "capsule layout directory", mode: 0o700, owner: Process.euid)
        Util.fail!("capsule directory contains unpinned names: #{directory}") unless Dir.children(directory).sort == children.sort
      end
    end

    def validate_direct_bytes!
      if Pins.contract
        Util.exact_file!(File.join(@root, "prebuilt-build-evidence.txt"),
                         @payload.fetch("artifactBuildEvidenceSHA256"), "prebuilt build evidence",
                         mode: 0o600, owner: Process.euid)
        Util.exact_file!(File.join(@root, "prebuilt-build-log.txt"),
                         @payload.fetch("artifactBuildLogSHA256"), "prebuilt build log",
                         mode: 0o600, owner: Process.euid)
      end
      {
        executable: "candidateExecutableSHA256",
        framework: "candidateMediaFrameworkExecutableSHA256",
        info_plist: "candidateInfoPlistSHA256",
        launch_plist: "candidateLaunchPlistSHA256",
        metadata: "capsuleMetadataSHA256",
        handoff: "handoffSHA256",
        identity: "hostIdentityManifestSHA256",
        reference: "designatedRequirementReferenceSHA256"
      }.each do |name, digest_key|
        expected = @payload.fetch(digest_key)
        mode = {
          executable: 0o755,
          framework: 0o755,
          info_plist: 0o644,
          launch_plist: 0o600,
          metadata: 0o600,
          handoff: 0o600,
          identity: 0o600,
          reference: 0o755
        }.fetch(name)
        Util.exact_file!(@paths.fetch(name), expected, name.to_s.tr("_", " "), mode: mode, owner: Process.euid)
      end
      Util.sidecar!(@paths.fetch(:handoff), @paths.fetch(:handoff) + ".sha256", @external_handoff_sha, "handoff")
      PredecessorReferenceFingerprint.verify!(@paths.fetch(:reference))
    end

    def validate_metadata!
      metadata = Util.strict_json(@paths.fetch(:metadata), Pins.fetch(:CAPSULE_KEYS), Pins.fetch(:CAPSULE_SCHEMA))
      cross = {
        "candidateAppRelativePath" => @payload.fetch("candidateAppRelativePath"),
        "candidateExecutableSHA256" => @payload.fetch("candidateExecutableSHA256"),
        "candidateMediaFrameworkExecutableSHA256" => @payload.fetch("candidateMediaFrameworkExecutableSHA256"),
        "designatedRequirementReferenceRelativePath" => @payload.fetch("designatedRequirementReferenceRelativePath"),
        "designatedRequirementReferenceSHA256" => @payload.fetch("designatedRequirementReferenceSHA256")
      }
      cross.each { |key, expected| Util.fail!("capsule metadata #{key} mismatch") unless metadata.fetch(key) == expected }
    end

    def validate_handoff!
      handoff = Util.strict_json(@paths.fetch(:handoff), Pins.fetch(:HANDOFF_KEYS), Pins.fetch(:HANDOFF_SCHEMA))
      expected = {
        "capsuleMetadataSHA256" => @payload.fetch("capsuleMetadataSHA256"),
        "candidateAppRelativePath" => @payload.fetch("candidateAppRelativePath"),
        "candidateExecutableSHA256" => @payload.fetch("candidateExecutableSHA256"),
        "candidateMediaFrameworkExecutableSHA256" => @payload.fetch("candidateMediaFrameworkExecutableSHA256"),
        "designatedRequirementReferenceRelativePath" => @payload.fetch("designatedRequirementReferenceRelativePath"),
        "designatedRequirementReferenceSHA256" => @payload.fetch("designatedRequirementReferenceSHA256"),
        "expectedTeamIdentifier" => Pins.fetch(:TEAM_ID),
        "hostIdentityManifestBasename" => File.basename(@paths.fetch(:identity)),
        "hostIdentityManifestSHA256" => @payload.fetch("hostIdentityManifestSHA256"),
        "hostIdentityManifestSHA256Basename" => File.basename(@paths.fetch(:identity)) + ".sha256"
      }
      expected.each { |key, value| Util.fail!("handoff #{key} mismatch") unless handoff.fetch(key) == value }
      Util.sidecar!(@paths.fetch(:identity), @paths.fetch(:identity) + ".sha256", @payload.fetch("hostIdentityManifestSHA256"), "host identity")
    end

    def validate_identity!
      identity = Util.strict_json(@paths.fetch(:identity), Pins.fetch(:IDENTITY_KEYS), Pins.fetch(:IDENTITY_SCHEMA))
      expected = {
        "executablePath" => Pins.fetch(:LIVE_EXECUTABLE),
        "executableSHA256" => @payload.fetch("candidateExecutableSHA256"),
        "executableIdentifier" => Pins.fetch(:EXECUTABLE_IDENTIFIER),
        "executableTeamIdentifier" => Pins.fetch(:TEAM_ID),
        "mediaFrameworkExecutablePath" => Pins.fetch(:LIVE_FRAMEWORK_IDENTITY_PATH),
        "mediaFrameworkExecutableSHA256" => @payload.fetch("candidateMediaFrameworkExecutableSHA256"),
        "mediaFrameworkExecutableIdentifier" => Pins.fetch(:FRAMEWORK_IDENTIFIER),
        "mediaFrameworkExecutableTeamIdentifier" => Pins.fetch(:TEAM_ID)
      }
      expected.each { |key, value| Util.fail!("host identity #{key} mismatch") unless identity.fetch(key) == value }
      %w[executableCDHash mediaFrameworkExecutableCDHash].each do |key|
        Util.fail!("host identity #{key} malformed") unless identity.fetch(key).match?(/\A[0-9a-f]{40}\z/)
      end
      @identity = identity
      Pins.contract.validate_payload_binding!(@payload, identity: identity) if Pins.contract
    end
  end

  class SessionFence
    Snapshot = Struct.new(:device, :inode, :size, :last_reset_offset, :digest, keyword_init: true)
    READ_CHUNK_BYTES = 1024 * 1024
    RESET_MARKERS = [
      "Worldwide availability is waiting for the paired iPhone",
      "Worldwide viewer disconnected",
      "Worldwide peer returned to idle",
      "Worldwide media ended; the Mac remains available for the paired iPhone"
    ].freeze
    UNSAFE_MARKERS = [
      "Worldwide authenticated media route selected",
      "Starting screen video capture",
      "peerConnected=true",
      "controlOpen=true"
    ].freeze
    STOP_MARKER = "Stopping screen video capture"

    def self.observe!(path, pid, nonce, prior: nil, fresh_generation: false)
      Util.fail!("fresh-generation session fence requires a prior snapshot") if
        fresh_generation && !prior
      stat = Util.regular_file!(path, "host stdout log", owner: Process.euid, links: 1)
      if prior
        Util.fail!("host stdout log was replaced") unless [stat.dev, stat.ino] == [prior.device, prior.inode]
        Util.fail!("host stdout log was truncated") if stat.size < prior.size
      end
      online = "Worldwide paired-device availability is online pid=#{pid} nonce=#{nonce}"
      markers = [online, *RESET_MARKERS, *UNSAFE_MARKERS, STOP_MARKER]
      overlap_bytes = markers.map(&:bytesize).max - 1
      offsets = {}
      digest = Digest::SHA256.new
      prefix_digest = Digest::SHA256.new if prior
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        opened = file.stat
        Util.fail!("host stdout log changed while opening") unless
          opened.file? && [opened.dev, opened.ino, opened.nlink] == [stat.dev, stat.ino, 1]
        observed_size = opened.size
        Util.fail!("host stdout log was truncated") if prior && observed_size < prior.size
        position = 0
        overlap = "".b
        while position < observed_size
          count = [READ_CHUNK_BYTES, observed_size - position].min
          chunk = file.pread(count, position)
          Util.fail!("host stdout log short read") unless chunk.bytesize == count
          digest.update(chunk)
          if prior && position < prior.size
            prefix_digest.update(chunk.byteslice(0, [count, prior.size - position].min))
          end
          window = overlap + chunk
          window_offset = position - overlap.bytesize
          markers.each do |marker|
            found = window.rindex(marker)
            offsets[marker] = window_offset + found if found
          end
          overlap = window.byteslice([window.bytesize - overlap_bytes, 0].max, overlap_bytes)
          position += count
        end
        after = File.lstat(path)
        Util.fail!("host stdout log changed while reading") unless
          after.file? && [after.dev, after.ino, after.nlink] == [opened.dev, opened.ino, 1] &&
          after.size >= observed_size
        stat = opened
      end
      if prior
        Util.fail!("host stdout log historical bytes changed") unless
          prefix_digest.hexdigest == prior.digest
      end
      online_offset = offsets[online]
      Util.fail!("host log lacks pinned generation availability marker") unless online_offset
      reset = RESET_MARKERS.map { |marker| offsets[marker] }.compact.max
      Util.fail!("host log has no quiescent-session boundary") unless reset
      if prior
        if fresh_generation
          Util.fail!("host lacks a fresh candidate quiescent-session boundary") unless
            reset >= prior.size
          Util.fail!("candidate availability marker precedes its fresh quiescent boundary") unless
            online_offset > reset
        else
          Util.fail!("host quiescent-session boundary changed") unless
            reset == prior.last_reset_offset
        end
      end
      Util.fail!("host has an authenticated/active peer after quiescent boundary") if
        UNSAFE_MARKERS.any? { |marker| offsets[marker] && offsets[marker] >= reset }
      start_offset = offsets["Starting screen video capture"]
      stop_offset = offsets[STOP_MARKER]
      Util.fail!("host screen remains active") if start_offset && start_offset >= reset &&
        (!stop_offset || start_offset > stop_offset)
      Snapshot.new(
        device: stat.dev,
        inode: stat.ino,
        size: stat.size,
        last_reset_offset: reset,
        digest: digest.hexdigest
      )
    rescue Errno::ELOOP, Errno::ENOENT, EOFError => error
      Util.fail!("host stdout log cannot be safely opened: #{error.message}")
    end
  end

  class Coordinator
    attr_reader :committed

    def initialize(host, capsule)
      @host = host
      @capsule = capsule
      @stop_intent = false
      @prepared = false
      @irreversible = false
      @committed = false
      @rollback_attempted = false
    end

    def preflight!
      @capsule.verify!
      @host.preflight!(@capsule)
      @host.preflight!(@capsule) # A second complete observation rejects unstable evidence.
      true
    end

    def execute!
      preflight!
      # Mark the prepare attempt before entering it so an asynchronous interrupt cannot land in
      # the otherwise-unobservable gap after prepare returns and strand its fresh namespace.
      @prepared = true
      @host.prepare!(@capsule)
      @capsule.verify! # Last transitive byte replay immediately precedes STOP_INTENT.
      @host.revalidate_immediately_before_stop!(@capsule)
      # Bind durable STOP_INTENT to the rollback latch. A deferred signal after this block must
      # take the exact-V90 rollback path, never the mutation-free pre-stop abort path.
      Thread.handle_interrupt(Interrupt => :never) do
        begin
          @host.journal!("STOP_INTENT")
        ensure
          # A full STOP_INTENT record observed after an fsync error is not success, but it is
          # enough to forbid the pre-stop deletion path. Recovery must follow the rollback graph.
          @stop_intent = true if @host.stop_intent_on_disk?
        end
      end
      @host.journal!("INSTALL_HOLDS_VERIFIED")
      @host.stop_predecessor!
      @host.hold_predecessor!
      @host.publish_candidate!
      @host.start_candidate!
      @host.verify_candidate_ready!
      @host.journal!("READY_VERIFIED")
      @host.journal!("COMMIT_INTENT")
      @host.prepare_irreversible_commit!
      # V91_COMMIT_IRREVERSIBLE is the durable point of no return. Signals are deferred until the
      # exact on-disk journal state and the in-memory no-rollback latch agree.
      Thread.handle_interrupt(Interrupt => :never) do
        @host.journal!("V91_COMMIT_IRREVERSIBLE")
        @irreversible = true
      end
      @host.finalize_postcommit!
      # COMMITTED_V91 is deliberately the last fallible success gate. It certifies final route
      # readback plus zero-notification monitor teardown, and is never followed by rollback.
      Thread.handle_interrupt(Interrupt => :never) do
        @host.journal!("COMMITTED_V91")
        @committed = true
      end
      true
    rescue Exception => original # rubocop:disable Lint/RescueException
      if @stop_intent && irreversible_or_indeterminate?
        @irreversible = true
        committed_but_unverified_after(original)
      end
      rollback_after(original) if @stop_intent && !@committed
      abort_before_stop_after(original) if @prepared && !@stop_intent
      raise
    end

    def interrupt!
      error = Failure.new("cutover interrupted")
      committed_but_unverified_after(error) if @stop_intent && irreversible_or_indeterminate?
      rollback_after(error) if @stop_intent && !@committed
      raise error
    end

    private

    def irreversible_or_indeterminate?
      return true if @irreversible
      @host.irreversible_on_disk?
    rescue Exception # rubocop:disable Lint/RescueException
      # If the authoritative journal inode cannot be read and reconciled after STOP_INTENT, the
      # controller cannot prove that the point of no return was not persisted. Destructive
      # rollback is therefore forbidden.
      true
    end

    def rollback_after(original)
      return if @rollback_attempted
      @rollback_attempted = true
      Thread.handle_interrupt(Interrupt => :never) { @host.rollback_exact_v90! }
    rescue Exception => rollback_error # rubocop:disable Lint/RescueException
      raise Failure, "#{original.message}; exact V90 rollback failed: #{rollback_error.message}"
    end

    def abort_before_stop_after(original)
      Thread.handle_interrupt(Interrupt => :never) { @host.abort_before_stop! }
    rescue Exception => cleanup_error # rubocop:disable Lint/RescueException
      raise Failure, "#{original.message}; exact pre-stop cleanup failed: #{cleanup_error.message}"
    end

    def committed_but_unverified_after(original)
      Thread.handle_interrupt(Interrupt => :never) do
        @host.record_committed_unverified!(original)
      end
      raise CommittedButUnverified,
            "#{original.message}; V91 crossed V91_COMMIT_IRREVERSIBLE and remains live; " \
            "commit safety proof is incomplete and exact-V90 rollback was intentionally forbidden"
    rescue CommittedButUnverified
      raise
    rescue Exception => evidence_error # rubocop:disable Lint/RescueException
      raise CommittedButUnverified,
            "#{original.message}; V91 crossed V91_COMMIT_IRREVERSIBLE and remains live; " \
            "committed-but-unverified evidence also failed: #{evidence_error.message}; rollback forbidden"
    end
  end

  # These are attribute-only lookups of the two product-owned pairing records. Raw
  # metadata remains in memory; neither password flags nor the legacy service are used.
  module PairingMetadata
    extend self

    SERVICE = "com.elamin.opensteamer.CaptureServer.WorldwidePairing.v1"
    ACCOUNTS = %w[worldwide-host-identity-v1 worldwide-paired-viewer-v1].freeze

    def observe!(runner: nil)
      runner ||= lambda do |arguments|
        Open3.capture3(
          { "HOME" => "/Users/ahmed", "USER" => "ahmed", "LOGNAME" => "ahmed",
            "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL" => "C" },
          "/usr/bin/security", *arguments, stdin_data: "", unsetenv_others: true
        )
      end
      digests = ACCOUNTS.each_with_index.map do |account, index|
        stdout, stderr, status = runner.call(
          ["find-generic-password", "-s", SERVICE, "-a", account]
        )
        Util.fail!("product pairing metadata lookup #{index + 1} failed") unless
          status.success? && !stdout.empty? && stderr.empty?
        Util.fail!("product pairing metadata is unexpectedly unbounded") unless stdout.bytesize <= 16_384
        Digest::SHA256.hexdigest(stdout.b)
      end
      { "schema" => "opensteamer.pairing-metadata-proof.v1", "count" => 2,
        "attributeDigests" => digests.freeze }.freeze
    end

    def assert_same!(before, after)
      Util.fail!("product pairing metadata changed during host update") unless before == after
      true
    end
  end

  class PredecessorRuntimeSnapshot
    attr_reader :pid, :runs, :start, :nonce, :files, :lock_directory, :lock_file

    def initialize(pid:, runs:, start:, nonce:, files:, lock_directory:, lock_file:)
      Util.fail!("predecessor process identity is malformed") unless
        pid.is_a?(Integer) && pid.positive? && runs.is_a?(Integer) && runs.positive? &&
        start.is_a?(String) && !start.empty? && !start.include?("\n") &&
        nonce.is_a?(String) && nonce.match?(/\A[0-9a-f]{64}\z/)
      expected_paths = Pins.fetch(:PREDECESSOR_IDENTITY_PATHS) + [Pins.fetch(:LAUNCH_AGENT)]
      Util.fail!("predecessor filesystem identity set differs") unless
        files.is_a?(Hash) && files.keys.sort == expected_paths.sort
      identities = files.values + [lock_directory, lock_file]
      Util.fail!("predecessor filesystem identity is malformed") unless identities.all? do |identity|
        identity.is_a?(Array) && identity.length == 3 &&
          identity[0].is_a?(Integer) && identity[0].positive? &&
          identity[1].is_a?(Integer) && identity[1].positive? &&
          %w[file directory].include?(identity[2])
      end
      Util.fail!("predecessor filesystem object types differ") unless
        files.fetch(Pins.fetch(:LIVE_APP))[2] == "directory" &&
        files.reject { |path, _| path == Pins.fetch(:LIVE_APP) }.values.all? { |identity| identity[2] == "file" } &&
        lock_directory[2] == "directory" && lock_file[2] == "file"
      @pid, @runs = pid, runs
      @start, @nonce = start.dup.freeze, nonce.dup.freeze
      @files = files.each_with_object({}) do |(path, identity), result|
        result[path.dup.freeze] = identity.map { |value| value.is_a?(String) ? value.dup.freeze : value }.freeze
      end.freeze
      @lock_directory = lock_directory.map { |value| value.is_a?(String) ? value.dup.freeze : value }.freeze
      @lock_file = lock_file.map { |value| value.is_a?(String) ? value.dup.freeze : value }.freeze
      freeze
    end

    def record
      {
        "schema" => "opensteamer.predecessor-runtime-snapshot.v1",
        "pid" => @pid, "runs" => @runs, "start" => @start, "nonce" => @nonce,
        "files" => @files, "lockDirectory" => @lock_directory, "lockFile" => @lock_file
      }
    end

    def assert_same!(other)
      Util.fail!("predecessor runtime changed during this deployment attempt") unless
        other.is_a?(PredecessorRuntimeSnapshot) && record == other.record
      true
    end

    def fresh_generation!(pid, nonce)
      Util.fail!("replacement process generation is not fresh") unless
        pid.is_a?(Integer) && pid.positive? && pid != @pid &&
        nonce.is_a?(String) && nonce.match?(/\A[0-9a-f]{64}\z/) && nonce != @nonce
      true
    end
  end

  class RealHost
    include Util

    SUCCESS_STATES = %w[
      BEGUN INPUTS_VERIFIED STOP_INTENT INSTALL_HOLDS_VERIFIED V90_STOPPED V90_HELD
      V91_PUBLISHED V91_BOOTSTRAPPED READY_VERIFIED COMMIT_INTENT
      V91_COMMIT_IRREVERSIBLE COMMITTED_V91
    ].freeze
    ROLLBACK_STATES = %w[
      ROLLBACK_STARTED V91_STOPPED FAILED_V91_ARCHIVED V90_RESTORED V90_BOOTSTRAPPED
      ROLLED_BACK_EXACT_V90
    ].freeze
    JOURNAL_TRANSITIONS = begin
      transitions = {
        nil => %w[BEGUN ABORTED_BEFORE_STOP],
        "BEGUN" => %w[INPUTS_VERIFIED ABORTED_BEFORE_STOP],
        "INPUTS_VERIFIED" => %w[STOP_INTENT ABORTED_BEFORE_STOP],
        "STOP_INTENT" => %w[INSTALL_HOLDS_VERIFIED ROLLBACK_STARTED],
        "INSTALL_HOLDS_VERIFIED" => %w[V90_STOPPED ROLLBACK_STARTED],
        "ROLLBACK_STARTED" => %w[V91_STOPPED],
        "V91_STOPPED" => %w[FAILED_V91_ARCHIVED],
        "FAILED_V91_ARCHIVED" => %w[V90_RESTORED],
        "V90_RESTORED" => %w[V90_BOOTSTRAPPED],
        "V90_BOOTSTRAPPED" => %w[ROLLED_BACK_EXACT_V90],
        "V91_COMMIT_IRREVERSIBLE" => %w[COMMITTED_V91 COMMITTED_V91_UNVERIFIED],
        "COMMITTED_V91" => %w[COMMITTED_V91_UNVERIFIED]
      }
      SUCCESS_STATES.each_cons(2) { |from, to| (transitions[from] ||= []) << to }
      %w[V90_STOPPED V90_HELD V91_PUBLISHED V91_BOOTSTRAPPED READY_VERIFIED COMMIT_INTENT].each do |from|
        (transitions[from] ||= []) << "ROLLBACK_STARTED"
      end
      transitions.transform_values!(&:freeze)
      transitions.freeze
    end

    def initialize
      @prepared = false
      @predecessor_stopped = false
      @candidate_installed = false
      @candidate_started = false
      @aborted = false
      @transaction = nil
      @journal = nil
      @session = nil
      @predecessor_runtime = nil
      @new_pid = nil
      @new_nonce = nil
      @route_monitor = nil
      @route_monitor_stopped = false
      @route_monitor_failure = nil
      @last_journal_state = nil
      @journal_io = nil
      @post_stop_helpers_root = nil
      @route_monitor_module_cache_path = nil
      @route_monitor_compiler_tmp_path = nil
      @update_root_created = false
      @predecessor_root_xattrs = nil
    end

    def preflight!(capsule)
      verify_retry_namespace_clean!
      verify_origins!
      verify_capsule_code!(capsule)
      @session = verify_live_v90!(@session)
      true
    end

    def prepare!(capsule)
      verify_retry_namespace_clean!
      create_owned_directory!(
        Pins.fetch(:V91_LOCK),
        0o700,
        "V91 runtime root after lock creation"
      ) { |identity| @lock_identity = identity }
      verify_retry_namespace_after_lock!
      if path_present?(Pins.fetch(:V91_UPDATE_ROOT))
        @update_root_identity = file_identity(Pins.fetch(:V91_UPDATE_ROOT))
        @update_root_created = false
      else
        create_owned_directory!(Pins.fetch(:V91_UPDATE_ROOT), 0o700, "new V91 history root") do |identity|
          @update_root_identity = identity
          @update_root_created = true
        end
        rollback_history.capture!
        @rollback_history_verified = true
      end
      transaction_name = "paired-#{Pins.release_name}-update-#{Time.now.to_i}-#{Process.pid}-#{SecureRandom.uuid}"
      @transaction = File.join(Pins.fetch(:V91_UPDATE_ROOT), transaction_name)
      create_owned_directory!(
        @transaction,
        0o700,
        "V91 update root after transaction creation"
      ) { |identity| @transaction_identity = identity }
      @journal = File.join(@transaction, "journal.log")
      write_durable(@journal, "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n", 0o600, exclusive: true) do |identity|
        @journal_identity = identity
      end
      journal!("BEGUN")
      persist_predecessor_runtime_snapshot!
      persist_pairing_metadata!("pairing-metadata-before.json")
      start_route_monitor!
      stage_post_stop_evidence!(capsule)
      publish_owned_pointer!(Pins.fetch(:V91_PENDING_POINTER), "#{@transaction}\n") do |identity|
        @pending_identity = identity
      end

      @token = SecureRandom.uuid
      @staged_root = "/Applications/.opensteamer-paired-#{Pins.release_name}-install-#{@token}"
      @staged_app = File.join(@staged_root, Pins.candidate_basename)
      @backup_app = "/Applications/.opensteamer-paired-#{Pins.release_name}-rollback-#{@token}.app"
      @failed_app = "/Applications/.opensteamer-paired-#{Pins.release_name}-failed-#{@token}.app"
      launch_parent = File.dirname(Pins.fetch(:LAUNCH_AGENT))
      @staged_plist = File.join(launch_parent, ".org.example.opensteamer.worldwide.#{Pins.release_name}-install-#{@token}.plist")
      @backup_plist = File.join(launch_parent, ".org.example.opensteamer.worldwide.#{Pins.release_name}-predecessor-rollback-#{@token}.plist")
      @failed_plist = File.join(launch_parent, ".org.example.opensteamer.worldwide.#{Pins.release_name}-failed-#{@token}.plist")
      verify_staged_install_layout!
      [@staged_root, @staged_app, @backup_app, @failed_app, @staged_plist, @backup_plist, @failed_plist].each do |path|
        Util.fail!("transaction staging name already exists") if File.exist?(path) || File.symlink?(path)
      end
      create_owned_directory!(
        @staged_root,
        0o700,
        "Applications directory after staged-root creation"
      ) { |identity| @staged_root_identity = identity }
      create_owned_directory!(
        @staged_app,
        0o755,
        "staged root after staged-app creation"
      ) { |identity| @staged_app_identity = identity }
      Dir.children(capsule.paths.fetch(:candidate)).each do |name|
        FileUtils.cp_r(File.join(capsule.paths.fetch(:candidate), name), @staged_app, preserve: true)
      end
      write_durable(
        @staged_plist,
        File.binread(capsule.paths.fetch(:launch_plist)),
        0o600,
        exclusive: true
      ) { |identity| @staged_plist_identity = identity }
      ensure_same_filesystem!(@staged_app, Pins.fetch(:LIVE_APP))
      ensure_same_filesystem!(@staged_plist, Pins.fetch(:LAUNCH_AGENT))
      durably_sync_staged_candidate!(capsule)
      route_monitor_clean!
      durably_sync_transaction_topology!
      journal!("INPUTS_VERIFIED")
      @prepared = true
    rescue Exception => original # rubocop:disable Lint/RescueException
      begin
        Thread.handle_interrupt(Interrupt => :never) { abort_before_stop! }
      rescue Exception => cleanup_error # rubocop:disable Lint/RescueException
        raise Failure, "#{original.message}; exact pre-stop cleanup failed: #{cleanup_error.message}"
      end
      raise
    end

    def revalidate_immediately_before_stop!(capsule)
      Util.fail!("transaction was not prepared") unless @prepared
      verify_retry_namespace_pre_stop!
      verify_origins!
      verify_capsule_code!(capsule)
      verify_post_stop_evidence!(capsule)
      verify_predecessor_runtime_snapshot_evidence!
      durably_sync_staged_candidate!(capsule)
      durably_sync_transaction_topology!
      # Gate before STOP_INTENT: a newly active viewer must abort without restarting the host.
      @session = verify_live_v90!(@session)
      route_monitor_clean!
      true
    end

    def journal!(state)
      Util.fail!("journal is unavailable") unless @journal
      prior_bytes = read_journal_bytes!
      prior_states = parse_journal_bytes!(prior_bytes)
      Util.fail!("journal memory/disk state diverged") unless prior_states.last == @last_journal_state
      allowed = JOURNAL_TRANSITIONS.fetch(@last_journal_state, [])
      Util.fail!("invalid journal transition #{@last_journal_state.inspect} -> #{state}") unless
        allowed.include?(state)
      line = "#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')} STATE #{Pins.state_out(state)}\n"
      @journal_io ||= File.open(@journal, File::RDWR | File::APPEND | File::NOFOLLOW)
      assert_open_identity!(@journal, @journal_io, "V91 journal")
      write_all!(@journal_io, line, "V91 journal #{state}")
      @journal_io.flush
      strict_fsync_io!(@journal_io, "V91 journal #{state}")
      Util.fail!("journal append bytes differ after fsync") unless read_journal_bytes! == prior_bytes + line
      Util.fail!("journal append topology differs after fsync") unless
        parse_journal_bytes!(read_journal_bytes!) == prior_states + [state]
      @last_journal_state = state
      true
    rescue Exception => error # rubocop:disable Lint/RescueException
      # The journal inode and its directory entry were made durable during prepare. If the exact
      # full record is observable after a write/fsync exception, conservatively accept it as the
      # state boundary. This prevents a durable point-of-no-return record from being followed by
      # rollback merely because an error was reported after persistence.
      current = @journal ? read_journal_bytes! : nil
      if current && prior_bytes && line && current == prior_bytes + line &&
         parse_journal_bytes!(current) == prior_states + [state]
        @last_journal_state = state
        raise JournalPersistenceUnverified,
              "#{state} record is complete but its fsync did not certify durability: #{error.message}"
      end
      if current && prior_bytes && line && current.start_with?(prior_bytes) &&
         line.start_with?(current.byteslice(prior_bytes.bytesize..-1).to_s)
        begin
          @journal_io.truncate(prior_bytes.bytesize)
          @journal_io.flush
          strict_fsync_io!(@journal_io, "V91 journal torn-record rollback")
          Util.fail!("journal torn-record rollback was not exact") unless read_journal_bytes! == prior_bytes
          Util.fail!("journal topology changed during torn-record rollback") unless
            parse_journal_bytes!(read_journal_bytes!) == prior_states
        rescue Exception => repair_error # rubocop:disable Lint/RescueException
          raise Failure,
                "#{error.message}; journal append is indeterminate and exact truncation failed: #{repair_error.message}"
        end
      end
      raise error
    end

    def stop_predecessor!
      route_monitor_clean!
      command!("/bin/launchctl", "bootout", Pins.fetch(:LAUNCH_LABEL))
      wait_until!(15, "predecessor did not stop cleanly") { runtime_absent? }
      verify_routes!
      route_monitor_clean!
      @predecessor_stopped = true
      journal!("V90_STOPPED")
    end

    def hold_predecessor!
      Util.fail!("predecessor is not stopped") unless @predecessor_stopped
      exclusive_rename(Pins.fetch(:LIVE_APP), @backup_app)
      exclusive_rename(Pins.fetch(:LAUNCH_AGENT), @backup_plist)
      route_monitor_clean!
      journal!("V90_HELD")
    end

    def publish_candidate!
      Util.fail!("V90 app/plist are not held") unless File.exist?(@backup_app) && File.exist?(@backup_plist)
      verify_staged_install_hold!
      exclusive_rename(@staged_app, Pins.fetch(:LIVE_APP))
      remove_staged_root_if_owned!
      exclusive_rename(@staged_plist, Pins.fetch(:LAUNCH_AGENT))
      @candidate_installed = true
      route_monitor_clean!
      journal!("V91_PUBLISHED")
    end

    def start_candidate!
      Util.fail!("candidate is not installed") unless @candidate_installed
      command!("/bin/launchctl", "bootstrap", "gui/501", Pins.fetch(:LAUNCH_AGENT))
      @candidate_started = true
      route_monitor_clean!
      journal!("V91_BOOTSTRAPPED")
    end

    def verify_candidate_ready!
      last_failure = nil
      begin
        wait_until!(90, "V91 host did not become ready", interval: 1.0) do
          begin
            establish_candidate_stability_baseline!
          rescue Failure => failure
            last_failure = failure
            false
          end
        end
      rescue Failure => failure
        detail = last_failure ? last_failure.message : "no readiness failure was captured"
        Util.fail!("#{failure.message}; last readiness failure: #{detail}")
      end
      run_candidate_stability_window!
      verify_pairing_metadata!
      true
    end

    def prepare_irreversible_commit!
      Util.fail!("candidate readiness was not established") unless @new_pid && @new_nonce
      result = <<~RESULT
        result=pending-terminal
        terminal_required=V91_COMMIT_IRREVERSIBLE,COMMITTED_V91
        pid=#{@new_pid}
        nonce=#{@new_nonce}
        target=v91
        selected=#{Pins.fetch(:LIVE_DISPLAY_MODE)}
        candidate_executable_sha256=#{@candidate_executable_sha}
        payload_manifest_sha256=#{@payload_sha}
        handoff_sha256=#{@handoff_sha}
      RESULT
      write_durable(File.join(@transaction, "result.txt"), Pins.record_out(result), 0o600, exclusive: true)
      publish_owned_pointer!(Pins.fetch(:V91_ACTIVE_POINTER), "#{@transaction}\n") do |identity|
        @active_pointer_identity = identity
      end
      remove_pending_pointer_if_owned!
      strict_fsync_directory!(Pins.fetch(:RUNTIME_ROOT), "V91 runtime root before commit decision")
      verify_candidate_stability_sample!
      verify_pairing_metadata!
      route_monitor_clean!
      true
    end

    def finalize_postcommit!
      Util.fail!("V91 commit is not irreversible") unless irreversible_on_disk?
      stop_route_monitor!
      verify_routes!
      verify_pairing_metadata!
      persist_pairing_metadata!("pairing-metadata-after-commit.json")
      result = <<~RESULT
        result=success-pending-terminal
        terminal_required=COMMITTED_V91
        point_of_no_return=V91_COMMIT_IRREVERSIBLE
        pid=#{@new_pid}
        nonce=#{@new_nonce}
        target=v91
        selected=#{Pins.fetch(:LIVE_DISPLAY_MODE)}
        candidate_executable_sha256=#{@candidate_executable_sha}
        payload_manifest_sha256=#{@payload_sha}
        handoff_sha256=#{@handoff_sha}
        route_monitor=#{Pins.fetch(:ROUTE_MONITOR_RESULT)}
      RESULT
      write_durable(
        File.join(@transaction, "commit-safety-proof.txt"),
        Pins.record_out(result),
        0o600,
        exclusive: true
      )
      verify_routes!
      remove_lock_if_owned!
      strict_fsync_directory!(Pins.fetch(:RUNTIME_ROOT), "V91 runtime root after irreversible commit proof")
      true
    end

    def irreversible_on_disk?
      return true if %w[V91_COMMIT_IRREVERSIBLE COMMITTED_V91 COMMITTED_V91_UNVERIFIED].include?(
        @last_journal_state
      )
      @journal ? journal_has_exact_terminal_record?("V91_COMMIT_IRREVERSIBLE", anywhere: true) : false
    end

    def stop_intent_on_disk?
      return true if @last_journal_state && @last_journal_state != "BEGUN" &&
                     @last_journal_state != "INPUTS_VERIFIED" &&
                     @last_journal_state != "ABORTED_BEFORE_STOP"
      @journal ? journal_has_exact_terminal_record?("STOP_INTENT", anywhere: true) : false
    end

    def record_committed_unverified!(original)
      return true if @committed_unverified_recorded
      errors = []
      attempt_cleanup(errors, "sticky monitor teardown") do
        stop_route_monitor!(allow_failure: true) if @route_monitor
        raise @route_monitor_failure if @route_monitor_failure
      end
      attempt_cleanup(errors, "final route readback") { verify_routes! }
      evidence = <<~RESULT
        result=committed-but-unverified
        point_of_no_return=V91_COMMIT_IRREVERSIBLE
        target=v91
        pid=#{@new_pid}
        nonce=#{@new_nonce}
        original_error=#{original.class}: #{original.message.to_s.gsub(/[\r\n]/, " ")}
        evidence_errors=#{errors.join(" | ").gsub(/[\r\n]/, " ")}
        rollback=forbidden
      RESULT
      write_durable(
        File.join(@transaction, "committed-but-unverified.txt"),
        Pins.record_out(evidence),
        0o600,
        exclusive: true
      )
      journal!("COMMITTED_V91_UNVERIFIED") unless @last_journal_state == "COMMITTED_V91_UNVERIFIED"
      @committed_unverified_recorded = true
      true
    end

    def abort_before_stop!
      return true if @aborted
      Util.fail!("cannot use pre-stop abort after predecessor stop") if @predecessor_stopped
      errors = []
      attempt_cleanup(errors, "abort journal") { journal!("ABORTED_BEFORE_STOP") if @journal && File.file?(@journal) }
      attempt_cleanup(errors, "route monitor teardown") do
        stop_route_monitor!(allow_failure: true) if @route_monitor
        raise @route_monitor_failure if @route_monitor_failure
      end
      attempt_cleanup(errors, "staged app") do
        remove_tree_exact!(@staged_app, @staged_app_identity) if @staged_app_identity && path_present?(@staged_app)
      end
      attempt_cleanup(errors, "staged root") { remove_staged_root_if_owned! }
      attempt_cleanup(errors, "staged plist") do
        unlink_exact!(@staged_plist, @staged_plist_identity) if @staged_plist_identity && path_present?(@staged_plist)
      end
      attempt_cleanup(errors, "pending pointer") { remove_pending_pointer_if_owned! }
      attempt_cleanup(errors, "journal descriptor") do
        @journal_io.close if @journal_io && !@journal_io.closed?
        @journal_io = nil
      end
      attempt_cleanup(errors, "transaction directory") do
        remove_tree_exact!(@transaction, @transaction_identity) if @transaction_identity && path_present?(@transaction)
      end
      attempt_cleanup(errors, "update root") do
        remove_new_update_root_if_owned!
      end
      attempt_cleanup(errors, "transaction lock") { remove_lock_if_owned! }
      attempt_cleanup(errors, "retained V91 retry baseline") { verify_retry_namespace_clean! }
      attempt_cleanup(errors, "runtime directory sync") do
        strict_fsync_directory!(Pins.fetch(:RUNTIME_ROOT), "V91 runtime root after abort")
      end
      @aborted = true
      Util.fail!("pre-stop cleanup errors: #{errors.join('; ')}") unless errors.empty?
      true
    end

    def remove_new_update_root_if_owned!(path: Pins.fetch(:V91_UPDATE_ROOT))
      return true unless @update_root_created && @update_root_identity
      Util.fail!("new update root acquired retained history") if @rollback_history &&
        (!@rollback_history.transactions.empty? || !@rollback_history.applications.empty? ||
         !@rollback_history.launch_agents.empty?)
      Util.fail!("new update root disappeared before owned cleanup") unless path_present?(path)
      Thread.handle_interrupt(Interrupt => :never) do
        remove_empty_directory_exact!(path, @update_root_identity)
        # Only our identity-proven empty root was removed. A retained history baseline
        # must never be discarded merely because its path disappeared or changed.
        @update_root_created = false
        @update_root_identity = nil
        @rollback_history = nil
        @rollback_history_verified = false
      end
      true
    end

    def rollback_exact_v90!
      journal!("ROLLBACK_STARTED") if @journal
      system("/bin/launchctl", "bootout", Pins.fetch(:LAUNCH_LABEL), out: File::NULL, err: File::NULL)
      wait_until!(15, "host did not become absent for rollback") { runtime_absent? }
      journal!("V91_STOPPED") if @journal
      archive_candidate_exact!(@staged_app_identity, [Pins.fetch(:LIVE_APP), @staged_app], @failed_app, "V91 app")
      archive_candidate_exact!(@staged_plist_identity, [Pins.fetch(:LAUNCH_AGENT), @staged_plist], @failed_plist, "V91 plist")
      journal!("FAILED_V91_ARCHIVED") if @journal
      restore_predecessor_exact!(
        Pins.fetch(:LIVE_APP),
        @backup_app,
        @predecessor_runtime.files.fetch(Pins.fetch(:LIVE_APP)),
        "V90 app"
      )
      restore_predecessor_exact!(
        Pins.fetch(:LAUNCH_AGENT),
        @backup_plist,
        @predecessor_runtime.files.fetch(Pins.fetch(:LAUNCH_AGENT)),
        "V90 plist"
      )
      verify_installed_v90_bytes!
      journal!("V90_RESTORED") if @journal
      command!("/bin/launchctl", "bootstrap", "gui/501", Pins.fetch(:LAUNCH_AGENT))
      journal!("V90_BOOTSTRAPPED") if @journal
      wait_until!(90, "exact V90 did not restart after rollback") do
        begin
          pid, runs = launch_identity
          record = strict_lock_record
          next false unless runs == 1 && pid.positive? && record.fetch(:pid) == pid
          @predecessor_runtime.fresh_generation!(pid, record.fetch(:nonce))
          @rollback_pid = pid
          @rollback_nonce = record.fetch(:nonce)
          verify_dynamic_process!(pid, expected_cdhash: Pins.fetch(:V90_CDHASH)) && verify_installed_v90_bytes!
        rescue Failure
          false
        end
      end
      restore_display_if_needed!
      wait_until!(15, "V90 display mode was not restored") { current_display_mode == Pins.fetch(:LIVE_DISPLAY_MODE) }
      31.times do
        verify_dynamic_process!(@rollback_pid, expected_cdhash: Pins.fetch(:V90_CDHASH))
        verify_installed_v90_bytes!
        retain_rollback_safety_failure { verify_routes! }
        route_monitor_clean!(allow_failure: true)
        Util.fail!("V90 host generation changed during rollback proof") unless
          strict_lock_record == { pid: @rollback_pid, nonce: @rollback_nonce }
        sleep 1
      end
      # The private install-hold root is auxiliary cleanup. Restore and prove V90 first so a
      # filesystem error removing this now-empty directory can never strand the host offline.
      remove_staged_root_if_owned!
      remove_provisional_active_pointer!
      remove_pending_pointer_if_owned!
      strict_fsync_directory!(Pins.fetch(:RUNTIME_ROOT), "V91 runtime root after rollback")
      route_monitor_clean!(allow_failure: true) if @route_monitor
      stop_route_monitor!(allow_failure: true) if @route_monitor
      retain_rollback_safety_failure { verify_routes! }
      if @route_monitor_failure
        Util.fail!("rollback route-monitor safety failure: #{@route_monitor_failure.message}")
      end
      verify_pairing_metadata!
      persist_pairing_metadata!("pairing-metadata-after-rollback.json")
      rollback_result = <<~RESULT
        result=pending-terminal
        terminal_required=ROLLED_BACK_EXACT_V90
        pid=#{@rollback_pid}
        nonce=#{@rollback_nonce}
        target=exact-v90
        selected=#{Pins.fetch(:LIVE_DISPLAY_MODE)}
      RESULT
      write_durable(
        File.join(@transaction, "rollback-result.txt"),
        Pins.record_out(rollback_result),
        0o600,
        exclusive: true
      )
      journal!("ROLLED_BACK_EXACT_V90") if @journal
      verify_owned_retry_lock!
      receipt = rollback_history.receipt_for(@transaction, @token)
      write_durable(
        File.join(@transaction, RollbackHistory::RECEIPT),
        JSON.generate(receipt) + "\n",
        0o600,
        exclusive: true
      )
      strict_fsync_directory!(@transaction, "completed rollback receipt")
      remove_lock_if_owned!
      strict_fsync_directory!(Pins.fetch(:RUNTIME_ROOT), "V91 runtime root after terminal receipt")
      true
    end

    private

    # These no-op hooks exist only so the offline self-test can hold the exact asynchronous-signal
    # windows open. Production subclasses never override them.
    def after_directory_create_before_identity!(_path)
      true
    end

    def after_file_create_before_identity!(_path)
      true
    end

    def set_durable_mode!(io, mode, label)
      io.chmod(mode)
      true
    rescue SystemCallError => error
      Util.fail!("#{label} chmod failed: #{error.message}")
    end

    def create_owned_directory!(path, mode, parent_label)
      identity = nil
      Thread.handle_interrupt(Interrupt => :never) do
        Dir.mkdir(path, mode)
        after_directory_create_before_identity!(path)
        identity = file_identity(path)
        yield identity if block_given?
        File.open(path, File::RDONLY | File::NOFOLLOW) do |directory|
          opened = directory.stat
          Util.fail!("owned directory changed while opening: #{path}") unless
            opened.directory? && [opened.dev, opened.ino, opened.ftype] == identity
          set_durable_mode!(directory, mode, "owned directory #{path}")
          strict_fsync_io!(directory, "owned directory #{path}")
        end
        assert_identity!(path, identity, "owned directory #{path}")
        Util.fail!("owned directory mode differs: #{path}") unless
          (File.lstat(path).mode & 0o7777) == mode
        strict_fsync_directory!(File.dirname(path), parent_label)
      end
      identity
    rescue SystemCallError => error
      Util.fail!("could not create durable owned directory #{path}: #{error.message}")
    end

    def write_all!(io, bytes, label)
      offset = 0
      while offset < bytes.bytesize
        written = io.write(bytes.byteslice(offset, bytes.bytesize - offset))
        Util.fail!("#{label} made no write progress") unless written && written.positive?
        offset += written
      end
      Util.fail!("#{label} short write") unless offset == bytes.bytesize
      true
    end

    def assert_open_identity!(path, io, label)
      path_stat = File.lstat(path)
      open_stat = io.stat
      Util.fail!("#{label} is not a regular file") unless path_stat.file? && open_stat.file?
      Util.fail!("#{label} open/path identity changed") unless
        [path_stat.dev, path_stat.ino, path_stat.nlink] == [open_stat.dev, open_stat.ino, 1]
      true
    end

    def strict_fsync_io!(io, label)
      io.fsync
      true
    rescue SystemCallError => error
      Util.fail!("#{label} fsync failed: #{error.message}")
    end

    def strict_fsync_directory!(path, label)
      flags = File::RDONLY | File::NOFOLLOW
      File.open(path, flags) do |directory|
        before = File.lstat(path)
        opened = directory.stat
        Util.fail!("#{label} is not a real directory") unless before.directory? && opened.directory?
        Util.fail!("#{label} open/path identity changed") unless
          [before.dev, before.ino] == [opened.dev, opened.ino]
        strict_fsync_io!(directory, label)
        after = File.lstat(path)
        Util.fail!("#{label} changed while syncing") unless
          after.directory? && [after.dev, after.ino] == [before.dev, before.ino]
      end
      true
    rescue Errno::ELOOP, Errno::ENOENT => error
      Util.fail!("#{label} cannot be safely opened: #{error.message}")
    end

    def strict_fsync_regular!(path, label)
      before = File.lstat(path)
      Util.fail!("#{label} is not a regular non-symlink file") unless before.file?
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        opened = file.stat
        Util.fail!("#{label} changed while opening") unless
          opened.file? && [opened.dev, opened.ino, opened.nlink, opened.size] ==
            [before.dev, before.ino, before.nlink, before.size]
        strict_fsync_io!(file, label)
        after = File.lstat(path)
        Util.fail!("#{label} changed while syncing") unless
          [after.dev, after.ino, after.nlink, after.size] ==
            [before.dev, before.ino, before.nlink, before.size]
      end
      true
    rescue Errno::ELOOP, Errno::ENOENT => error
      Util.fail!("#{label} cannot be safely opened: #{error.message}")
    end

    def durably_sync_tree!(root)
      root_stat = File.lstat(root)
      Util.fail!("staged candidate root is not a real directory") unless root_stat.directory?
      directories = []
      visit = lambda do |path|
        stat = File.lstat(path)
        Util.fail!("staged candidate crosses filesystems: #{path}") unless stat.dev == root_stat.dev
        if stat.directory?
          directories << path
          Dir.each_child(path) { |name| visit.call(File.join(path, name)) }
        elsif stat.file?
          strict_fsync_regular!(path, "staged candidate file #{path}")
        elsif stat.symlink?
          # Symlink target bytes are committed by fsyncing the containing directory. CopyManifest
          # independently constrains the exact five aliases and their targets.
          next
        else
          Util.fail!("staged candidate contains unsupported node: #{path}")
        end
      end
      visit.call(root)
      directories.sort_by { |path| -path.count(File::SEPARATOR) }.each do |directory|
        strict_fsync_directory!(directory, "staged candidate directory #{directory}")
      end
      true
    end

    def durably_sync_staged_candidate!(capsule)
      verify_staged_candidate!(capsule)
      durably_sync_tree!(@staged_app)
      strict_fsync_directory!(File.dirname(@staged_app), "staged candidate parent")
      strict_fsync_regular!(@staged_plist, "staged V91 launch plist")
      strict_fsync_directory!(File.dirname(@staged_plist), "staged launch-plist parent")
      verify_staged_candidate!(capsule)
      true
    end

    def durably_sync_transaction_topology!(
      runtime_root: Pins.fetch(:RUNTIME_ROOT),
      update_root: Pins.fetch(:V91_UPDATE_ROOT),
      lock_path: Pins.fetch(:V91_LOCK)
    )
      children = [
        [@post_stop_helpers_root, @post_stop_helpers_root_identity, "staged observer-tools directory"],
        [@route_monitor_module_cache_path, @route_monitor_module_cache_identity,
         "route-monitor module-cache directory"],
        [@route_monitor_compiler_tmp_path, @route_monitor_compiler_tmp_identity,
         "route-monitor compiler TMPDIR"]
      ]
      children.each do |path, identity, label|
        Util.fail!("#{label} identity was not recorded") unless path && identity
        Util.fail!("#{label} escaped the transaction") unless File.dirname(path) == @transaction
        assert_identity!(path, identity, label)
        strict_fsync_directory!(path, label)
      end

      Util.fail!("V91 transaction identity was not recorded") unless @transaction && @transaction_identity
      Util.fail!("V91 transaction escaped the update root") unless File.dirname(@transaction) == update_root
      assert_identity!(@transaction, @transaction_identity, "V91 transaction directory")
      strict_fsync_directory!(@transaction, "V91 transaction directory")

      Util.fail!("V91 update-root identity was not recorded") unless @update_root_identity
      Util.fail!("V91 update root has the wrong parent") unless File.dirname(update_root) == runtime_root
      assert_identity!(update_root, @update_root_identity, "V91 update root")
      strict_fsync_directory!(update_root, "V91 update root")

      Util.fail!("V91 lock identity was not recorded") unless @lock_identity
      Util.fail!("V91 lock has the wrong parent") unless File.dirname(lock_path) == runtime_root
      assert_identity!(lock_path, @lock_identity, "V91 transaction lock")
      strict_fsync_directory!(lock_path, "V91 transaction lock")

      strict_fsync_directory!(runtime_root, "V91 runtime root topology")
      true
    end

    def parse_journal_bytes!(bytes)
      lines = bytes.lines
      Util.fail!("V91 journal header is missing or malformed") unless
        lines.shift == "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n"
      prior = nil
      states = lines.map do |line|
        match = line.match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z STATE ([A-Z0-9_]+)\n\z/)
        Util.fail!("V91 journal contains a torn or malformed record") unless match
        state = Pins.state_in(match[1])
        Util.fail!("V91 journal contains an invalid state transition #{prior.inspect} -> #{state}") unless
          JOURNAL_TRANSITIONS.fetch(prior, []).include?(state)
        prior = state
        state
      end
      states
    end

    def read_journal_bytes!
      Util.fail!("journal is unavailable") unless @journal
      @journal_io ||= File.open(@journal, File::RDWR | File::APPEND | File::NOFOLLOW)
      @journal_identity ||= file_identity(@journal)
      assert_identity!(@journal, @journal_identity, "V91 journal path")
      assert_open_identity!(@journal, @journal_io, "V91 journal")
      @journal_io.flush
      size = @journal_io.stat.size
      size.zero? ? "" : @journal_io.pread(size, 0)
    end

    def journal_has_exact_terminal_record?(state, anywhere: false)
      states = parse_journal_bytes!(read_journal_bytes!)
      anywhere ? states.include?(state) : states.last == state
    end

    def publish_owned_pointer!(path, contents)
      parent = File.dirname(path)
      basename = File.basename(path)
      temporary = File.join(parent, ".#{basename}.#{Process.pid}.#{SecureRandom.uuid}.tmp")
      temp_identity = nil
      begin
        write_durable(temporary, contents, 0o600, exclusive: true) do |identity|
          temp_identity = identity
          yield identity if block_given?
        end
        assert_identity!(temporary, temp_identity, "temporary pointer")
        Util.fail!("temporary pointer bytes changed") unless File.binread(temporary) == contents
        Util.fail!("pointer destination already exists") if path_present?(path)
        exclusive_rename(temporary, path)
        assert_identity!(path, temp_identity, "published pointer")
        Util.fail!("published pointer bytes changed") unless File.binread(path) == contents
        strict_fsync_directory!(parent, "pointer parent")
        temp_identity
      rescue Exception => original # rubocop:disable Lint/RescueException
        Thread.handle_interrupt(Interrupt => :never) do
          final_owned = temp_identity && identity_matches?(path, temp_identity)
          temp_owned = temp_identity && identity_matches?(temporary, temp_identity)
          if final_owned
            Util.fail!("published pointer bytes are not exact after error") unless File.binread(path) == contents
            strict_fsync_directory!(parent, "pointer parent reconciliation")
            return temp_identity
          end
          if temp_owned
            actual = File.binread(temporary)
            Util.fail!("temporary pointer contains foreign bytes") unless contents.start_with?(actual)
            unlink_exact!(temporary, temp_identity)
          elsif path_present?(temporary)
            Util.fail!("unowned temporary pointer appeared")
          end
          Util.fail!("unowned pointer destination appeared") if path_present?(path)
        end
        raise original
      end
    end

    def file_identity(path)
      stat = File.lstat(path)
      [stat.dev, stat.ino, stat.ftype]
    rescue Errno::ENOENT
      Util.fail!("filesystem identity target is missing: #{path}")
    end

    def attempt_cleanup(errors, label)
      yield
    rescue Exception => error # rubocop:disable Lint/RescueException
      errors << "#{label}: #{error.message}"
      false
    end

    def retain_rollback_safety_failure
      yield
      true
    rescue Failure => error
      @route_monitor_failure ||= error
      false
    end

    def path_present?(path)
      File.lstat(path)
      true
    rescue Errno::ENOENT
      false
    end

    def identity_matches?(path, expected)
      return false unless expected && path && path_present?(path)
      actual = file_identity(path)
      actual[0, expected.length] == expected
    end

    def assert_identity!(path, expected, label)
      Util.fail!("#{label} filesystem identity changed") unless identity_matches?(path, expected)
      true
    end

    def unlink_exact!(path, identity, expected_contents: nil)
      return true unless path_present?(path)
      assert_identity!(path, identity, path)
      stat = File.lstat(path)
      Util.fail!("refusing to unlink non-file #{path}") unless stat.file? || stat.symlink?
      if expected_contents
        Util.fail!("owned file contents changed: #{path}") unless stat.file? && File.binread(path) == expected_contents
      end
      File.unlink(path)
      strict_fsync_directory!(File.dirname(path), "unlink parent")
      true
    end

    def remove_tree_exact!(path, identity)
      allowed = if path == @staged_app
                  verify_staged_install_layout!
                  @staged_root
                elsif path == @transaction
                  Pins.fetch(:V91_UPDATE_ROOT)
                end
      Util.fail!("refusing unapproved recursive cleanup target: #{path}") unless allowed && File.dirname(path) == allowed
      assert_identity!(path, identity, path)
      root = File.lstat(path)
      Util.fail!("recursive cleanup root is not a real directory: #{path}") unless root.directory?
      remove_tree_contents!(path, root.dev)
      Dir.rmdir(path)
      strict_fsync_directory!(File.dirname(path), "recursive cleanup parent")
      true
    end

    def verify_staged_install_layout!
      Util.fail!("V91 staging token is malformed") unless
        @token&.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
      expected_root = "/Applications/.opensteamer-paired-#{Pins.release_name}-install-#{@token}"
      expected_app = File.join(expected_root, Pins.candidate_basename)
      Util.fail!("V91 staged root escaped the exact install-hold namespace") unless
        @staged_root == expected_root && File.dirname(@staged_root) == File.dirname(Pins.fetch(:LIVE_APP))
      Util.fail!("V91 staged app lacks the production bundle basename") unless
        @staged_app == expected_app && File.basename(@staged_app) == Pins.candidate_basename
      true
    end

    def verify_staged_install_hold!
      verify_staged_install_layout!
      Util.fail!("V91 staged-root identity was not recorded") unless @staged_root_identity
      Util.fail!("V91 staged-app identity was not recorded") unless @staged_app_identity
      verify_private_install_hold!(
        @staged_root,
        @staged_app,
        @staged_root_identity,
        @staged_app_identity
      )
    end

    def verify_private_install_hold!(root, app, root_identity, app_identity)
      Util.directory!(root, "V91 staged root", mode: 0o700, owner: Process.euid)
      Util.directory!(app, "V91 staged app", mode: 0o755, owner: Process.euid)
      assert_identity!(root, root_identity, "V91 staged root")
      assert_identity!(app, app_identity, "V91 staged app")
      expected_basename = Pins.candidate_basename
      Util.fail!("V91 staged app escaped its private root") unless
        File.dirname(app) == root && File.basename(app) == expected_basename
      Util.fail!("V91 staged root contains unexpected entries") unless
        Dir.children(root) == [expected_basename]
      true
    end

    def remove_staged_root_if_owned!
      return true unless @staged_root_identity
      verify_staged_install_layout!
      remove_empty_directory_exact!(@staged_root, @staged_root_identity)
      @staged_root_identity = nil
      true
    end

    def remove_tree_contents!(directory, root_device)
      Dir.each_child(directory) do |name|
        Util.fail!("unsafe cleanup entry name") if name.match?(/[\x00-\x1f\x7f]/)
        child = File.join(directory, name)
        stat = File.lstat(child)
        Util.fail!("cleanup tree crosses filesystems: #{child}") unless stat.dev == root_device
        if stat.directory?
          remove_tree_contents!(child, root_device)
          Dir.rmdir(child)
        elsif stat.file? || stat.symlink?
          File.unlink(child)
        else
          Util.fail!("cleanup tree contains unsupported file type: #{child}")
        end
      end
    end

    def remove_empty_directory_exact!(path, identity)
      return true unless path_present?(path)
      assert_identity!(path, identity, path)
      Util.fail!("owned directory is not empty: #{path}") unless File.lstat(path).directory? && Dir.empty?(path)
      Dir.rmdir(path)
      strict_fsync_directory!(File.dirname(path), "directory removal parent")
      true
    end

    def remove_pending_pointer_if_owned!
      return true unless @pending_identity
      unlink_exact!(Pins.fetch(:V91_PENDING_POINTER), @pending_identity, expected_contents: "#{@transaction}\n")
      @pending_identity = nil
      true
    end

    def remove_lock_if_owned!
      return true unless @lock_identity
      remove_empty_directory_exact!(Pins.fetch(:V91_LOCK), @lock_identity)
      @lock_identity = nil
      true
    end

    def remove_provisional_active_pointer!
      if @active_pointer_identity
        unlink_exact!(Pins.fetch(:V91_ACTIVE_POINTER), @active_pointer_identity, expected_contents: "#{@transaction}\n")
        @active_pointer_identity = nil
      elsif path_present?(Pins.fetch(:V91_ACTIVE_POINTER))
        Util.fail!("unowned V91 active pointer appeared during rollback")
      end
      true
    end

    def archive_candidate_exact!(identity, locations, archive, label)
      Util.fail!("#{label} identity was not recorded") unless identity
      if identity_matches?(archive, identity)
        Util.fail!("#{label} appears in multiple locations") if locations.any? { |path| identity_matches?(path, identity) }
        return true
      end
      matches = locations.compact.select { |path| identity_matches?(path, identity) }
      Util.fail!("#{label} exact object is missing or duplicated") unless matches.length == 1
      Util.fail!("#{label} archive path already exists") if path_present?(archive)
      exclusive_rename(matches.first, archive)
      assert_identity!(archive, identity, "archived #{label}")
      true
    end

    def restore_predecessor_exact!(live, backup, expected_identity, label)
      live_matches = identity_matches?(live, expected_identity)
      backup_matches = identity_matches?(backup, expected_identity)
      Util.fail!("#{label} appears in both live and rollback locations") if live_matches && backup_matches
      if backup_matches
        Util.fail!("#{label} live destination is occupied") if path_present?(live)
        exclusive_rename(backup, live)
      elsif !live_matches
        Util.fail!("#{label} exact object is unavailable for rollback")
      end
      assert_identity!(live, expected_identity, label)
      true
    end

    def restore_display_if_needed!
      return true if current_display_mode == Pins.fetch(:LIVE_DISPLAY_MODE)
      selector = helper_path("select-live-display-mode-v23")
      command!(selector, Pins.fetch(:LIVE_DISPLAY_MODE))
      true
    end

    def verify_route_monitor_tools!
      Util.exact_file!(
        Pins.fetch(:ROUTE_MONITOR_SOURCE),
        Pins.fetch(:ROUTE_MONITOR_SOURCE_SHA256),
        "V91 route-monitor source",
        mode: 0o644,
        owner: Process.euid
      )
      compiler_link = File.lstat(Pins.fetch(:SWIFTC))
      Util.fail!("pinned swiftc path is not the reviewed symlink") unless
        compiler_link.symlink? && compiler_link.uid == Process.euid && compiler_link.nlink == 1 &&
        File.readlink(Pins.fetch(:SWIFTC)) == Pins.fetch(:SWIFTC_LINK_TARGET)
      compiler = File.realpath(Pins.fetch(:SWIFTC))
      compiler_stat = Util.regular_file!(compiler, "pinned swiftc executable", mode: 0o755, owner: Process.euid, links: 1)
      Util.fail!("pinned swiftc filesystem identity changed") unless
        [compiler_stat.dev, compiler_stat.ino] == Pins.fetch(:SWIFTC_IDENTITY)
      Util.fail!("pinned swiftc executable digest mismatch") unless Util.sha256(Pins.fetch(:SWIFTC)) == Pins.fetch(:SWIFTC_SHA256)
      sdk_link = File.lstat(Pins.fetch(:MACOS_SDK))
      Util.fail!("pinned macOS SDK path is not the reviewed symlink") unless
        sdk_link.symlink? && sdk_link.uid == Process.euid && sdk_link.nlink == 1 &&
        File.readlink(Pins.fetch(:MACOS_SDK)) == Pins.fetch(:MACOS_SDK_LINK_TARGET)
      sdk = File.realpath(Pins.fetch(:MACOS_SDK))
      sdk_stat = Util.directory!(sdk, "pinned macOS SDK", mode: 0o755, owner: Process.euid)
      Util.fail!("pinned macOS SDK filesystem identity changed") unless
        [sdk_stat.dev, sdk_stat.ino] == Pins.fetch(:MACOS_SDK_IDENTITY)
      Util.exact_file!(
        File.join(Pins.fetch(:MACOS_SDK), "SDKSettings.json"),
        Pins.fetch(:MACOS_SDK_SETTINGS_SHA256),
        "pinned macOS SDK settings",
        mode: 0o644,
        owner: Process.euid
      )
      true
    rescue Errno::ENOENT
      Util.fail!("pinned route-monitor compiler is missing")
    end

    def start_route_monitor!
      Util.fail!("route monitor already exists") if @route_monitor
      verify_routes!
      verify_route_monitor_tools!
      monitor_source = File.join(@transaction, "sticky-coreaudio-route-monitor.swift")
      binary = File.join(@transaction, "sticky-coreaudio-route-monitor")
      module_cache = File.join(@transaction, "sticky-coreaudio-module-cache")
      compiler_tmp = File.join(@transaction, "sticky-coreaudio-compiler-tmp")
      @route_monitor_module_cache_path = module_cache
      @route_monitor_compiler_tmp_path = compiler_tmp
      event_path = File.join(@transaction, "sticky-coreaudio-route-events.log")
      stdout_path = File.join(@transaction, "sticky-coreaudio-route-monitor.stdout")
      stderr_path = File.join(@transaction, "sticky-coreaudio-route-monitor.stderr")
      write_durable(
        monitor_source,
        File.binread(Pins.fetch(:ROUTE_MONITOR_SOURCE)),
        0o400,
        exclusive: true
      ) { |identity| @route_monitor_source_identity = identity }
      create_owned_directory!(
        module_cache,
        0o700,
        "V91 transaction after route-monitor module-cache creation"
      ) { |identity| @route_monitor_module_cache_identity = identity }
      create_owned_directory!(
        compiler_tmp,
        0o700,
        "V91 transaction after route-monitor TMPDIR creation"
      ) { |identity| @route_monitor_compiler_tmp_identity = identity }
      command_with_environment!(
        {
          "TMPDIR" => compiler_tmp,
          "CLANG_MODULE_CACHE_PATH" => module_cache,
          "SWIFT_MODULECACHE_PATH" => module_cache
        },
        Pins.fetch(:SWIFTC),
        "-sdk", Pins.fetch(:MACOS_SDK),
        "-module-cache-path", module_cache,
        monitor_source,
        "-O",
        "-framework", "CoreAudio",
        "-framework", "Foundation",
        "-o", binary
      )
      assert_identity!(module_cache, @route_monitor_module_cache_identity, "route-monitor module cache")
      assert_identity!(compiler_tmp, @route_monitor_compiler_tmp_identity, "route-monitor compiler TMPDIR")
      assert_identity!(monitor_source, @route_monitor_source_identity, "staged route-monitor source")
      Util.exact_file!(
        monitor_source,
        Pins.fetch(:ROUTE_MONITOR_SOURCE_SHA256),
        "staged route-monitor source",
        mode: 0o400,
        owner: Process.euid,
        links: 1
      )
      File.chmod(0o500, binary)
      binary_identity = file_identity(binary)
      Util.regular_file!(binary, "compiled V91 route monitor", mode: 0o500, owner: Process.euid, links: 1)
      command!("/usr/bin/codesign", "--verify", "--strict", "--verbose=1", binary)
      binary_sha = Util.sha256(binary)
      [event_path, stdout_path, stderr_path].each do |path|
        write_durable(path, "", 0o600, exclusive: true)
      end
      reader, writer = IO.pipe
      stdout_file = File.open(stdout_path, File::WRONLY | File::APPEND)
      stderr_file = File.open(stderr_path, File::WRONLY | File::APPEND)
      pid = Process.spawn(
        binary,
        event_path,
        "BlackHole2ch_UID",
        "BuiltInSpeakerDevice",
        "BuiltInSpeakerDevice",
        in: reader,
        out: stdout_file,
        err: stderr_file,
        close_others: true
      )
      reader.close
      stdout_file.close
      stderr_file.close
      @route_monitor = {
        pid: pid,
        stdin: writer,
        status: nil,
        source: monitor_source,
        source_identity: @route_monitor_source_identity,
        binary: binary,
        binary_identity: binary_identity,
        binary_sha: binary_sha,
        event: event_path,
        event_identity: file_identity(event_path),
        stdout: stdout_path,
        stdout_identity: file_identity(stdout_path),
        stderr: stderr_path,
        stderr_identity: file_identity(stderr_path)
      }
      wait_until!(15, "sticky CoreAudio monitor did not arm") do
        monitor_reap_nonblocking!
        Util.fail!("sticky CoreAudio monitor exited before READY") if @route_monitor[:status]
        File.binread(stdout_path) == "#{Pins.fetch(:ROUTE_MONITOR_READY)}\n"
      end
      route_monitor_clean!
      true
    rescue Exception # rubocop:disable Lint/RescueException
      writer.close if defined?(writer) && writer && !writer.closed?
      reader.close if defined?(reader) && reader && !reader.closed?
      stdout_file.close if defined?(stdout_file) && stdout_file && !stdout_file.closed?
      stderr_file.close if defined?(stderr_file) && stderr_file && !stderr_file.closed?
      raise
    end

    def monitor_reap_nonblocking!
      return @route_monitor[:status] if @route_monitor[:status]
      waited = Process.waitpid2(@route_monitor.fetch(:pid), Process::WNOHANG)
      @route_monitor[:status] = waited.last if waited
      @route_monitor[:status]
    rescue Errno::ECHILD
      @route_monitor[:status] || Util.fail!("sticky CoreAudio monitor wait identity was lost")
    end

    def verify_route_monitor_files!
      {
        source: [0o400, @route_monitor.fetch(:source_identity)],
        binary: [0o500, @route_monitor.fetch(:binary_identity)],
        event: [0o600, @route_monitor.fetch(:event_identity)],
        stdout: [0o600, @route_monitor.fetch(:stdout_identity)],
        stderr: [0o600, @route_monitor.fetch(:stderr_identity)]
      }.each do |name, (mode, identity)|
        path = @route_monitor.fetch(name)
        assert_identity!(path, identity, "route monitor #{name}")
        Util.regular_file!(path, "route monitor #{name}", mode: mode, owner: Process.euid, links: 1)
      end
      Util.fail!("staged route-monitor source bytes changed") unless
        Util.sha256(@route_monitor.fetch(:source)) == Pins.fetch(:ROUTE_MONITOR_SOURCE_SHA256)
      Util.fail!("compiled route-monitor bytes changed") unless
        Util.sha256(@route_monitor.fetch(:binary)) == @route_monitor.fetch(:binary_sha)
      true
    end

    def route_monitor_clean!(allow_failure: false)
      Util.fail!("sticky CoreAudio route monitor is unavailable") unless @route_monitor
      if @route_monitor_stopped
        raise @route_monitor_failure if @route_monitor_failure && !allow_failure
        return @route_monitor_failure.nil?
      end
      verify_route_monitor_files!
      monitor_reap_nonblocking!
      Util.fail!("sticky CoreAudio monitor exited prematurely") if @route_monitor[:status]
      Util.fail!("sticky CoreAudio route event was observed") unless File.zero?(@route_monitor.fetch(:event))
      Util.fail!("sticky CoreAudio monitor stderr is nonempty") unless File.zero?(@route_monitor.fetch(:stderr))
      Util.fail!("sticky CoreAudio monitor readiness proof changed") unless
        File.binread(@route_monitor.fetch(:stdout)) == "#{Pins.fetch(:ROUTE_MONITOR_READY)}\n"
      verify_routes!
      true
    rescue Failure => error
      raise unless allow_failure
      @route_monitor_failure ||= error
      false
    end

    def stop_route_monitor!(allow_failure: false)
      return true unless @route_monitor
      if @route_monitor_stopped
        raise @route_monitor_failure if @route_monitor_failure && !allow_failure
        return @route_monitor_failure.nil?
      end
      begin
        @route_monitor.fetch(:stdin).write("STOP\n")
        @route_monitor.fetch(:stdin).flush
      rescue IOError, Errno::EPIPE => error
        @route_monitor_failure ||= Failure.new("could not stop sticky CoreAudio monitor: #{error.message}")
      ensure
        @route_monitor.fetch(:stdin).close unless @route_monitor.fetch(:stdin).closed?
      end
      begin
        wait_until!(15, "sticky CoreAudio monitor did not stop") do
          !monitor_reap_nonblocking!.nil?
        end
      rescue Failure => error
        @route_monitor_failure ||= error
      end
      unless @route_monitor[:status]
        begin
          Process.kill("TERM", @route_monitor.fetch(:pid))
          wait_until!(3, "sticky CoreAudio monitor ignored TERM") do
            !monitor_reap_nonblocking!.nil?
          end
        rescue Failure, Errno::ESRCH => error
          @route_monitor_failure ||= Failure.new("forced route-monitor teardown failed: #{error.message}")
        end
      end
      unless @route_monitor[:status]
        begin
          Process.kill("KILL", @route_monitor.fetch(:pid))
          wait_until!(3, "sticky CoreAudio monitor ignored KILL") do
            !monitor_reap_nonblocking!.nil?
          end
        rescue Failure, Errno::ESRCH => error
          @route_monitor_failure ||= Failure.new("route-monitor reap failed: #{error.message}")
        end
      end
      begin
        verify_route_monitor_files!
        status = @route_monitor[:status]
        expected_stdout = "#{Pins.fetch(:ROUTE_MONITOR_READY)}\n#{Pins.fetch(:ROUTE_MONITOR_RESULT)}\n"
        Util.fail!("sticky CoreAudio monitor did not exit successfully") unless status&.success?
        Util.fail!("sticky CoreAudio route notifications were observed") unless File.zero?(@route_monitor.fetch(:event))
        Util.fail!("sticky CoreAudio monitor teardown emitted stderr") unless File.zero?(@route_monitor.fetch(:stderr))
        Util.fail!("sticky CoreAudio monitor proof mismatch") unless
          File.binread(@route_monitor.fetch(:stdout)) == expected_stdout
        verify_routes!
      rescue Failure => error
        @route_monitor_failure ||= error
      ensure
        @route_monitor_stopped = true
      end
      raise @route_monitor_failure if @route_monitor_failure && !allow_failure
      @route_monitor_failure.nil?
    end

    def verify_retry_namespace_clean!
      verify_rollback_history!
      verify_update_root_children!(rollback_history.transactions)
      verify_retry_prefix_names!(
        applications: rollback_history.applications,
        launch_agents: rollback_history.launch_agents
      )
      verify_no_pointer_temps!
      [Pins.fetch(:V91_PENDING_POINTER), Pins.fetch(:V91_ACTIVE_POINTER), Pins.fetch(:V91_LOCK)].each do |path|
        Util.fail!("V91 retry namespace contains an unexpected live artifact: #{path}") if
          path_present?(path)
      end
      true
    end

    def verify_retry_namespace_after_lock!
      verify_rollback_history!
      verify_update_root_children!(rollback_history.transactions)
      verify_retry_prefix_names!(
        applications: rollback_history.applications,
        launch_agents: rollback_history.launch_agents
      )
      verify_no_pointer_temps!
      [Pins.fetch(:V91_PENDING_POINTER), Pins.fetch(:V91_ACTIVE_POINTER)].each do |path|
        Util.fail!("V91 retry namespace contains an unexpected pointer: #{path}") if path_present?(path)
      end
      verify_owned_retry_lock!
      true
    end

    def verify_retry_namespace_pre_stop!
      verify_rollback_history!
      Util.fail!("current V91 transaction identity is unavailable") unless
        @transaction && @transaction_identity
      assert_identity!(@transaction, @transaction_identity, "current V91 transaction")
      verify_update_root_children!(rollback_history.transactions + [File.basename(@transaction)])
      verify_retry_prefix_names!(
        applications: rollback_history.applications + [File.basename(@staged_root)],
        launch_agents: rollback_history.launch_agents + [File.basename(@staged_plist)]
      )
      verify_no_pointer_temps!
      verify_owned_retry_lock!
      Util.fail!("V91 pending pointer identity is unavailable") unless @pending_identity
      assert_identity!(Pins.fetch(:V91_PENDING_POINTER), @pending_identity, "V91 pending pointer")
      Util.fail!("V91 pending pointer bytes changed") unless
        File.binread(Pins.fetch(:V91_PENDING_POINTER)) == "#{@transaction}\n"
      Util.fail!("V91 active pointer appeared before commit") if path_present?(Pins.fetch(:V91_ACTIVE_POINTER))
      true
    end

    def rollback_history
      @rollback_history ||= RollbackHistory.new(
        root: Pins.fetch(:V91_UPDATE_ROOT),
        application_parent: File.dirname(Pins.fetch(:LIVE_APP)),
        launch_parent: File.dirname(Pins.fetch(:LAUNCH_AGENT))
      )
    end

    def verify_rollback_history!
      return rollback_history.unchanged! if @rollback_history_verified
      if path_present?(Pins.fetch(:V91_UPDATE_ROOT))
        rollback_history.capture!
        @rollback_history_verified = true
      end
      true
    end

    def verify_retained_code_identity!(path, identifier, cdhash, label)
      metadata = combined_capture!("/usr/bin/codesign", "--display", "--verbose=4", path)
      identity = Util.exact_code_identity_values(metadata.b)
      Util.fail!("#{label} code identity changed") unless
        identity.fetch(:identifier) == [identifier] &&
        identity.fetch(:team_identifier) == [Pins.fetch(:TEAM_ID)] &&
        identity.fetch(:cdhash) == [cdhash]
      true
    end

    def verify_update_root_children!(expected)
      unless path_present?(Pins.fetch(:V91_UPDATE_ROOT))
        Util.fail!("V91 history disappeared") unless expected.empty?
        return true
      end
      actual = Dir.children(Pins.fetch(:V91_UPDATE_ROOT)).sort
      Util.fail!("V91 update-root children differ from exact retry allowlist") unless
        actual == expected.sort
      true
    end

    def verify_retry_prefix_names!(applications:, launch_agents:)
      application_names = Dir.children(File.dirname(Pins.fetch(:LIVE_APP))).select do |name|
        name.start_with?(".opensteamer-paired-#{Pins.release_name}-")
      end.sort
      launch_names = Dir.children(File.dirname(Pins.fetch(:LAUNCH_AGENT))).select do |name|
        name.start_with?(".org.example.opensteamer.worldwide.#{Pins.release_name}-")
      end.sort
      Util.fail!("V91 application retry namespace differs from exact allowlist") unless
        application_names == applications.sort
      Util.fail!("V91 launch-agent retry namespace differs from exact allowlist") unless
        launch_names == launch_agents.sort
      true
    end

    def verify_no_pointer_temps!
      pointer_temps = Dir.children(Pins.fetch(:RUNTIME_ROOT)).select do |name|
        name.start_with?(".#{File.basename(Pins.fetch(:V91_PENDING_POINTER))}.") ||
          name.start_with?(".#{File.basename(Pins.fetch(:V91_ACTIVE_POINTER))}.")
      end
      Util.fail!("V91 pointer temporary namespace is not empty") unless pointer_temps.empty?
      true
    end

    def verify_owned_retry_lock!
      Util.fail!("V91 transaction lock identity is unavailable") unless @lock_identity
      assert_identity!(Pins.fetch(:V91_LOCK), @lock_identity, "V91 transaction lock")
      lock_stat = Util.directory!(
        Pins.fetch(:V91_LOCK),
        "V91 transaction lock",
        mode: 0o700,
        owner: Process.euid
      )
      Util.fail!("V91 transaction lock group changed") unless lock_stat.gid == 20
      Util.fail!("V91 transaction lock is not empty") unless Dir.empty?(Pins.fetch(:V91_LOCK))
      true
    end

    def verify_origins!
      return Pins.contract.verify_baseline_evidence! if Pins.contract
      verify_pointer!(
        Pins.fetch(:V90_POINTER), Pins.fetch(:V90_POINTER_SHA256),
        Pins.fetch(:V90_EVIDENCE), Pins.fetch(:V90_EVIDENCE_IDENTITY), "committed V90"
      )
      exact = {
        "journal.log" => Pins.fetch(:V90_JOURNAL_SHA256),
        "result.txt" => Pins.fetch(:V90_RESULT_SHA256),
        "commit-safety-proof.txt" => Pins.fetch(:V90_COMMIT_PROOF_SHA256),
        "v90-candidate-app-copy-manifest.txt" => Pins.fetch(:V90_APP_MANIFEST_SHA256)
      }
      exact.each do |relative, sha|
        Util.exact_file!(File.join(Pins.fetch(:V90_EVIDENCE), relative), sha,
                         "committed V90 #{relative}", mode: 0o600, owner: 501)
      end
      Util.exact_file!(
        Pins.fetch(:V90_BUNDLE_VERIFIER_SOURCE),
        Pins.fetch(:V90_BUNDLE_VERIFIER_SHA256),
        "V90-compatible bundle verifier",
        mode: 0o755,
        owner: 501
      )
      verify_predecessor_commit_proof!(
        File.binread(File.join(Pins.fetch(:V90_EVIDENCE), "journal.log")),
        File.binread(File.join(Pins.fetch(:V90_EVIDENCE), "commit-safety-proof.txt"))
      )
      Pins.fetch(:V90_HELPERS).each do |relative, sha|
        path = File.join(Pins.fetch(:OBSERVER_EVIDENCE), relative)
        Util.exact_file!(path, sha, "trusted observer #{relative}", mode: 0o500, owner: 501)
      end
      true
    end

    def verify_predecessor_commit_proof!(journal, proof)
      Util.fail!("predecessor is not terminal committed V90") unless
        journal.lines.map(&:chomp).last == Pins.fetch(:V90_TERMINAL)
      records = proof.lines.map(&:chomp)
      required = [
        "result=success-pending-terminal",
        "terminal_required=COMMITTED_V90",
        "point_of_no_return=V90_COMMIT_IRREVERSIBLE",
        "target=v90",
        "selected=#{Pins.fetch(:LIVE_DISPLAY_MODE)}",
        "candidate_executable_sha256=#{Pins.fetch(:V90_EXECUTABLE_SHA256)}",
        "route_monitor=#{Pins.fetch(:ROUTE_MONITOR_RESULT)}"
      ]
      Util.fail!("committed V90 safety proof differs") unless
        required.all? { |line| records.count(line) == 1 } &&
        records.grep(/\Acandidate_executable_sha256=/).length == 1 &&
        records.grep(/\Aterminal_required=/).length == 1 &&
        records.grep(/\Aroute_monitor=/).length == 1
      true
    end

    def verify_pointer!(path, sha, evidence, identity, label)
      Util.exact_file!(path, sha, "#{label} pointer", mode: 0o600, owner: 501)
      Util.fail!("#{label} pointer targets unpinned evidence") unless File.binread(path) == "#{evidence}\n"
      stat = Util.directory!(evidence, "#{label} evidence", mode: 0o700, owner: 501)
      Util.fail!("#{label} evidence identity changed") unless [stat.dev, stat.ino] == identity
    end

    def verify_capsule_code!(capsule)
      @capsule_root = capsule.root
      @candidate_executable_sha = capsule.payload.fetch("candidateExecutableSHA256")
      @candidate_framework_sha = capsule.payload.fetch("candidateMediaFrameworkExecutableSHA256")
      @candidate_info_sha = capsule.payload.fetch("candidateInfoPlistSHA256")
      @candidate_plist_sha = capsule.payload.fetch("candidateLaunchPlistSHA256")
      @candidate_cdhash = capsule.identity.fetch("executableCDHash")
      @capsule_candidate_copy_manifest = capsule.paths.fetch(:candidate_copy_manifest)
      @reference_path = capsule.paths.fetch(:reference)
      @payload_sha = Util.sha256(File.join(capsule.root, "v91-deployment-payload-manifest.json"))
      @handoff_sha = capsule.payload.fetch("handoffSHA256")
      verifier = File.join(capsule.root, "source", Pins.candidate_verifier_relative)
      command_with_environment!({ "OPENSTEAMER_EXPECTED_ARCHITECTURES" => "arm64" }, verifier, *Pins.candidate_verifier_flags, capsule.paths.fetch(:candidate), Pins.fetch(:TEAM_ID), capsule.paths.fetch(:reference))
      true
    end

    def stage_post_stop_evidence!(capsule)
      if Pins.contract
        Pins.contract.verify_baseline_evidence!
        {
          "successor-profile.json" => [Pins.contract.profile_path, Pins.contract.profile_sha],
          "reviewed-current-baseline.json" => Pins.contract.profile.fetch("baseline").values_at("path", "sha256")
        }.each do |name, (source, digest)|
          destination = File.join(@transaction, name)
          write_durable(destination, File.binread(source), 0o600, exclusive: true)
          Util.exact_file!(destination, digest, name, mode: 0o600, owner: Process.euid)
        end
      end
      observer = ToolingProof.readiness_observer!(capsule.tooling)
      @post_stop_readiness_sha = observer.fetch("readinessScriptSHA256")
      @post_stop_tooling_provenance = observer.reject { |key, _| key == "bytes" }.merge(
        "schema" => "opensteamer.host-cutover-tooling-provenance.v1",
        (Pins.contract ? "artifactSealToolingCommit" : "artifactBuildToolingCommit") => capsule.payload.fetch("toolingCommit"),
        (Pins.contract ? "artifactSealToolingTree" : "artifactBuildToolingTree") => capsule.payload.fetch("toolingTree"),
        "artifactAssemblerScriptGitBlob" => capsule.payload.fetch("assemblerScriptGitBlob")
      )
      @post_stop_tooling_receipt = File.join(@transaction, "v91-deployment-tooling.json")
      receipt = JSON.pretty_generate(@post_stop_tooling_provenance) + "\n"
      @post_stop_tooling_receipt_sha = Digest::SHA256.hexdigest(receipt)
      write_durable(@post_stop_tooling_receipt, receipt, 0o600, exclusive: true) do |identity|
        @post_stop_tooling_receipt_identity = identity
      end
      @post_stop_readiness = File.join(@transaction, "verify-v91-secondary-viewer-readiness.sh")
      write_durable(
        @post_stop_readiness,
        observer.fetch("bytes"),
        Pins.fetch(:READINESS_STAGED_MODE),
        exclusive: true
      ) { |identity| @post_stop_readiness_identity = identity }

      @post_stop_copy_manifest = File.join(@transaction, "v91-candidate-app-copy-manifest.txt")
      write_durable(
        @post_stop_copy_manifest,
        File.binread(capsule.paths.fetch(:candidate_copy_manifest)),
        0o600,
        exclusive: true
      ) { |identity| @post_stop_copy_manifest_identity = identity }

      @post_stop_reference = File.join(@transaction, "approved-predecessor-reference-CaptureServer")
      write_durable(
        @post_stop_reference,
        File.binread(capsule.paths.fetch(:reference)),
        0o755,
        exclusive: true
      ) { |identity| @post_stop_reference_identity = identity }
      helpers_root = File.join(@transaction, "pinned-v90-observer-tools")
      @post_stop_helpers_root = helpers_root
      create_owned_directory!(
        helpers_root,
        0o700,
        "V91 transaction after observer-tools creation"
      ) { |identity| @post_stop_helpers_root_identity = identity }
      @post_stop_helpers = {}
      Pins.fetch(:V90_HELPERS).each do |name, digest|
        source = File.join(Pins.fetch(:OBSERVER_EVIDENCE), name)
        destination = File.join(helpers_root, name)
        identity = nil
        write_durable(destination, File.binread(source), 0o500, exclusive: true) do |created_identity|
          identity = created_identity
        end
        @post_stop_helpers[name] = { path: destination, identity: identity, digest: digest }
      end
      @post_stop_v90_verifier = File.join(helpers_root, "verify-v90-mac-host-bundle.sh")
      write_durable(
        @post_stop_v90_verifier,
        File.binread(Pins.fetch(:V90_BUNDLE_VERIFIER_SOURCE)),
        0o500,
        exclusive: true
      ) { |identity| @post_stop_v90_verifier_identity = identity }
      @post_stop_v90_manifest = File.join(@transaction, "v90-predecessor-app-copy-manifest.txt")
      write_durable(
        @post_stop_v90_manifest,
        File.binread(Pins.fetch(:V90_COMMITTED_COPY_MANIFEST)),
        0o600,
        exclusive: true
      ) { |identity| @post_stop_v90_manifest_identity = identity }
      verify_post_stop_evidence!(capsule)
      true
    end

    def verify_post_stop_evidence!(capsule)
      if Pins.contract
        {
          "successor-profile.json" => Pins.contract.profile_sha,
          "reviewed-current-baseline.json" => Pins.contract.profile.fetch("baseline").fetch("sha256")
        }.each do |name, digest|
          Util.exact_file!(File.join(@transaction, name), digest, name, mode: 0o600, owner: Process.euid)
        end
      end
      observer = ToolingProof.readiness_observer!(capsule.tooling)
      observer.reject { |key, _| key == "bytes" }.each do |key, value|
        Util.fail!("deployment readiness provenance changed: #{key}") unless
          @post_stop_tooling_provenance.fetch(key) == value
      end
      assert_identity!(
        @post_stop_tooling_receipt,
        @post_stop_tooling_receipt_identity,
        "deployment tooling provenance"
      )
      Util.exact_file!(
        @post_stop_tooling_receipt,
        @post_stop_tooling_receipt_sha,
        "deployment tooling provenance",
        mode: 0o600,
        owner: Process.euid
      )
      assert_identity!(@post_stop_readiness, @post_stop_readiness_identity, "staged V91 readiness observer")
      Util.exact_file!(
        @post_stop_readiness,
        @post_stop_readiness_sha,
        "staged V91 readiness observer",
        mode: Pins.fetch(:READINESS_STAGED_MODE),
        owner: Process.euid
      )
      copy_sha = capsule.payload.fetch("candidateAppCopyManifestSHA256")
      Util.exact_file!(
        capsule.paths.fetch(:candidate_copy_manifest),
        copy_sha,
        "capsule candidate copy manifest",
        mode: 0o600,
        owner: Process.euid
      )
      assert_identity!(@post_stop_copy_manifest, @post_stop_copy_manifest_identity, "staged candidate copy manifest")
      Util.exact_file!(
        @post_stop_copy_manifest,
        copy_sha,
        "staged candidate copy manifest",
        mode: 0o600,
        owner: Process.euid
      )
      reference_sha = capsule.payload.fetch("designatedRequirementReferenceSHA256")
      Util.exact_file!(
        capsule.paths.fetch(:reference),
        reference_sha,
        "capsule predecessor reference",
        mode: 0o755,
        owner: Process.euid
      )
      assert_identity!(@post_stop_reference, @post_stop_reference_identity, "staged predecessor reference")
      Util.exact_file!(
        @post_stop_reference,
        reference_sha,
        "staged predecessor reference",
        mode: 0o755,
        owner: Process.euid
      )
      PredecessorReferenceFingerprint.verify!(
        capsule.paths.fetch(:reference),
        label: "capsule predecessor reference"
      )
      PredecessorReferenceFingerprint.verify!(
        @post_stop_reference,
        label: "staged predecessor reference"
      )
      Pins.fetch(:V90_HELPERS).each do |name, digest|
        source = File.join(Pins.fetch(:OBSERVER_EVIDENCE), name)
        Util.exact_file!(source, digest, "V90 helper #{name}", mode: 0o500, owner: Process.euid)
        staged = @post_stop_helpers.fetch(name)
        assert_identity!(staged.fetch(:path), staged.fetch(:identity), "staged V90 helper #{name}")
        Util.exact_file!(
          staged.fetch(:path),
          digest,
          "staged V90 helper #{name}",
          mode: 0o500,
          owner: Process.euid
        )
      end
      Util.exact_file!(
        Pins.fetch(:V90_BUNDLE_VERIFIER_SOURCE),
        Pins.fetch(:V90_BUNDLE_VERIFIER_SHA256),
        "V90-compatible bundle verifier",
        mode: 0o755,
        owner: Process.euid
      )
      Util.exact_file!(
        Pins.fetch(:V90_COMMITTED_COPY_MANIFEST),
        Pins.fetch(:V90_APP_MANIFEST_SHA256),
        "committed V90 app copy manifest",
        mode: 0o600,
        owner: Process.euid
      )
      assert_identity!(
        @post_stop_v90_verifier,
        @post_stop_v90_verifier_identity,
        "staged V90-compatible bundle verifier"
      )
      Util.exact_file!(
        @post_stop_v90_verifier,
        Pins.fetch(:V90_BUNDLE_VERIFIER_SHA256),
        "staged V90-compatible bundle verifier",
        mode: 0o500,
        owner: Process.euid
      )
      assert_identity!(
        @post_stop_v90_manifest,
        @post_stop_v90_manifest_identity,
        "staged committed V90 app copy manifest"
      )
      Util.exact_file!(
        @post_stop_v90_manifest,
        Pins.fetch(:V90_APP_MANIFEST_SHA256),
        "staged committed V90 app copy manifest",
        mode: 0o600,
        owner: Process.euid
      )
      true
    end

    def helper_path(name)
      staged = @post_stop_helpers && @post_stop_helpers[name]
      staged ? staged.fetch(:path) : File.join(Pins.fetch(:OBSERVER_EVIDENCE), name)
    end

    def verify_live_v90!(prior_session)
      observed = capture_predecessor_runtime_snapshot!
      @predecessor_runtime.assert_same!(observed) if @predecessor_runtime
      verify_installed_v90_bytes!
      verify_dynamic_process!(observed.pid, expected_start: observed.start, expected_cdhash: Pins.fetch(:V90_CDHASH))
      verify_routes!
      verify_pairing_metadata!
      Util.fail!("live display selection differs from pinned V90") unless current_display_mode == Pins.fetch(:LIVE_DISPLAY_MODE)
      session = observe_predecessor_session!(observed, prior_session)
      observed.assert_same!(capture_predecessor_runtime_snapshot!)
      @predecessor_runtime ||= observed
      session
    end

    def verify_pairing_metadata!
      observed = PairingMetadata.observe!
      PairingMetadata.assert_same!(@pairing_metadata, observed) if @pairing_metadata
      @pairing_metadata ||= observed
      true
    end

    def persist_pairing_metadata!(basename)
      Util.fail!("pairing metadata baseline was not established") unless @pairing_metadata
      Util.fail!("pairing metadata evidence name is not allowed") unless
        %w[pairing-metadata-before.json pairing-metadata-after-commit.json pairing-metadata-after-rollback.json].include?(basename)
      write_durable(File.join(@transaction, basename), JSON.generate(@pairing_metadata) + "\n", 0o600, exclusive: true)
    end

    def capture_predecessor_runtime_snapshot!
      pid, runs = launch_identity
      start = Util.capture!("/bin/ps", "-p", pid.to_s, "-o", "lstart=").split.join(" ")
      lock = strict_lock_record
      Util.fail!("predecessor launch and generation-lock PIDs differ") unless lock.fetch(:pid) == pid
      files = (Pins.fetch(:PREDECESSOR_IDENTITY_PATHS) + [Pins.fetch(:LAUNCH_AGENT)]).each_with_object({}) do |path, result|
        result[path] = file_identity(path)
      end
      PredecessorRuntimeSnapshot.new(
        pid: pid, runs: runs, start: start, nonce: lock.fetch(:nonce), files: files,
        lock_directory: file_identity(File.dirname(Pins.fetch(:LIVE_LOCK_PATH))),
        lock_file: file_identity(Pins.fetch(:LIVE_LOCK_PATH))
      )
    end

    def observe_predecessor_session!(runtime, prior)
      SessionFence.observe!(Pins.fetch(:LAUNCH_STDOUT), runtime.pid, runtime.nonce, prior: prior)
    end

    def persist_predecessor_runtime_snapshot!
      Util.fail!("verified predecessor runtime snapshot is missing") unless @predecessor_runtime
      @predecessor_snapshot_path = File.join(@transaction, "predecessor-runtime-snapshot.json")
      contents = JSON.generate(@predecessor_runtime.record) + "\n"
      @predecessor_snapshot_sha = Util.sha256_text(contents)
      write_durable(@predecessor_snapshot_path, contents, 0o600, exclusive: true)
      verify_predecessor_runtime_snapshot_evidence!
    end

    def verify_predecessor_runtime_snapshot_evidence!
      Util.fail!("predecessor runtime evidence was not recorded") unless
        @predecessor_runtime && @predecessor_snapshot_path && @predecessor_snapshot_sha
      Util.exact_file!(
        @predecessor_snapshot_path, @predecessor_snapshot_sha,
        "predecessor runtime snapshot", mode: 0o600, owner: Process.euid
      )
      Util.fail!("predecessor runtime evidence differs from this invocation") unless
        File.binread(@predecessor_snapshot_path) == JSON.generate(@predecessor_runtime.record) + "\n"
      true
    end

    def verify_installed_v90_bytes!
      if @predecessor_runtime
        @predecessor_runtime.files.each do |path, expected|
          assert_identity!(path, expected, "live V90 #{path}")
        end
      end
      Util.exact_file!(Pins.fetch(:LIVE_EXECUTABLE), Pins.fetch(:V90_EXECUTABLE_SHA256), "live V90 executable", mode: 0o755, owner: 501)
      Util.exact_file!(Pins.fetch(:LIVE_FRAMEWORK), Pins.fetch(:V90_FRAMEWORK_SHA256), "live V90 framework", mode: 0o755, owner: 501)
      Util.exact_file!(Pins.fetch(:LIVE_INFO_PLIST), Pins.fetch(:V90_INFO_PLIST_SHA256), "live V90 Info.plist", mode: 0o644, owner: 501)
      Util.exact_file!(Pins.fetch(:LAUNCH_AGENT), Pins.fetch(:LAUNCH_AGENT_SHA256), "live V90 launch plist", mode: 0o600, owner: 501)
      LaunchContract.verify!(Pins.fetch(:LAUNCH_AGENT))
      verifier, verifier_mode = v90_bundle_verifier
      manifest, manifest_mode = v90_copy_manifest
      reference = v90_reference
      @predecessor_root_xattrs ||= CopyManifest.capture_published_root_xattrs!(Pins.fetch(:LIVE_APP))
      verify_v90_bundle_contract!(
        app: Pins.fetch(:LIVE_APP),
        verifier: verifier,
        verifier_sha: Pins.fetch(:V90_BUNDLE_VERIFIER_SHA256),
        verifier_mode: verifier_mode,
        manifest: manifest,
        manifest_sha: Pins.fetch(:V90_APP_MANIFEST_SHA256),
        manifest_mode: manifest_mode,
        reference: reference,
        reference_sha: Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_SHA256),
        reference_mode: 0o755,
        allowed_root_xattrs: @predecessor_root_xattrs
      )
      metadata = combined_capture!("/usr/bin/codesign", "--display", "--verbose=4", Pins.fetch(:LIVE_EXECUTABLE))
      Util.fail!("live V90 code identifier mismatch") unless
        Util.exact_prefixed_values(metadata, "Identifier=") == [Pins.fetch(:EXECUTABLE_IDENTIFIER)]
      Util.fail!("live V90 TeamIdentifier mismatch") unless
        Util.exact_prefixed_values(metadata, "TeamIdentifier=") == [Pins.fetch(:TEAM_ID)]
      cdhashes = Util.exact_prefixed_values(metadata, "CDHash=")
      Util.fail!("live V90 CDHash mismatch") unless
        cdhashes.length == 1 && cdhashes.first.match?(/\A[0-9A-Fa-f]+\z/n) &&
          cdhashes.first.downcase == Pins.fetch(:V90_CDHASH)
      requirement_output = combined_capture!("/usr/bin/codesign", "--display", "--requirements", "-", Pins.fetch(:LIVE_EXECUTABLE))
      requirement = requirement_output.b.lines.map { |line| line.strip.sub(/\A# /n, "") }
                                      .find { |line| line.start_with?("designated =>") }
      Util.fail!("live V90 designated requirement mismatch") unless requirement == "designated => #{Pins.fetch(:V90_DESIGNATED_REQUIREMENT)}"
      true
    end

    def v90_bundle_verifier
      if @transaction
        Util.fail!("staged V90-compatible bundle verifier is unavailable") unless
          @post_stop_v90_verifier && @post_stop_v90_verifier_identity
        assert_identity!(
          @post_stop_v90_verifier,
          @post_stop_v90_verifier_identity,
          "staged V90-compatible bundle verifier"
        )
        [@post_stop_v90_verifier, 0o500]
      else
        [Pins.fetch(:V90_BUNDLE_VERIFIER_SOURCE), 0o755]
      end
    end

    def v90_copy_manifest
      if @transaction
        Util.fail!("staged committed V90 app copy manifest is unavailable") unless
          @post_stop_v90_manifest && @post_stop_v90_manifest_identity
        assert_identity!(
          @post_stop_v90_manifest,
          @post_stop_v90_manifest_identity,
          "staged committed V90 app copy manifest"
        )
        [@post_stop_v90_manifest, 0o600]
      else
        [Pins.fetch(:V90_COMMITTED_COPY_MANIFEST), 0o600]
      end
    end

    def v90_reference
      if @transaction
        Util.fail!("staged V90 designated-requirement reference is unavailable") unless
          @post_stop_reference && @post_stop_reference_identity
        assert_identity!(
          @post_stop_reference,
          @post_stop_reference_identity,
          "staged predecessor reference"
        )
        reference = @post_stop_reference
      else
        Util.fail!("capsule V90 designated-requirement reference is unavailable") unless @reference_path
        reference = @reference_path
      end
      Util.exact_file!(
        reference,
        Pins.fetch(:APPROVED_PREDECESSOR_REFERENCE_SHA256),
        "V90 designated-requirement reference",
        mode: 0o755,
        owner: Process.euid
      )
      PredecessorReferenceFingerprint.verify!(reference, label: "V90 designated-requirement reference")
      reference
    end

    def verify_v90_bundle_contract!(
      app:, verifier:, verifier_sha:, verifier_mode:, manifest:, manifest_sha:, manifest_mode:,
      reference:, reference_sha:, reference_mode:, allowed_root_xattrs:
    )
      Util.fail!("V90 designated-requirement reference is unavailable") unless
        reference.is_a?(String) && !reference.empty?
      Util.exact_file!(
        verifier,
        verifier_sha,
        "V90-compatible bundle verifier",
        mode: verifier_mode,
        owner: Process.euid
      )
      Util.exact_file!(
        manifest,
        manifest_sha,
        "committed V90 app copy manifest",
        mode: manifest_mode,
        owner: Process.euid
      )
      Util.exact_file!(
        reference,
        reference_sha,
        "V90 designated-requirement reference",
        mode: reference_mode,
        owner: Process.euid
      )
      CopyManifest.new(app, allowed_root_xattrs: allowed_root_xattrs).verify!(manifest)
      command_with_environment!(
        { "OPENSTEAMER_EXPECTED_ARCHITECTURES" => "arm64" },
        verifier,
        "--installed-runtime",
        app,
        Pins.fetch(:TEAM_ID),
        reference
      )
      true
    end

    def verify_staged_candidate!(capsule)
      verify_staged_install_hold!
      staged_executable = File.join(@staged_app, "Contents/MacOS/CaptureServer")
      staged_framework = File.join(@staged_app, "Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC")
      staged_info = File.join(@staged_app, "Contents/Info.plist")
      Util.exact_file!(staged_executable, @candidate_executable_sha, "staged V91 executable", mode: 0o755, owner: Process.euid)
      Util.exact_file!(staged_framework, @candidate_framework_sha, "staged V91 framework", mode: 0o755, owner: Process.euid)
      Util.exact_file!(staged_info, @candidate_info_sha, "staged V91 Info.plist", mode: 0o644, owner: Process.euid)
      Util.exact_file!(@staged_plist, @candidate_plist_sha, "staged V91 launch plist", mode: 0o600, owner: Process.euid)
      CopyManifest.new(@staged_app).verify!(capsule.paths.fetch(:candidate_copy_manifest))
      LaunchContract.verify!(@staged_plist)
      verifier = File.join(capsule.root, "source", Pins.candidate_verifier_relative)
      command_with_environment!({ "OPENSTEAMER_EXPECTED_ARCHITECTURES" => "arm64" }, verifier, *Pins.candidate_verifier_flags, @staged_app, Pins.fetch(:TEAM_ID), capsule.paths.fetch(:reference))
    end

    def verify_installed_candidate_bytes!
      Util.fail!("installed candidate root xattr baseline is unavailable") unless @candidate_root_xattrs
      Util.exact_file!(Pins.fetch(:LIVE_EXECUTABLE), @candidate_executable_sha, "installed V91 executable", mode: 0o755, owner: 501)
      Util.exact_file!(Pins.fetch(:LIVE_FRAMEWORK), @candidate_framework_sha, "installed V91 framework", mode: 0o755, owner: 501)
      Util.exact_file!(Pins.fetch(:LIVE_INFO_PLIST), @candidate_info_sha, "installed V91 Info.plist", mode: 0o644, owner: 501)
      Util.exact_file!(Pins.fetch(:LAUNCH_AGENT), @candidate_plist_sha, "installed V91 launch plist", mode: 0o600, owner: 501)
      CopyManifest.new(Pins.fetch(:LIVE_APP), allowed_root_xattrs: @candidate_root_xattrs).verify!(@post_stop_copy_manifest)
      LaunchContract.verify!(Pins.fetch(:LAUNCH_AGENT))
      true
    end

    def launch_identity
      output = Util.capture!("/bin/launchctl", "print", Pins.fetch(:LAUNCH_LABEL))
      pids = output.scan(/^\s*pid = ([1-9][0-9]*)\s*$/).flatten.map(&:to_i)
      runs = output.scan(/^\s*runs = ([1-9][0-9]*)\s*$/).flatten.map(&:to_i)
      Util.fail!("launch state has ambiguous pid/runs") unless pids.length == 1 && runs.length == 1
      [pids.first, runs.first]
    end

    def verify_dynamic_process!(pid, expected_start: nil, expected_cdhash:)
      process_set = Util.capture!("/usr/bin/pgrep", "-x", "CaptureServer").strip
      Util.fail!("unexpected CaptureServer process set") unless process_set == pid.to_s
      command = Util.capture!("/bin/ps", "-p", pid.to_s, "-ww", "-o", "command=").strip
      Util.fail!("host command differs from ten-argument contract") unless command == Pins.fetch(:LAUNCH_ARGUMENTS).join(" ")
      start = Util.capture!("/bin/ps", "-p", pid.to_s, "-o", "lstart=").split.join(" ")
      Util.fail!("host process-start identity mismatch") if expected_start && start != expected_start
      command!("/usr/bin/codesign", *Pins.fetch(:DYNAMIC_CODESIGN_VERIFY_ARGUMENTS), "+#{pid}")
      metadata_stdout, metadata_stderr, metadata_status = Open3.capture3(
        "/usr/bin/codesign", "--display", "--verbose=4", "+#{pid}"
      )
      Util.fail!("could not read live process code identity") unless metadata_status.success?
      verify_dynamic_codesign_identity!(
        metadata_stdout.b + metadata_stderr.b,
        expected_cdhash: expected_cdhash
      )
      text = Util.capture!("/usr/sbin/lsof", "-a", "-p", pid.to_s, "-d", "txt", "-Fn")
      Util.fail!("live process text mapping differs") unless text.lines.map(&:chomp).count("n#{Pins.fetch(:LIVE_EXECUTABLE)}") == 1
      mappings = Util.capture!("/usr/sbin/lsof", "-a", "-p", pid.to_s, "-Fn")
      Util.fail!("live process lacks pinned media-framework mapping") unless mappings.lines.map(&:chomp).include?("n#{Pins.fetch(:LIVE_FRAMEWORK)}")
      true
    end

    def verify_dynamic_codesign_identity!(metadata, expected_cdhash:)
      identity = Util.exact_code_identity_values(metadata)
      Util.fail!("live process code identity is ambiguous") unless
        identity.fetch(:identifier) == [Pins.fetch(:EXECUTABLE_IDENTIFIER)] &&
        identity.fetch(:team_identifier) == [Pins.fetch(:TEAM_ID)] &&
        identity.fetch(:cdhash) == [expected_cdhash]
      true
    end

    def strict_lock_record
      directory = File.dirname(Pins.fetch(:LIVE_LOCK_PATH))
      Util.directory!(directory, "host generation-lock directory", mode: 0o700, owner: 501)
      assert_identity!(directory, @predecessor_runtime.lock_directory, "host lock directory") if @predecessor_runtime
      Util.regular_file!(Pins.fetch(:LIVE_LOCK_PATH), "host generation lock", mode: 0o600, owner: 501, links: 1)
      match = File.binread(Pins.fetch(:LIVE_LOCK_PATH)).match(/\AOPENSTEAMER_WORLDWIDE_HOST_GENERATION_V1\npid=([1-9][0-9]*)\nnonce=([0-9a-f]{64})\n\z/)
      Util.fail!("host generation lock is malformed") unless match
      { pid: match[1].to_i, nonce: match[2] }
    end

    def verify_routes!
      tool = helper_path("SwitchAudioSource")
      Pins.fetch(:ROUTES).each do |type, expected|
        actual = Util.capture!(tool, "-c", "-t", type, "-f", "json").strip
        Util.fail!("#{type} audio route changed") unless actual == expected
      end
      true
    end

    def readiness_generation!
      output = Util.capture!(@post_stop_readiness, Pins.fetch(:LIVE_EXECUTABLE), @candidate_executable_sha)
      pattern = /\AV91_SECONDARY_VIEWER_ENDPOINT_IDLE_OK candidateSHA256=#{Regexp.escape(@candidate_executable_sha)} pid=#{@new_pid} managerGeneration=(0|[1-9][0-9]*) probes=2\n?\z/
      match = output.match(pattern)
      Util.fail!("V91 secondary-viewer readiness proof is malformed or mismatched") unless match
      Integer(match[1], 10)
    end

    def observe_candidate_session!(prior, fresh_generation: false)
      SessionFence.observe!(
        Pins.fetch(:LAUNCH_STDOUT),
        @new_pid,
        @new_nonce,
        prior: prior,
        fresh_generation: fresh_generation
      )
    end

    def establish_candidate_stability_baseline!
      pid, runs = launch_identity
      Util.fail!("V91 launch identity is not a fresh single run") unless runs == 1
      @new_pid = pid
      record = strict_lock_record
      Util.fail!("V91 generation-lock PID differs from launch") unless record.fetch(:pid) == pid
      @predecessor_runtime.fresh_generation!(pid, record.fetch(:nonce))
      @new_nonce = record.fetch(:nonce)
      verify_dynamic_process!(pid, expected_cdhash: @candidate_cdhash)
      capture_candidate_root_xattrs!
      verify_installed_candidate_bytes!
      Util.fail!("V91 display mode did not settle") unless current_display_mode == Pins.fetch(:LIVE_DISPLAY_MODE)
      @candidate_session = observe_candidate_session!(@session, fresh_generation: true)
      verify_routes!
      route_monitor_clean!
      @candidate_manager_generation = readiness_generation!
      true
    end

    def capture_candidate_root_xattrs!
      @candidate_root_xattrs ||= CopyManifest.capture_published_root_xattrs!(Pins.fetch(:LIVE_APP))
    end

    def verify_candidate_stability_sample!
      Util.fail!("candidate stability baseline is unavailable") unless
        @new_pid && @new_nonce && !@candidate_manager_generation.nil? && @candidate_session
      Util.fail!("V91 launch identity changed during stability proof") unless
        launch_identity == [@new_pid, 1]
      Util.fail!("V91 host generation changed during stability proof") unless
        strict_lock_record == { pid: @new_pid, nonce: @new_nonce }
      verify_dynamic_process!(@new_pid, expected_cdhash: @candidate_cdhash)
      verify_installed_candidate_bytes!
      Util.fail!("secondary-viewer manager generation changed during stability proof") unless
        readiness_generation! == @candidate_manager_generation
      Util.fail!("V91 display mode changed during stability proof") unless
        current_display_mode == Pins.fetch(:LIVE_DISPLAY_MODE)
      @candidate_session = observe_candidate_session!(@candidate_session)
      verify_routes!
      route_monitor_clean!
      true
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def stability_sleep(seconds)
      sleep(seconds)
    end

    def run_candidate_stability_window!(duration: 31)
      started = monotonic_now
      final_deadline = started + duration
      1.upto(duration) do |second|
        deadline = started + second
        remaining = deadline - monotonic_now
        stability_sleep(remaining) if remaining.positive?
        Util.fail!("monotonic stability clock did not reach second #{second}") if monotonic_now < deadline
        verify_candidate_stability_sample!
        # Slow complete probes count toward elapsed stability; never exit midway through a sample.
        break if monotonic_now >= final_deadline
      end
      Util.fail!("candidate stability window was shorter than #{duration} seconds") if
        monotonic_now < final_deadline
      true
    end

    def current_display_mode
      tool = helper_path("verify-live-display-topology-v23")
      topology = Util.capture!(tool, "--opensteamer-any")
      lines = topology.lines.map(&:chomp)
      Util.fail!("display topology is malformed") unless lines.length >= 3 && lines.first.match?(/\Adisplay=[1-9][0-9]* online=1 main=1 vendor=6f73 product=1718\z/)
      current = lines[1][/\Acurrent=(.+)\z/, 1]
      Util.fail!("display topology lacks current selection") unless current && lines.drop(2).count(current) == 1
      current
    end

    def runtime_absent?
      _out, _err, status = Open3.capture3("/bin/launchctl", "print", Pins.fetch(:LAUNCH_LABEL))
      return false if status.success?
      pids, = Open3.capture3("/usr/bin/pgrep", "-x", "CaptureServer")
      return false unless pids.strip.empty?
      lock_probe = helper_path("probe-worldwide-lock-v23")
      topology = helper_path("verify-live-display-topology-v23")
      _a, _b, lock_status = Open3.capture3(lock_probe, "--unowned")
      _c, _d, topology_status = Open3.capture3(topology, "--headless")
      lock_status.success? && topology_status.success?
    end

    def ensure_same_filesystem!(staged, destination)
      source_dev = File.lstat(staged).dev
      destination_dev = File.lstat(destination).dev
      Util.fail!("transaction cannot use same-filesystem rename") unless source_dev == destination_dev
    end

    def exclusive_rename(source, destination)
      Util.fail!("rename source is missing") unless File.exist?(source) || File.symlink?(source)
      Util.fail!("rename destination already exists") if File.exist?(destination) || File.symlink?(destination)
      Util.fail!("rename crosses filesystems") unless File.lstat(source).dev == File.lstat(File.dirname(destination)).dev
      source_parent = File.dirname(source)
      destination_parent = File.dirname(destination)
      result = DarwinRename.renamex_np(source, destination, 0x00000004) # RENAME_EXCL
      Util.fail!("exclusive rename failed for #{source}") unless result.zero?
      strict_fsync_directory!(source_parent, "exclusive rename source parent") if source_parent != destination_parent
      strict_fsync_directory!(destination_parent, "exclusive rename parent")
    end

    def wait_until!(seconds, diagnostic, interval: 0.1)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      loop do
        return true if yield
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep interval
      end
      Util.fail!(diagnostic)
    end

    def command!(*args)
      Util.capture!(*args)
      true
    end

    def command_with_environment!(environment, *args)
      stdout, stderr, status = Open3.capture3(environment, *args)
      Util.fail!("command failed: #{args.shelljoin}: #{stderr.strip}") unless status.success?
      stdout
    end

    def combined_capture!(*args)
      stdout, stderr, status = Open3.capture3(*args)
      Util.fail!("command failed: #{args.shelljoin}: #{stderr.strip}") unless status.success?
      stdout.b + stderr.b
    end

    def write_durable(path, contents, mode, exclusive:)
      flags = File::WRONLY | File::CREAT | File::NOFOLLOW
      flags |= File::EXCL if exclusive
      Thread.handle_interrupt(Interrupt => :never) do
        File.open(path, flags, mode) do |file|
          after_file_create_before_identity!(path)
          stat = file.stat
          identity = [stat.dev, stat.ino, stat.ftype]
          yield identity if block_given?
          set_durable_mode!(file, mode, "durable file #{path}")
          write_all!(file, contents, "durable file #{path}")
          file.flush
          strict_fsync_io!(file, "durable file #{path}")
          assert_open_identity!(path, file, "durable file #{path}")
          Util.fail!("durable file mode differs: #{path}") unless
            (file.stat.mode & 0o7777) == mode
        end
      end
      strict_fsync_directory!(File.dirname(path), "durable file parent")
      true
    rescue Errno::ELOOP => error
      Util.fail!("durable file path is a symlink: #{path}: #{error.message}")
    end

  end

  # A receipt is written only after exact rollback and clean route-monitor teardown. It owns
  # only deterministic archive names derived from its UUID, never paths supplied by a receipt.
  class RollbackHistory
    RECEIPT = "rollback-terminal-receipt.json"
    SCHEMA = "opensteamer.rollback-terminal-receipt.v1"
    KEYS = %w[schema transaction token transactionIdentity transactionSHA256 failedAppIdentity
              failedAppSHA256 failedAppRootXattrs failedPlistIdentity failedPlistSHA256 journalSHA256 rollbackResultSHA256].freeze
    TOKEN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze
    TRANSACTION = /\Apaired-v91-update-[0-9]+-[0-9]+-[0-9a-f-]{36}\z/.freeze

    attr_reader :transactions, :applications, :launch_agents

    def initialize(root:, application_parent:, launch_parent:)
      @root, @application_parent, @launch_parent = root, application_parent, launch_parent
      @transactions, @applications, @launch_agents = [], [], []
      @snapshots = {}
    end

    def self.identity(path)
      stat = File.lstat(path)
      [stat.dev, stat.ino, stat.ftype].join(":")
    end

    # In-memory replay is stat-only. ctime detects byte/xattr changes even if mtime is restored.
    def self.snapshot(path, exclude_receipt: false)
      records = []
      walk = lambda do |node, relative|
        stat = File.lstat(node)
        records << [relative, stat.dev, stat.ino, stat.ftype, stat.mode, stat.uid, stat.gid,
                    stat.nlink, stat.size, stat.mtime.to_r.to_s, stat.ctime.to_r.to_s,
                    (File.readlink(node) if stat.symlink?)]
        if stat.directory?
          Dir.children(node).sort.each do |name|
            next if exclude_receipt && relative.empty? && name == RECEIPT
            walk.call(File.join(node, name), relative.empty? ? name : File.join(relative, name))
          end
        end
      end
      walk.call(path, "")
      records
    rescue SystemCallError => error
      Util.fail!("rollback history cannot be inspected: #{error.message}")
    end

    def self.tree_digest(path, transaction: false)
      entries = snapshot(path, exclude_receipt: transaction)
      records = entries.map do |entry|
        relative, dev, ino, kind, mode, uid, gid, nlink = entry
        Util.fail!("rollback history has unsafe node name") if relative.match?(/[\x00-\x1f\x7f]/)
        node = relative.empty? ? path : File.join(path, relative)
        Util.fail!("rollback history contains foreign-owned node") unless uid == Process.euid
        Util.fail!("rollback history contains unsupported node") unless %w[file directory link].include?(kind)
        Util.fail!("rollback history contains hard-linked file") if kind == "file" && nlink != 1
        Util.fail!("rollback transaction contains symbolic link") if transaction && kind == "link"
        Util.clean_node_metadata!(node, "rollback transaction node") if transaction
        if kind == "link"
          Util.fail!("rollback app contains unreviewed alias") unless
            Pins.fetch(:ALLOWED_CANDIDATE_SYMLINKS)[relative] == File.readlink(node)
          Util.fail!("rollback app alias escapes archive") unless File.realpath(node).start_with?(File.realpath(path) + "/")
        end
        content = kind == "file" ? Util.sha256(node) : (kind == "link" ? File.readlink(node) : "")
        [relative, dev, ino, kind, mode, uid, gid, (kind == "directory" ? 0 : nlink), content]
      end
      Util.fail!("rollback history changed while hashing") unless
        snapshot(path, exclude_receipt: transaction) == entries
      Util.sha256_text(JSON.generate(records))
    end

    def paths(token)
      Util.fail!("rollback receipt token is malformed") unless TOKEN.match?(token.to_s)
      [File.join(@application_parent, ".opensteamer-paired-#{Pins.release_name}-failed-#{token}.app"),
       File.join(@launch_parent, ".org.example.opensteamer.worldwide.#{Pins.release_name}-failed-#{token}.plist")]
    end

    def receipt_for(transaction, token)
      validate_transaction_path!(transaction)
      app, plist = paths(token)
      verify_terminal_proof!(transaction)
      Util.directory!(transaction, "completed rollback transaction", mode: 0o700, owner: Process.euid)
      Util.regular_file!(plist, "failed rollback launch plist", mode: 0o600, owner: Process.euid)
      Util.fail!("failed rollback app is not a real directory") unless File.lstat(app).directory?
      allowed_xattrs = CopyManifest.capture_published_root_xattrs!(app)
      CopyManifest.new(app, allowed_root_xattrs: allowed_xattrs).verify!(
        File.join(transaction, "v91-candidate-app-copy-manifest.txt")
      )
      {
        "schema" => SCHEMA, "transaction" => File.basename(transaction), "token" => token,
        "transactionIdentity" => self.class.identity(transaction),
        "transactionSHA256" => self.class.tree_digest(transaction, transaction: true),
        "failedAppIdentity" => self.class.identity(app), "failedAppSHA256" => self.class.tree_digest(app),
        "failedAppRootXattrs" => JSON.generate(allowed_xattrs),
        "failedPlistIdentity" => self.class.identity(plist), "failedPlistSHA256" => Util.sha256(plist),
        "journalSHA256" => Util.sha256(File.join(transaction, "journal.log")),
        "rollbackResultSHA256" => Util.sha256(File.join(transaction, "rollback-result.txt"))
      }
    end

    def capture!(legacy: nil)
      Util.directory!(@root, "rollback history root", mode: 0o700, owner: Process.euid)
      @root_identity = self.class.identity(@root)
      Dir.children(@root).sort.each do |name|
        transaction = File.join(@root, name)
        if legacy && transaction == legacy.fetch(:transaction)
          app, plist = legacy.values_at(:app, :plist)
          before = [transaction, app, plist].to_h { |path| [path, self.class.snapshot(path)] }
          legacy.fetch(:verify).call
        else
          validate_transaction_path!(transaction)
          receipt_path = File.join(transaction, RECEIPT)
          Util.regular_file!(receipt_path, "rollback terminal receipt", mode: 0o600, owner: Process.euid)
          receipt = Util.strict_json(receipt_path, KEYS, SCHEMA)
          Util.fail!("rollback receipt transaction mismatch") unless receipt.fetch("transaction") == name
          app, plist = paths(receipt.fetch("token"))
          before = [transaction, app, plist].to_h { |path| [path, self.class.snapshot(path)] }
          Util.fail!("rollback receipt changed while opening") unless
            Util.strict_json(receipt_path, KEYS, SCHEMA) == receipt
          Util.fail!("rollback history receipt does not match retained evidence") unless
            receipt == receipt_for(transaction, receipt.fetch("token"))
        end
        Util.fail!("rollback histories reuse an archive") if @applications.include?(File.basename(app)) ||
          @launch_agents.include?(File.basename(plist))
        @transactions << name
        @applications << File.basename(app)
        @launch_agents << File.basename(plist)
        before.each do |path, snapshot|
          Util.fail!("rollback history changed during validation") unless self.class.snapshot(path) == snapshot
          @snapshots[path] = snapshot
        end
      end
      if legacy
        Util.fail!("legacy rollback history is missing") unless @transactions.include?(File.basename(legacy.fetch(:transaction)))
      end
      true
    end

    def unchanged!
      Util.fail!("rollback history root was replaced") unless self.class.identity(@root) == @root_identity
      @snapshots.each do |path, expected|
        Util.fail!("retained rollback history changed: #{File.basename(path)}") unless self.class.snapshot(path) == expected
      end
      true
    end

    private

    def validate_transaction_path!(transaction)
      Util.fail!("rollback transaction path is outside owned history root") unless
        File.dirname(transaction) == @root &&
        /\Apaired-#{Regexp.escape(Pins.release_name)}-update-[0-9]+-[0-9]+-[0-9a-f-]{36}\z/.match?(File.basename(transaction)) &&
        File.basename(transaction).split("-").last(5).join("-").match?(TOKEN)
      Util.directory!(transaction, "rollback transaction", mode: 0o700, owner: Process.euid)
    end

    def verify_terminal_proof!(transaction)
      journal = File.join(transaction, "journal.log")
      Util.regular_file!(journal, "rollback journal", mode: 0o600, owner: Process.euid)
      lines = File.readlines(journal, chomp: true)
      Util.fail!("rollback journal header is invalid") unless lines.shift == Pins.fetch(:V91_JOURNAL_HEADER)
      prior = nil
      lines.each do |line|
        state = line[/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z STATE ([A-Z0-9_]+)\z/, 1]
        state = Pins.state_in(state) if state
        Util.fail!("rollback journal transition is invalid") unless state && RealHost::JOURNAL_TRANSITIONS.fetch(prior, []).include?(state)
        prior = state
      end
      Util.fail!("rollback transaction is not terminal") unless prior == "ROLLED_BACK_EXACT_V90"
      result = File.join(transaction, "rollback-result.txt")
      Util.regular_file!(result, "rollback result", mode: 0o600, owner: Process.euid)
      expected = /\Aresult=pending-terminal\nterminal_required=ROLLED_BACK_EXACT_V90\npid=[1-9][0-9]*\nnonce=[0-9a-f]{64}\ntarget=exact-v90\nselected=#{Regexp.escape(Pins.fetch(:LIVE_DISPLAY_MODE))}\n\z/
      Util.fail!("rollback result proof differs") unless Pins.record_in(File.binread(result)).match?(expected)
      stdout = File.join(transaction, "sticky-coreaudio-route-monitor.stdout")
      Util.regular_file!(stdout, "rollback CoreAudio stdout", mode: 0o600, owner: Process.euid)
      Util.fail!("rollback lacks clean CoreAudio teardown") unless
        File.binread(stdout) == "#{Pins.fetch(:ROUTE_MONITOR_READY)}\n#{Pins.fetch(:ROUTE_MONITOR_RESULT)}\n"
      %w[sticky-coreaudio-route-events.log sticky-coreaudio-route-monitor.stderr].each do |name|
        path = File.join(transaction, name)
        Util.regular_file!(path, "rollback CoreAudio empty proof", mode: 0o600, owner: Process.euid)
        Util.fail!("rollback CoreAudio proof is not clean") unless File.zero?(path)
      end
    end
  end

  class FakeCapsule
    attr_reader :verify_count

    def initialize(fail_verify_at: nil)
      @verify_count = 0
      @fail_verify_at = fail_verify_at
    end

    def verify!
      @verify_count += 1
      raise Failure, "capsule drift" if @fail_verify_at == @verify_count
      true
    end
  end

  class FakeHost
    attr_reader :events, :states, :active_pointer

    def initialize(fail_at: nil, namespace_fresh: true)
      @events = []
      @states = []
      @fail_at = fail_at
      @namespace_fresh = namespace_fresh
      @active_pointer = false
      @pending_pointer = false
      @transaction_lock = false
      @prepared_artifacts = false
      @route_safety_failure = false
      @committed_unverified = false
    end

    def preflight!(_capsule)
      observe(:preflight)
      raise Failure, "V91 namespace is not fresh" unless @namespace_fresh
    end

    def prepare!(_capsule)
      mutate(:prepare)
      @pending_pointer = true
      @transaction_lock = true
      @prepared_artifacts = true
      journal!("BEGUN")
      observe(:initial_durability_barrier)
      observe(:initial_topology_barrier)
      journal!("INPUTS_VERIFIED")
    end

    def revalidate_immediately_before_stop!(_capsule)
      observe(:revalidate)
      observe(:final_durability_barrier)
      observe(:final_topology_barrier)
    end

    def stop_predecessor!
      mutate(:stop_predecessor)
      journal!("V90_STOPPED")
    end

    def hold_predecessor!
      mutate(:rename_v90_app_to_hold)
      mutate(:rename_v90_plist_to_hold)
      journal!("V90_HELD")
    end

    def publish_candidate!
      mutate(:rename_v91_app_to_live)
      mutate(:rename_v91_plist_to_live)
      journal!("V91_PUBLISHED")
    end

    def start_candidate!
      mutate(:start_candidate)
      journal!("V91_BOOTSTRAPPED")
    end

    def verify_candidate_ready!
      observe(:verify_candidate_ready)
    end

    def prepare_irreversible_commit!
      mutate(:write_pending_result)
      mutate(:publish_active_pointer)
      @active_pointer = true
      mutate(:unlink_pending_pointer)
      @pending_pointer = false
      observe(:pre_irreversible_safety_replay)
    end

    def finalize_postcommit!
      @route_safety_failure = true if @fail_at == :stop_route_monitor
      mutate(:stop_route_monitor)
      observe(:final_route_readback)
      mutate(:write_final_result)
      mutate(:remove_transaction_lock)
      @transaction_lock = false
    end

    def abort_before_stop!
      mutate(:abort_before_stop)
      @active_pointer = false
      @pending_pointer = false
      @transaction_lock = false
      @prepared_artifacts = false
    end

    def journal!(state)
      if @fail_at == :journal_stop_after_persist && state == "STOP_INTENT"
        @events << [:mutate, :"journal:#{state}"]
        @states << state
        raise JournalPersistenceUnverified, "injected uncertain durable #{state}"
      end
      if @fail_at == :journal_irreversible_after_persist && state == "V91_COMMIT_IRREVERSIBLE"
        @events << [:mutate, :"journal:#{state}"]
        @states << state
        raise Failure, "injected durable #{state} acknowledgement failure"
      end
      mutate("journal:#{state}".to_sym)
      @states << state
    end

    def irreversible_on_disk?
      @states.include?("V91_COMMIT_IRREVERSIBLE")
    end

    def stop_intent_on_disk?
      @states.include?("STOP_INTENT")
    end

    def record_committed_unverified!(_original)
      mutate(:record_committed_unverified)
      @committed_unverified = true
      @states << "COMMITTED_V91_UNVERIFIED" unless @states.last == "COMMITTED_V91_UNVERIFIED"
      true
    end

    def rollback_exact_v90!
      raise Failure, "rollback lost transaction lock" unless @transaction_lock
      %w[ROLLBACK_STARTED V91_STOPPED FAILED_V91_ARCHIVED V90_RESTORED V90_BOOTSTRAPPED].each do |state|
        journal!(state)
      end
      mutate(:rollback_exact_v90)
      @active_pointer = false
      @pending_pointer = false
      @prepared_artifacts = false
      raise Failure, "retained route-monitor safety failure" if @route_safety_failure
      journal!("ROLLED_BACK_EXACT_V90")
      mutate(:publish_rollback_receipt)
      @transaction_lock = false
    end

    def rollback_clean?
      !@active_pointer && !@pending_pointer && !@transaction_lock && !@prepared_artifacts
    end

    def commit_clean?
      @active_pointer && !@pending_pointer && !@transaction_lock && @prepared_artifacts
    end

    def committed_unverified?
      @committed_unverified && @active_pointer && !@pending_pointer
    end

    def abort_clean?
      !@active_pointer && !@pending_pointer && !@transaction_lock && !@prepared_artifacts
    end

    private

    def observe(event)
      @events << [:observe, event]
      raise Failure, "injected #{event}" if @fail_at == event
      true
    end

    def mutate(event)
      @events << [:mutate, event]
      raise Failure, "injected #{event}" if @fail_at == event
      true
    end
  end

  module SelfTest
    extend self

    def verify_reusable_rollback_history_fixture!
      Dir.mktmpdir("v91-reusable-history-") do |temporary|
        root = File.realpath(temporary)
        history_root, applications, launch_agents = %w[history applications launch_agents].map { |name| File.join(root, name) }
        [history_root, applications, launch_agents].each { |path| Dir.mkdir(path, 0o700) }
        build_history = -> { RollbackHistory.new(root: history_root, application_parent: applications, launch_parent: launch_agents) }
        write_private = lambda do |path, content|
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content) }
        end
        counter = 0
        seal = lambda do |states|
          counter += 1
          token = SecureRandom.uuid
          transaction = File.join(history_root, "paired-v91-update-#{counter}-#{Process.pid}-#{SecureRandom.uuid}")
          Dir.mkdir(transaction, 0o700)
          app, plist = build_history.call.paths(token)
          Dir.mkdir(app, 0o755)
          File.chmod(0o755, app)
          create_copy_manifest_fixture(app)
          manifest, = CopyManifest.new(app).render
          write_private.call(File.join(transaction, "v91-candidate-app-copy-manifest.txt"), manifest)
          if counter == 2
            Util.capture!("/usr/bin/xattr", "-w", "-x", "com.apple.macl", "00" * 72, app)
          end
          write_private.call(plist, "unchanged-fixture-launch-contract\n")
          journal = "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n" + states.map { |state| "2026-01-01T00:00:00Z STATE #{state}\n" }.join
          write_private.call(File.join(transaction, "journal.log"), journal)
          write_private.call(File.join(transaction, "rollback-result.txt"),
                             "result=pending-terminal\nterminal_required=ROLLED_BACK_EXACT_V90\npid=#{counter}\nnonce=#{'a' * 64}\ntarget=exact-v90\nselected=#{Pins.fetch(:LIVE_DISPLAY_MODE)}\n")
          write_private.call(File.join(transaction, "sticky-coreaudio-route-monitor.stdout"),
                             "#{Pins.fetch(:ROUTE_MONITOR_READY)}\n#{Pins.fetch(:ROUTE_MONITOR_RESULT)}\n")
          %w[sticky-coreaudio-route-events.log sticky-coreaudio-route-monitor.stderr].each do |name|
            write_private.call(File.join(transaction, name), "")
          end
          receipt = build_history.call.receipt_for(transaction, token)
          write_private.call(File.join(transaction, RollbackHistory::RECEIPT), JSON.generate(receipt) + "\n")
        end
        fixture_host = Class.new(FakeHost) do
          define_method(:initialize) do |builder, publisher, boundary|
            super(fail_at: boundary)
            @builder, @publisher = builder, publisher
          end
          define_method(:preflight!) do |capsule|
            unless @history
              @history = @builder.call
              @history.capture!
            end
            @history.unchanged!
            super(capsule)
          end
          define_method(:rollback_exact_v90!) do
            super()
            @publisher.call(states)
          end
        end
        capsule = FakeCapsule.new
        %i[verify_candidate_ready pre_irreversible_safety_replay].each do |boundary|
          host = fixture_host.new(build_history, seal, boundary)
          begin
            Coordinator.new(host, capsule).execute!
            raise Failure, "fixture unexpectedly committed"
          rescue Failure => error
            raise Failure, "rollback fixture failed before intended boundary: #{error.message}" unless
              error.message == "injected #{boundary}"
          end
          assert("each reused artifact attempt exact-rolls back") { host.states.last == "ROLLED_BACK_EXACT_V90" }
          assert("rollback receipt is published after terminal while lock is owned") do
            host.events.index([:mutate, :publish_rollback_receipt]) >
              host.events.index([:mutate, :"journal:ROLLED_BACK_EXACT_V90"])
          end
        end
        history = build_history.call
        history.capture!
        assert("same artifact has two retained independently owned rollback histories") do
          capsule.verify_count == 4 && history.transactions.length == 2 && history.applications.uniq.length == 2
        end
        history.unchanged!
        first_transaction = File.join(history_root, history.transactions.first)
        receipt_path = File.join(first_transaction, RollbackHistory::RECEIPT)
        original_receipt = File.binread(receipt_path)
        File.binwrite(receipt_path, original_receipt.sub('"token":', '"unexpected":'))
        expect_failure("tampered rollback receipt") { build_history.call.capture! }
        File.binwrite(receipt_path, original_receipt)
        expect_failure("cached receipt metadata drift") { history.unchanged! }
        history = build_history.call
        history.capture!
        artifact = File.join(applications, history.applications.first, "Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC")
        original_bytes = File.binread(artifact)
        File.open(artifact, "ab") { |file| file.write("drift") }
        expect_failure("cached archived artifact drift") { history.unchanged! }
        expect_failure("persisted archived artifact drift") { build_history.call.capture! }
        File.binwrite(artifact, original_bytes)
        incomplete = File.join(history_root, "paired-v91-update-99-#{Process.pid}-#{SecureRandom.uuid}")
        Dir.mkdir(incomplete, 0o700)
        expect_failure("unfinished rollback history blocks retry") { build_history.call.capture! }
        Dir.rmdir(incomplete)
        unknown = File.join(history_root, "unowned-history")
        Dir.mkdir(unknown, 0o700)
        expect_failure("unknown history namespace blocks retry") { build_history.call.capture! }
        Dir.rmdir(unknown)
        final_history = build_history.call
        final_history.capture!
        assert("failed checks preserve both original transactions") { final_history.transactions.length == 2 }
      end
    end

    def verify_artifact_build_provenance_fixture!
      Dir.mktmpdir("v91-build-provenance-") do |temporary|
        root = File.realpath(temporary)
        environment = {
          "GIT_AUTHOR_NAME" => "Fixture", "GIT_AUTHOR_EMAIL" => "fixture@example.invalid",
          "GIT_COMMITTER_NAME" => "Fixture", "GIT_COMMITTER_EMAIL" => "fixture@example.invalid",
          "GIT_AUTHOR_DATE" => "2000-01-01T00:00:00Z", "GIT_COMMITTER_DATE" => "2000-01-01T00:00:00Z"
        }
        git = lambda do |*arguments, input: ""|
          output, error, status = Open3.capture3(
            environment, "/usr/bin/git", "-C", root, *arguments, stdin_data: input
          )
          Util.fail!("fixture Git failed: #{error.strip}") unless status.success?
          output
        end
        git.call("init", "--bare", "--quiet")
        make_tree = lambda do |content|
          blob = git.call("hash-object", "-w", "--stdin", input: content).strip
          scripts = git.call("mktree", input: "100755 blob #{blob}\tassemble-v91-sealed-host-oracle-capsule.sh\n").strip
          macos = git.call("mktree", input: "040000 tree #{scripts}\tscripts\n").strip
          tree = git.call("mktree", input: "040000 tree #{macos}\tmacOS\n").strip
          [tree, blob]
        end
        source_tree, = make_tree.call("source assembler\n")
        source = git.call("commit-tree", source_tree, input: "source\n").strip
        build_tree, build_blob = make_tree.call("reviewed build assembler\n")
        build = git.call("commit-tree", build_tree, "-p", source, input: "build tooling\n").strip
        deployment_tree, deployment_blob = make_tree.call("later deployment tooling\n")
        deployment = git.call("commit-tree", deployment_tree, "-p", build, input: "deployment tooling\n").strip
        unrelated = git.call("commit-tree", source_tree, input: "unrelated history\n").strip
        payload = {
          "sourceCommit" => source, "sourceTree" => source_tree,
          "toolingCommit" => build, "toolingTree" => build_tree,
          "assemblerScriptRelativePath" => "macOS/scripts/assemble-v91-sealed-host-oracle-capsule.sh",
          "assemblerScriptGitBlob" => build_blob
        }
        original = Marshal.dump(payload)
        assert("unchanged artifact can use newer deployment tooling") do
          BuildProvenance.verify!(payload, { commit: deployment }, git: git) &&
            build != deployment && build_blob != deployment_blob && Marshal.dump(payload) == original
        end
        assert("artifact can use its original deployment tooling") do
          BuildProvenance.verify!(payload, { commit: build }, git: git)
        end
        {
          "historical build tree drift" => { "toolingTree" => deployment_tree },
          "historical assembler blob drift" => { "assemblerScriptGitBlob" => deployment_blob },
          "historical source tree drift" => { "sourceTree" => build_tree },
          "historical source outside build ancestry" => { "sourceCommit" => unrelated },
          "historical build outside deployment ancestry" => {
            "toolingCommit" => unrelated, "toolingTree" => source_tree
          },
          "historical build missing" => { "toolingCommit" => "f" * 40 },
          "historical assembler path substitution" => { "assemblerScriptRelativePath" => "other.sh" }
        }.each do |label, changes|
          expect_failure(label) do
            BuildProvenance.verify!(payload.merge(changes), { commit: deployment }, git: git)
          end
        end
        expect_failure("deployment outside approved build ancestry") do
          BuildProvenance.verify!(payload, { commit: unrelated }, git: git)
        end
      end
      true
    end

    def verify_deployment_observer_fixture!
      Dir.mktmpdir("v91-observer-provenance-") do |temporary|
        root = File.realpath(temporary)
        relative = "macOS/scripts/verify-v91-secondary-viewer-readiness.sh"
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path), mode: 0o755)
        current = "#!/bin/sh\n# current reviewed readiness observer\n"
        obsolete = "#!/bin/sh\n# obsolete product-source readiness observer\n"
        File.binwrite(path, current)
        File.chmod(0o755, path)
        blob = Digest::SHA1.hexdigest("blob #{current.bytesize}\0".b + current)
        proof = { commit: "a" * 40, tree: "b" * 40, blobs: { relative => blob } }
        snapshot = TrackedToolSnapshot.read!(root, relative, proof, mode: 0o755)
        assert("readiness observer is exact current deployment tooling") do
          snapshot.fetch("bytes") == current && snapshot.fetch("readinessScriptGitBlob") == blob &&
            snapshot.fetch("deploymentToolingCommit") == proof.fetch(:commit) &&
            snapshot.fetch("readinessScriptSHA256") == Digest::SHA256.hexdigest(current)
        end
        File.binwrite(path, obsolete)
        expect_failure("obsolete product-source observer cannot replace deployment observer") do
          TrackedToolSnapshot.read!(root, relative, proof, mode: 0o755)
        end
        File.binwrite(path, current + "drift")
        expect_failure("readiness bytes changed after tooling verification") do
          TrackedToolSnapshot.read!(root, relative, proof, mode: 0o755)
        end
        File.binwrite(path, current)
        hardlink = File.join(root, "hardlink")
        File.link(path, hardlink)
        expect_failure("readiness observer cannot be hard-linked") do
          TrackedToolSnapshot.read!(root, relative, proof, mode: 0o755)
        end
        File.unlink(hardlink)
        File.rename(path, hardlink)
        File.symlink(hardlink, path)
        expect_failure("readiness observer cannot be symlink-substituted") do
          TrackedToolSnapshot.read!(root, relative, proof, mode: 0o755)
        end
      end
      true
    end

    def assert(label)
      raise Failure, "self-test failed: #{label}" unless yield
    end

    def expect_failure(label)
      begin
        yield
      rescue Failure
        return true
      end
      raise Failure, "self-test failed: #{label} unexpectedly succeeded"
    end

    def expect_exception(label)
      begin
        yield
      rescue Exception # rubocop:disable Lint/RescueException
        return true
      end
      raise Failure, "self-test failed: #{label} unexpectedly succeeded"
    end

    def create_copy_manifest_fixture(root)
      framework = File.join(root, "Contents/Frameworks/LiveKitWebRTC.framework")
      version = File.join(framework, "Versions/A")
      ["Headers", "Modules", "Resources"].each do |name|
        FileUtils.mkdir_p(File.join(version, name), mode: 0o755)
      end
      executable = File.join(version, "LiveKitWebRTC")
      File.binwrite(executable, "fixture-framework-binary\n")
      File.chmod(0o755, executable)
      {
        "Headers" => "Versions/Current/Headers",
        "LiveKitWebRTC" => "Versions/Current/LiveKitWebRTC",
        "Modules" => "Versions/Current/Modules",
        "Resources" => "Versions/Current/Resources"
      }.each do |name, target|
        File.symlink(target, File.join(framework, name))
      end
      File.symlink("A", File.join(framework, "Versions/Current"))
      true
    end

    def verify_v90_bundle_contract_fixture!
      Dir.mktmpdir("v91-v90-bundle-contract-") do |temporary|
        root = File.realpath(temporary)
        app = File.join(root, "opensteamer Host.app")
        Dir.mkdir(app, 0o755)
        File.chmod(0o755, app)
        create_copy_manifest_fixture(app)
        macos = File.join(app, "Contents/MacOS")
        resources = File.join(app, "Contents/Resources")
        FileUtils.mkdir_p(macos, mode: 0o755)
        FileUtils.mkdir_p(resources, mode: 0o755)
        executable = File.join(macos, "CaptureServer")
        info = File.join(app, "Contents/Info.plist")
        notices = File.join(resources, "ThirdPartyNotices.md")
        File.binwrite(executable, "fixture-v90-executable\n")
        File.chmod(0o755, executable)
        File.binwrite(info, "fixture-v90-info\n")
        File.chmod(0o644, info)
        File.binwrite(notices, "fixture-v90-notices\n")
        File.chmod(0o644, notices)
        assert("V90 fixture has the committed no-icon resource schema") do
          Dir.children(resources) == ["ThirdPartyNotices.md"]
        end

        manifest = File.join(root, "v90-candidate-app-copy-manifest.txt")
        File.binwrite(manifest, CopyManifest.new(app).render.first)
        File.chmod(0o600, manifest)
        verifier = File.join(root, "verify-v90-mac-host-bundle.sh")
        verifier_bytes = <<~SH
          #!/bin/sh
          set -eu
          [ "$#" -eq 4 ]
          [ "$1" = "--installed-runtime" ]
          [ "$3" = "#{Pins.fetch(:TEAM_ID)}" ]
          [ -d "$2" ]
          [ -f "$2/Contents/Resources/ThirdPartyNotices.md" ]
          [ ! -e "$2/Contents/Resources/AppIcon.icns" ]
          [ "${OPENSTEAMER_EXPECTED_ARCHITECTURES:-}" = "arm64" ]
          [ -f "$4" ]
        SH
        File.binwrite(verifier, verifier_bytes)
        File.chmod(0o500, verifier)
        reference = File.join(root, "approved-reference")
        File.binwrite(reference, "fixture-reference\n")
        File.chmod(0o755, reference)
        Util.capture!("/usr/bin/xattr", "-w", "-x", "com.apple.macl", "00" * 72, app)
        root_xattrs = CopyManifest.capture_published_root_xattrs!(app)
        assert("V90 root metadata baseline is exact and immutable") do
          root_xattrs == Pins.fetch(:APP_ROOT_ALLOWED_XATTRS) && root_xattrs.frozen? &&
            root_xattrs.values.all?(&:frozen?)
        end

        host = RealHost.new
        verify = lambda do
          host.send(
            :verify_v90_bundle_contract!,
            app: app,
            verifier: verifier,
            verifier_sha: Digest::SHA256.hexdigest(verifier_bytes),
            verifier_mode: 0o500,
            manifest: manifest,
            manifest_sha: Util.sha256(manifest),
            manifest_mode: 0o600,
            reference: reference,
            reference_sha: Util.sha256(reference),
            reference_mode: 0o755,
            allowed_root_xattrs: root_xattrs
          )
        end
        assert("V90-compatible production path accepts the no-icon committed schema") { verify.call }

        File.chmod(0o700, verifier)
        File.open(verifier, "ab") { |file| file.write("# drift\n") }
        expect_failure("tampered staged V90 verifier") { verify.call }
        File.binwrite(verifier, verifier_bytes)
        File.chmod(0o500, verifier)

        original_manifest = File.binread(manifest)
        expected_manifest_sha = Util.sha256(manifest)
        verify_with_pinned_manifest = lambda do
          host.send(
            :verify_v90_bundle_contract!,
            app: app,
            verifier: verifier,
            verifier_sha: Digest::SHA256.hexdigest(verifier_bytes),
            verifier_mode: 0o500,
            manifest: manifest,
            manifest_sha: expected_manifest_sha,
            manifest_mode: 0o600,
            reference: reference,
            reference_sha: Digest::SHA256.hexdigest("fixture-reference\n"),
            reference_mode: 0o755,
            allowed_root_xattrs: root_xattrs
          )
        end
        File.open(manifest, "ab") { |file| file.write("drift\n") }
        expect_failure("tampered committed V90 manifest") { verify_with_pinned_manifest.call }
        File.binwrite(manifest, original_manifest)
        File.chmod(0o600, manifest)

        original_notices = File.binread(notices)
        File.open(notices, "ab") { |file| file.write("drift\n") }
        expect_failure("tampered V90 resource") { verify_with_pinned_manifest.call }
        File.binwrite(notices, original_notices)
        File.chmod(0o644, notices)

        expect_failure("missing V90 designated-requirement reference") do
          host.send(
            :verify_v90_bundle_contract!,
            app: app,
            verifier: verifier,
            verifier_sha: Digest::SHA256.hexdigest(verifier_bytes),
            verifier_mode: 0o500,
            manifest: manifest,
            manifest_sha: expected_manifest_sha,
            manifest_mode: 0o600,
            reference: nil,
            reference_sha: Digest::SHA256.hexdigest("fixture-reference\n"),
            reference_mode: 0o755,
            allowed_root_xattrs: root_xattrs
          )
        end

        File.open(reference, "ab") { |file| file.write("drift\n") }
        expect_failure("tampered V90 designated-requirement reference") do
          verify_with_pinned_manifest.call
        end
        File.binwrite(reference, "fixture-reference\n")
        File.chmod(0o755, reference)

        Util.capture!("/usr/bin/xattr", "-w", "-x", "com.apple.macl", "01" + ("00" * 71), app)
        expect_failure("captured V90 root metadata drift") { verify_with_pinned_manifest.call }

        missing_staged = RealHost.new
        missing_staged.instance_variable_set(:@transaction, root)
        expect_failure("transaction cannot fall back to source V90 verifier") do
          missing_staged.send(:v90_bundle_verifier)
        end
        expect_failure("transaction cannot fall back to committed V90 manifest source") do
          missing_staged.send(:v90_copy_manifest)
        end
        expect_failure("transaction cannot fall back to capsule predecessor reference") do
          missing_staged.send(:v90_reference)
        end

        staged_host = RealHost.new
        staged_host.instance_variable_set(:@transaction, root)
        staged_host.instance_variable_set(:@post_stop_v90_verifier, verifier)
        staged_host.instance_variable_set(
          :@post_stop_v90_verifier_identity,
          staged_host.send(:file_identity, verifier)
        )
        staged_host.instance_variable_set(:@post_stop_v90_manifest, manifest)
        staged_host.instance_variable_set(
          :@post_stop_v90_manifest_identity,
          staged_host.send(:file_identity, manifest)
        )
        assert("staged rollback verifier and manifest retain their recorded identities") do
          staged_host.send(:v90_bundle_verifier) == [verifier, 0o500] &&
            staged_host.send(:v90_copy_manifest) == [manifest, 0o600]
        end
        replaced_manifest = manifest + ".replaced"
        File.rename(manifest, replaced_manifest)
        File.binwrite(manifest, original_manifest)
        File.chmod(0o600, manifest)
        expect_failure("same-byte staged V90 manifest inode substitution") do
          staged_host.send(:v90_copy_manifest)
        end
        replaced = verifier + ".replaced"
        File.rename(verifier, replaced)
        File.binwrite(verifier, verifier_bytes)
        File.chmod(0o500, verifier)
        expect_failure("same-byte staged V90 verifier inode substitution") do
          staged_host.send(:v90_bundle_verifier)
        end
      end
      true
    end

    def verify_copy_stable_manifest_fixture!
      source_parent = Dir.mktmpdir("v91-copy-source-", "/Volumes/t7")
      destination_parent = Dir.mktmpdir("v91-copy-destination-")
      source = File.join(source_parent, "Fixture.app")
      destination = File.join(destination_parent, "Fixture.app")
      Dir.mkdir(source, 0o755)
      File.chmod(0o755, source)
      create_copy_manifest_fixture(source)
      source_manifest, source_aliases = CopyManifest.new(source).render
      FileUtils.cp_r(source, destination, preserve: true)
      destination_manifest, destination_aliases = CopyManifest.new(destination).render
      assert("copy fixture crosses filesystems") { File.lstat(source).dev != File.lstat(destination).dev }
      assert("copy-stable manifest ignores copy-variant directory metadata") do
        source_manifest == destination_manifest && source_aliases == destination_aliases
      end
      manifest = Tempfile.new("v91-copy-manifest")
      begin
        manifest.write(source_manifest)
        manifest.flush
        CopyManifest.new(source).verify!(manifest.path)
        CopyManifest.new(destination).verify!(manifest.path)
        File.open(File.join(destination, "Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC"), "ab") do |file|
          file.write("drift")
        end
        expect_failure("copy-stable manifest byte drift") do
          CopyManifest.new(destination).verify!(manifest.path)
        end

        root_xattr = "com.opensteamer.v91-retry-self-test"
        Util.capture!("/usr/bin/xattr", "-w", "-x", root_xattr, "000102", source)
        expect_failure("copy manifest rejects an unreviewed root xattr") do
          CopyManifest.new(source).verify!(manifest.path)
        end
        CopyManifest.new(
          source,
          allowed_root_xattrs: { root_xattr => "000102" }
        ).verify!(manifest.path)
        Util.capture!("/usr/bin/xattr", "-w", "-x", root_xattr, "000103", source)
        expect_failure("copy manifest rejects reviewed root xattr drift") do
          CopyManifest.new(
            source,
            allowed_root_xattrs: { root_xattr => "000102" }
          ).verify!(manifest.path)
        end
      ensure
        manifest.close!
      end
    ensure
      FileUtils.remove_entry(source_parent) if source_parent && File.exist?(source_parent)
      FileUtils.remove_entry(destination_parent) if destination_parent && File.exist?(destination_parent)
    end

    def verify_published_candidate_root_xattrs_fixture!
      expect_failure("installed candidate requires captured root metadata") do
        RealHost.new.send(:verify_installed_candidate_bytes!)
      end
      Dir.mktmpdir("v91-published-root-") do |temporary|
        root = File.join(File.realpath(temporary), "Fixture.app")
        Dir.mkdir(root, 0o755)
        File.chmod(0o755, root)
        create_copy_manifest_fixture(root)
        manifest = File.join(temporary, "copy-manifest.txt")
        File.binwrite(manifest, CopyManifest.new(root).render.first)
        empty_baseline = CopyManifest.capture_published_root_xattrs!(root)
        assert("unlaunched published root retains empty immutable metadata") do
          empty_baseline.empty? && empty_baseline.frozen?
        end
        CopyManifest.new(root, allowed_root_xattrs: empty_baseline).verify!(manifest)
        Util.capture!("/usr/bin/xattr", "-w", "-x", "com.apple.macl", "00" * 72, root)
        expect_failure("staged candidate still rejects launch metadata") do
          CopyManifest.new(root).verify!(manifest)
        end
        expect_failure("empty published baseline cannot acquire new metadata") do
          CopyManifest.new(root, allowed_root_xattrs: empty_baseline).verify!(manifest)
        end
        live_baseline = CopyManifest.capture_published_root_xattrs!(root)
        assert("published root accepts only exact immutable launch metadata") do
          live_baseline == { "com.apple.macl" => "00" * 72 } && live_baseline.frozen? &&
            live_baseline.values.all?(&:frozen?)
        end
        CopyManifest.new(root, allowed_root_xattrs: live_baseline).verify!(manifest)
        ["00" * 71, "00" * 73, "01" + "00" * 71].each do |invalid|
          Util.capture!("/usr/bin/xattr", "-w", "-x", "com.apple.macl", invalid, root)
          expect_failure("published root rejects malformed or nonzero launch metadata") do
            CopyManifest.capture_published_root_xattrs!(root)
          end
          expect_failure("published root rejects changed launch metadata") do
            CopyManifest.new(root, allowed_root_xattrs: live_baseline).verify!(manifest)
          end
        end
        Util.capture!("/usr/bin/xattr", "-d", "com.apple.macl", root)
        expect_failure("published root rejects disappearing launch metadata") do
          CopyManifest.new(root, allowed_root_xattrs: live_baseline).verify!(manifest)
        end
        Util.capture!("/usr/bin/xattr", "-w", "-x", "com.opensteamer.unreviewed", "00", root)
        expect_failure("published root rejects unreviewed metadata") do
          CopyManifest.capture_published_root_xattrs!(root)
        end
        Util.capture!("/usr/bin/xattr", "-d", "com.opensteamer.unreviewed", root)
        Util.capture!("/usr/bin/xattr", "-w", "-x", "com.apple.macl", "00" * 72, root)
        child = File.join(root, "Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC")
        Util.capture!("/usr/bin/xattr", "-w", "-x", "com.apple.macl", "00" * 72, child)
        expect_failure("published root policy does not permit child metadata") do
          CopyManifest.new(root, allowed_root_xattrs: live_baseline).verify!(manifest)
        end
        Util.capture!("/usr/bin/xattr", "-d", "com.apple.macl", child)
        File.open(child, "ab") { |file| file.write("drift") }
        expect_failure("published root policy preserves exact content proof") do
          CopyManifest.new(root, allowed_root_xattrs: live_baseline).verify!(manifest)
        end
      end
    end

    def verify_real_journal_state_machine!
      Dir.mktmpdir("v91-journal-self-test-") do |root|
        success_host = RealHost.new
        success_journal = File.join(root, "success.log")
        File.binwrite(success_journal, "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n")
        success_host.instance_variable_set(:@journal, success_journal)
        RealHost::SUCCESS_STATES.each { |state| success_host.journal!(state) }
        expect_failure("journal rejects states after committed terminal") do
          success_host.journal!("ROLLBACK_STARTED")
        end

        rollback_origins = %w[
          STOP_INTENT INSTALL_HOLDS_VERIFIED V90_STOPPED V90_HELD V91_PUBLISHED
          V91_BOOTSTRAPPED READY_VERIFIED COMMIT_INTENT
        ]
        rollback_origins.each_with_index do |origin, index|
          host = RealHost.new
          journal = File.join(root, "rollback-#{index}.log")
          File.binwrite(journal, "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n")
          host.instance_variable_set(:@journal, journal)
          RealHost::SUCCESS_STATES.each do |state|
            host.journal!(state)
            break if state == origin
          end
          RealHost::ROLLBACK_STATES.each { |state| host.journal!(state) }
          states = File.readlines(journal, chomp: true).drop(1).map { |line| line.split.last }
          assert("real rollback journal terminal #{origin}") do
            states.last(RealHost::ROLLBACK_STATES.length) == RealHost::ROLLBACK_STATES
          end
        end
      end
    end

    def verify_predecessor_signature_layout_fixture!
      data_offset = 56
      data_size = 8
      header = [
        PredecessorReferenceFingerprint::MH_MAGIC_64,
        PredecessorReferenceFingerprint::CPU_TYPE_ARM64,
        0,
        2,
        2,
        24,
        0,
        0
      ].pack("V8")
      ordinary_command = [0x2, 8].pack("V2")
      signature_command = [
        PredecessorReferenceFingerprint::LC_CODE_SIGNATURE,
        16,
        data_offset,
        data_size
      ].pack("V4")
      valid = header + ordinary_command + signature_command + ("s" * data_size)
      assert("predecessor Mach-O signature layout parses") do
        PredecessorReferenceFingerprint.signature_layout(valid) == [data_offset, data_size]
      end

      mutations = {
        "truncated header" => valid.byteslice(0, 31),
        "wrong magic" => ([0, PredecessorReferenceFingerprint::CPU_TYPE_ARM64] +
          [0, 2, 2, 24, 0, 0]).pack("V8") + valid.byteslice(32..),
        "wrong architecture" => ([PredecessorReferenceFingerprint::MH_MAGIC_64, 7] +
          [0, 2, 2, 24, 0, 0]).pack("V8") + valid.byteslice(32..),
        "missing signature" => ([
          PredecessorReferenceFingerprint::MH_MAGIC_64,
          PredecessorReferenceFingerprint::CPU_TYPE_ARM64,
          0, 2, 1, 8, 0, 0
        ].pack("V8") + ordinary_command + ("s" * data_size)),
        "duplicate signature" => ([
          PredecessorReferenceFingerprint::MH_MAGIC_64,
          PredecessorReferenceFingerprint::CPU_TYPE_ARM64,
          0, 2, 2, 32, 0, 0
        ].pack("V8") + signature_command + signature_command + ("s" * data_size)),
        "invalid signature command size" => (header + ordinary_command + [
          PredecessorReferenceFingerprint::LC_CODE_SIGNATURE, 8
        ].pack("V2") + ("s" * 16))
      }
      mutations.each do |label, bytes|
        expect_failure("predecessor Mach-O parser rejects #{label}") do
          PredecessorReferenceFingerprint.signature_layout(bytes)
        end
      end
    end

    def verify_predecessor_codesign_metadata_fixture!
      parser = PredecessorReferenceFingerprint
      metadata = (
        "Executable=/fixture/CaptureServer\n" \
        "Identifier=com.example.expected\n" \
        "Signed Time=Sep 19, 2026 at 10:02:48 \xE2\x80\xAFPM\n"
      ).dup.force_encoding(Encoding::US_ASCII)
      assert("predecessor codesign metadata field parses on pinned system Ruby") do
        parser.send(
          :exact_field!,
          metadata,
          "Identifier=",
          "com.example.expected",
          "fixture predecessor"
        )
        true
      end
      expect_failure("predecessor codesign metadata rejects duplicate fields") do
        parser.send(
          :exact_field!,
          metadata + "Identifier=com.example.expected\n",
          "Identifier=",
          "com.example.expected",
          "fixture predecessor"
        )
      end
      expect_failure("predecessor codesign metadata rejects mismatched fields") do
        parser.send(
          :exact_field!,
          metadata,
          "Identifier=",
          "com.example.hostile",
          "fixture predecessor"
        )
      end
    end

    def verify_dynamic_codesign_metadata_fixture!
      metadata = (
        "Executable=/fixture/CaptureServer\n" \
        "Identifier=#{Pins.fetch(:EXECUTABLE_IDENTIFIER)}\n" \
        "Signed Time=Sep 19, 2026 at 10:02:48 \xE2\x80\xAFPM\n" \
        "TeamIdentifier=#{Pins.fetch(:TEAM_ID)}\n" \
        "CDHash=#{Pins.fetch(:V90_CDHASH).upcase}\n"
      ).dup.force_encoding(Encoding::US_ASCII)
      host = RealHost.allocate
      assert("dynamic codesign identity parses non-ASCII metadata on pinned system Ruby") do
        host.send(
          :verify_dynamic_codesign_identity!,
          metadata,
          expected_cdhash: Pins.fetch(:V90_CDHASH)
        )
      end
      expect_failure("dynamic codesign identity rejects duplicate fields") do
        host.send(
          :verify_dynamic_codesign_identity!,
          metadata + "Identifier=#{Pins.fetch(:EXECUTABLE_IDENTIFIER)}\n",
          expected_cdhash: Pins.fetch(:V90_CDHASH)
        )
      end
      expect_failure("dynamic codesign identity rejects wrong CDHash") do
        host.send(
          :verify_dynamic_codesign_identity!,
          metadata,
          expected_cdhash: "0" * 40
        )
      end
    end

    def close_journal!(host)
      io = host.instance_variable_get(:@journal_io)
      io.close if io && !io.closed?
    end

    def seed_journal!(host, states)
      states.each { |state| host.journal!(state) }
      host
    end

    def verify_journal_fault_reconciliation!
      scenarios = {
        "STOP_INTENT" => %w[BEGUN INPUTS_VERIFIED],
        "V91_COMMIT_IRREVERSIBLE" => %w[
          BEGUN INPUTS_VERIFIED STOP_INTENT INSTALL_HOLDS_VERIFIED V90_STOPPED V90_HELD
          V91_PUBLISHED V91_BOOTSTRAPPED READY_VERIFIED COMMIT_INTENT
        ],
        "COMMITTED_V91" => RealHost::SUCCESS_STATES[0...-1],
        "ROLLED_BACK_EXACT_V90" => %w[
          BEGUN INPUTS_VERIFIED STOP_INTENT INSTALL_HOLDS_VERIFIED V90_STOPPED
          ROLLBACK_STARTED V91_STOPPED FAILED_V91_ARCHIVED V90_RESTORED V90_BOOTSTRAPPED
        ]
      }
      Dir.mktmpdir("v91-journal-faults-") do |root|
        scenarios.each_with_index do |(target, prior), index|
          path = File.join(root, "journal-#{index}.log")
          File.binwrite(path, "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n")
          host = RealHost.new
          host.instance_variable_set(:@journal, path)
          host.instance_variable_set(:@journal_identity, host.send(:file_identity, path))
          seed_journal!(host, prior)
          base = host.method(:strict_fsync_io!)
          injected = false
          host.define_singleton_method(:strict_fsync_io!) do |io, label|
            base.call(io, label)
            if !injected && label == "V91 journal #{target}"
              injected = true
              raise Errno::EIO, "injected post-fsync acknowledgement failure"
            end
            true
          end
          expect_failure("full visible journal fsync error #{target}") { host.journal!(target) }
          states = host.send(:parse_journal_bytes!, host.send(:read_journal_bytes!))
          assert("full journal record advances conservatively #{target}") { states == prior + [target] }
          assert("full journal record advances memory conservatively #{target}") do
            host.instance_variable_get(:@last_journal_state) == target
          end
          if %w[V91_COMMIT_IRREVERSIBLE COMMITTED_V91].include?(target)
            expect_failure("rollback rejected after #{target}") { host.journal!("ROLLBACK_STARTED") }
          end
          close_journal!(host)
        end


        path = File.join(root, "prefsync-eio.log")
        File.binwrite(path, "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n")
        host = RealHost.new
        host.instance_variable_set(:@journal, path)
        host.instance_variable_set(:@journal_identity, host.send(:file_identity, path))
        prior = RealHost::SUCCESS_STATES.take_while { |state| state != "V91_COMMIT_IRREVERSIBLE" }
        seed_journal!(host, prior)
        base = host.method(:strict_fsync_io!)
        injected = false
        host.define_singleton_method(:strict_fsync_io!) do |io, label|
          if !injected && label == "V91 journal V91_COMMIT_IRREVERSIBLE"
            injected = true
            raise Errno::EIO, "injected true pre-fsync failure"
          end
          base.call(io, label)
        end
        expect_failure("true pre-fsync EIO is never success") do
          host.journal!("V91_COMMIT_IRREVERSIBLE")
        end
        assert("pre-fsync EIO forbids rollback conservatively") do
          host.send(:irreversible_on_disk?) &&
            host.instance_variable_get(:@last_journal_state) == "V91_COMMIT_IRREVERSIBLE"
        end
        close_journal!(host)

        path = File.join(root, "torn.log")
        File.binwrite(path, "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n")
        host = RealHost.new
        host.instance_variable_set(:@journal, path)
        host.instance_variable_set(:@journal_identity, host.send(:file_identity, path))
        seed_journal!(host, %w[BEGUN INPUTS_VERIFIED])
        before = host.send(:read_journal_bytes!)
        base_write = host.method(:write_all!)
        injected = false
        host.define_singleton_method(:write_all!) do |io, bytes, label|
          if !injected && label == "V91 journal STOP_INTENT"
            injected = true
            io.write(bytes.byteslice(0, bytes.bytesize / 2))
            io.flush
            raise Failure, "injected torn append"
          end
          base_write.call(io, bytes, label)
        end
        expect_failure("torn journal record") { host.journal!("STOP_INTENT") }
        assert("torn journal record is truncated exactly") { host.send(:read_journal_bytes!) == before }
        assert("torn record does not advance memory state") do
          host.instance_variable_get(:@last_journal_state) == "INPUTS_VERIFIED"
        end
        close_journal!(host)

        path = File.join(root, "replacement.log")
        moved = File.join(root, "replacement.original.log")
        File.binwrite(path, "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n")
        host = RealHost.new
        host.instance_variable_set(:@journal, path)
        host.instance_variable_set(:@journal_identity, host.send(:file_identity, path))
        seed_journal!(host, %w[BEGUN INPUTS_VERIFIED STOP_INTENT])
        File.rename(path, moved)
        File.binwrite(path, "#{Pins.fetch(:V91_JOURNAL_HEADER)}\n")
        expect_failure("journal pathname replacement") { host.send(:irreversible_on_disk?) }
        close_journal!(host)
      end
    end

    def verify_atomic_pointer_fixture!
      Dir.mktmpdir("v91-pointer-") do |root|
        path = File.join(root, "pointer")
        contents = "/private/txn-v91\n"
        host = RealHost.new
        identity = host.send(:publish_owned_pointer!, path, contents)
        assert("atomic pointer exact bytes") { File.binread(path) == contents }
        assert("atomic pointer mode") { (File.lstat(path).mode & 0o7777) == 0o600 }
        assert("atomic pointer identity") { host.send(:identity_matches?, path, identity) }
        File.unlink(path)

        host = RealHost.new
        base_write = host.method(:write_durable)
        injected = false
        host.define_singleton_method(:write_durable) do |target, bytes, mode, exclusive:, &identity_block|
          if !injected && File.basename(target).include?(".pointer.")
            injected = true
            flags = File::WRONLY | File::CREAT | File::EXCL
            File.open(target, flags, mode) do |file|
              stat = file.stat
              identity_block&.call([stat.dev, stat.ino, stat.ftype])
              file.write(bytes.byteslice(0, bytes.bytesize / 2))
              file.flush
              file.fsync
            end
            raise Failure, "injected partial pointer write"
          end
          base_write.call(target, bytes, mode, exclusive: exclusive, &identity_block)
        end
        expect_failure("partial pointer write") { host.send(:publish_owned_pointer!, path, contents) }
        assert("partial pointer never becomes public") { !File.exist?(path) }
        assert("partial pointer temporary is removed") { Dir.children(root).empty? }

        host = RealHost.new
        base_sync = host.method(:strict_fsync_directory!)
        injected = false
        host.define_singleton_method(:strict_fsync_directory!) do |directory, label|
          base_sync.call(directory, label)
          if !injected && label == "exclusive rename parent"
            injected = true
            raise Failure, "injected post-rename parent fsync acknowledgement failure"
          end
          true
        end
        identity = host.send(:publish_owned_pointer!, path, contents)
        assert("post-rename pointer error reconciles exact final inode") do
          host.send(:identity_matches?, path, identity) && File.binread(path) == contents
        end
        assert("post-rename reconciliation leaves no temporary") { Dir.children(root) == ["pointer"] }
      end
    end

    def verify_real_inode_recovery_fixture!
      2.times do |variant|
        Dir.mktmpdir("v91-inode-recovery-") do |root|
          host = RealHost.new
          live_app = File.join(root, "live.app")
          backup_app = File.join(root, "backup.app")
          staged_app = File.join(root, "staged.app")
          failed_app = File.join(root, "failed.app")
          live_plist = File.join(root, "live.plist")
          backup_plist = File.join(root, "backup.plist")
          staged_plist = File.join(root, "staged.plist")
          failed_plist = File.join(root, "failed.plist")
          Dir.mkdir(live_app)
          File.binwrite(File.join(live_app, "v90"), "v90")
          File.binwrite(live_plist, "v90-plist")
          Dir.mkdir(staged_app)
          File.binwrite(File.join(staged_app, "v91"), "v91")
          File.binwrite(staged_plist, "v91-plist")
          v90_app = host.send(:file_identity, live_app)
          v90_plist = host.send(:file_identity, live_plist)
          v91_app = host.send(:file_identity, staged_app)
          v91_plist = host.send(:file_identity, staged_plist)

          host.send(:exclusive_rename, live_app, backup_app)
          if variant == 1
            host.send(:exclusive_rename, live_plist, backup_plist)
            host.send(:exclusive_rename, staged_app, live_app)
          end
          host.send(:archive_candidate_exact!, v91_app, [live_app, staged_app], failed_app, "fixture V91 app")
          host.send(:archive_candidate_exact!, v91_plist, [live_plist, staged_plist], failed_plist, "fixture V91 plist")
          host.send(:restore_predecessor_exact!, live_app, backup_app, v90_app, "fixture V90 app")
          host.send(:restore_predecessor_exact!, live_plist, backup_plist, v90_plist, "fixture V90 plist")
          assert("real recovery restores V90 app variant #{variant}") do
            host.send(:identity_matches?, live_app, v90_app)
          end
          assert("real recovery restores V90 plist variant #{variant}") do
            host.send(:identity_matches?, live_plist, v90_plist)
          end
          assert("real recovery archives V91 app variant #{variant}") do
            host.send(:identity_matches?, failed_app, v91_app)
          end
          assert("real recovery archives V91 plist variant #{variant}") do
            host.send(:identity_matches?, failed_plist, v91_plist)
          end
          host.send(:archive_candidate_exact!, v91_app, [live_app, staged_app], failed_app, "fixture V91 app")
          host.send(:restore_predecessor_exact!, live_app, backup_app, v90_app, "fixture V90 app")
        end
      end

      Dir.mktmpdir("v91-inode-collision-") do |root|
        host = RealHost.new
        staged = File.join(root, "staged.plist")
        live = File.join(root, "live.plist")
        archive = File.join(root, "failed.plist")
        File.binwrite(staged, "candidate")
        File.link(staged, live)
        identity = host.send(:file_identity, staged)
        expect_failure("duplicate candidate inode locations") do
          host.send(:archive_candidate_exact!, identity, [live, staged], archive, "duplicate fixture")
        end
      end


      %i[app plist].each do |kind|
        Dir.mktmpdir("v91-reported-rename-") do |root|
          host = RealHost.new
          source = File.join(root, kind == :app ? "candidate.app" : "candidate.plist")
          live = File.join(root, kind == :app ? "live.app" : "live.plist")
          failed = File.join(root, kind == :app ? "failed.app" : "failed.plist")
          kind == :app ? Dir.mkdir(source) : File.binwrite(source, "candidate")
          identity = host.send(:file_identity, source)
          base = host.method(:strict_fsync_directory!)
          injected = false
          host.define_singleton_method(:strict_fsync_directory!) do |directory, label|
            base.call(directory, label)
            if !injected && label == "exclusive rename parent"
              injected = true
              raise Failure, "injected post-rename sync acknowledgement failure"
            end
            true
          end
          expect_failure("reported #{kind} publish rename failure") do
            host.send(:exclusive_rename, source, live)
          end
          assert("reported #{kind} rename moved exact inode") do
            host.send(:identity_matches?, live, identity) && !File.exist?(source)
          end
          host.send(:archive_candidate_exact!, identity, [live, source], failed, "reported #{kind}")
          assert("reported #{kind} rename recovers exact inode") do
            host.send(:identity_matches?, failed, identity)
          end
        end
      end
    end

    def verify_recursive_fsync_fixture!
      Dir.mktmpdir("v91-fsync-tree-") do |root|
        app = File.join(root, "Fixture.app")
        nested = File.join(app, "Contents/Deep")
        FileUtils.mkdir_p(nested)
        top_file = File.join(app, "top")
        deep_file = File.join(nested, "deep")
        sentinel = File.join(root, "external-sentinel")
        File.binwrite(top_file, "top")
        File.binwrite(deep_file, "deep")
        File.binwrite(sentinel, "outside")
        File.symlink(sentinel, File.join(nested, "alias"))
        host = RealHost.new
        regular = host.method(:strict_fsync_regular!)
        directory = host.method(:strict_fsync_directory!)
        events = []
        host.define_singleton_method(:strict_fsync_regular!) do |path, label|
          events << [:file, path]
          regular.call(path, label)
        end
        host.define_singleton_method(:strict_fsync_directory!) do |path, label|
          events << [:dir, path]
          directory.call(path, label)
        end
        host.send(:durably_sync_tree!, app)
        assert("fsync barrier covers each real file once") do
          events.count([:file, top_file]) == 1 && events.count([:file, deep_file]) == 1
        end
        assert("fsync barrier never follows symlink target") { !events.include?([:file, sentinel]) }
        assert("fsync barrier orders child directory before root") do
          events.index([:dir, nested]) < events.index([:dir, app]) && events.last == [:dir, app]
        end

        host = RealHost.new
        regular = host.method(:strict_fsync_regular!)
        host.define_singleton_method(:strict_fsync_regular!) do |path, label|
          raise Failure, "injected deep-file fsync failure" if path == deep_file
          regular.call(path, label)
        end
        expect_failure("strict recursive fsync failure") { host.send(:durably_sync_tree!, app) }

        invalid = Object.new
        invalid.define_singleton_method(:fsync) { raise Errno::EINVAL, "injected unsupported fsync" }
        expect_failure("strict fsync rejects EINVAL") do
          RealHost.new.send(:strict_fsync_io!, invalid, "fixture strict fsync")
        end
      end
    end

    def verify_full_durability_barrier_fixture!
      Dir.mktmpdir("v91-full-fsync-barrier-") do |root|
        app = File.join(root, "Fixture.app")
        plist = File.join(root, "candidate.plist")
        Dir.mkdir(app)
        payload = File.join(app, "payload")
        File.binwrite(payload, "original")
        File.binwrite(plist, "plist")
        host = RealHost.new
        host.instance_variable_set(:@staged_app, app)
        host.instance_variable_set(:@staged_plist, plist)
        events = []
        verifies = 0
        host.define_singleton_method(:verify_staged_candidate!) do |_capsule|
          verifies += 1
          events << :verify
          raise Failure, "mutation detected by final replay" if verifies == 2 && File.binread(payload) != "original"
          true
        end
        host.define_singleton_method(:durably_sync_tree!) do |_path|
          events << :tree
          File.binwrite(payload, "mutated")
          true
        end
        host.define_singleton_method(:strict_fsync_directory!) do |_path, label|
          events << label
          true
        end
        host.define_singleton_method(:strict_fsync_regular!) do |_path, label|
          events << label
          true
        end
        expect_failure("mutation between fsync and replay") do
          host.send(:durably_sync_staged_candidate!, Object.new)
        end
        assert("durability barrier orders verify-sync-parent-plist-parent-verify") do
          events == [
            :verify,
            :tree,
            "staged candidate parent",
            "staged V91 launch plist",
            "staged launch-plist parent",
            :verify
          ]
        end
      end
    end

    def verify_staged_install_layout_fixture!
      token = "12345678-1234-4123-8123-123456789abc"
      root = "/Applications/.opensteamer-paired-v91-install-#{token}"
      app = File.join(root, "opensteamer Host.app")
      build = lambda do |candidate_token: token, candidate_root: root, candidate_app: app|
        host = RealHost.new
        host.instance_variable_set(:@token, candidate_token)
        host.instance_variable_set(:@staged_root, candidate_root)
        host.instance_variable_set(:@staged_app, candidate_app)
        host
      end
      assert("staged install hold preserves the production bundle basename") do
        build.call.send(:verify_staged_install_layout!)
      end
      expect_failure("staged install hold malformed token") do
        build.call(candidate_token: "not-a-uuid").send(:verify_staged_install_layout!)
      end
      expect_failure("staged install hold escaped root") do
        build.call(candidate_root: "/private/tmp/.opensteamer-paired-v91-install-#{token}")
             .send(:verify_staged_install_layout!)
      end
      expect_failure("staged install hold wrong bundle basename") do
        build.call(candidate_app: File.join(root, "hidden.app")).send(:verify_staged_install_layout!)
      end

      Dir.mktmpdir("v91-install-hold-") do |parent|
        hold = File.join(parent, "private-hold")
        staged = File.join(hold, "opensteamer Host.app")
        Dir.mkdir(hold, 0o700)
        Dir.mkdir(staged, 0o755)
        File.chmod(0o700, hold)
        File.chmod(0o755, staged)
        host = RealHost.new
        hold_identity = host.send(:file_identity, hold)
        staged_identity = host.send(:file_identity, staged)
        assert("private install hold exact metadata and topology") do
          host.send(:verify_private_install_hold!, hold, staged, hold_identity, staged_identity)
        end
        foreign = File.join(hold, "foreign")
        File.binwrite(foreign, "unexpected")
        expect_failure("private install hold rejects foreign child") do
          host.send(:verify_private_install_hold!, hold, staged, hold_identity, staged_identity)
        end
        File.unlink(foreign)
        File.chmod(0o755, hold)
        expect_failure("private install hold rejects public root mode") do
          host.send(:verify_private_install_hold!, hold, staged, hold_identity, staged_identity)
        end
      end
    end

    def verify_cross_parent_rename_fsync_fixture!
      Dir.mktmpdir("v91-cross-parent-rename-") do |root|
        source_parent = File.join(root, "source")
        destination_parent = File.join(root, "destination")
        Dir.mkdir(source_parent)
        Dir.mkdir(destination_parent)
        source = File.join(source_parent, "payload")
        destination = File.join(destination_parent, "payload")
        File.binwrite(source, "candidate")
        host = RealHost.new
        syncs = []
        base = host.method(:strict_fsync_directory!)
        host.define_singleton_method(:strict_fsync_directory!) do |directory, label|
          base.call(directory, label)
          syncs << [directory, label]
          true
        end
        host.send(:exclusive_rename, source, destination)
        assert("cross-parent rename syncs source then destination directory") do
          syncs == [
            [source_parent, "exclusive rename source parent"],
            [destination_parent, "exclusive rename parent"]
          ]
        end
      end
    end

    def configure_topology_fixture!(host, runtime_root)
      update_root = File.join(runtime_root, "updates")
      lock_path = File.join(runtime_root, "lock")
      transaction = File.join(update_root, "transaction")
      helpers = File.join(transaction, "helpers")
      module_cache = File.join(transaction, "module-cache")
      compiler_tmp = File.join(transaction, "compiler-tmp")
      [update_root, lock_path].each { |path| Dir.mkdir(path, 0o700) }
      Dir.mkdir(transaction, 0o700)
      [helpers, module_cache, compiler_tmp].each { |path| Dir.mkdir(path, 0o700) }
      {
        update_root: update_root,
        lock_path: lock_path,
        transaction: transaction,
        helpers: helpers,
        module_cache: module_cache,
        compiler_tmp: compiler_tmp
      }.tap do |paths|
        host.instance_variable_set(:@update_root_identity, host.send(:file_identity, update_root))
        host.instance_variable_set(:@lock_identity, host.send(:file_identity, lock_path))
        host.instance_variable_set(:@transaction, transaction)
        host.instance_variable_set(:@transaction_identity, host.send(:file_identity, transaction))
        host.instance_variable_set(:@post_stop_helpers_root, helpers)
        host.instance_variable_set(:@post_stop_helpers_root_identity, host.send(:file_identity, helpers))
        host.instance_variable_set(:@route_monitor_module_cache_path, module_cache)
        host.instance_variable_set(
          :@route_monitor_module_cache_identity,
          host.send(:file_identity, module_cache)
        )
        host.instance_variable_set(:@route_monitor_compiler_tmp_path, compiler_tmp)
        host.instance_variable_set(
          :@route_monitor_compiler_tmp_identity,
          host.send(:file_identity, compiler_tmp)
        )
      end
    end

    def verify_transaction_topology_fixture!
      Dir.mktmpdir("v91-topology-") do |runtime_root|
        host = RealHost.new
        paths = configure_topology_fixture!(host, runtime_root)
        base = host.method(:strict_fsync_directory!)
        events = []
        host.define_singleton_method(:strict_fsync_directory!) do |path, label|
          events << [path, label]
          base.call(path, label)
        end
        host.send(
          :durably_sync_transaction_topology!,
          runtime_root: runtime_root,
          update_root: paths.fetch(:update_root),
          lock_path: paths.fetch(:lock_path)
        )
        indices = events.each_with_index.to_h
        child_events = %i[helpers module_cache compiler_tmp].map do |name|
          events.find { |path, _label| path == paths.fetch(name) }
        end
        transaction_event = events.find { |path, _label| path == paths.fetch(:transaction) }
        update_event = events.find { |path, _label| path == paths.fetch(:update_root) }
        lock_event = events.find { |path, _label| path == paths.fetch(:lock_path) }
        runtime_event = events.find { |path, _label| path == runtime_root }
        assert("transaction topology covers every required directory exactly once") do
          required = child_events + [transaction_event, update_event, lock_event, runtime_event]
          required.none?(&:nil?) && required.all? { |event| events.count(event) == 1 }
        end
        assert("transaction topology is synced child to parent") do
          child_events.all? { |event| indices.fetch(event) < indices.fetch(transaction_event) } &&
            indices.fetch(transaction_event) < indices.fetch(update_event) &&
            indices.fetch(update_event) < indices.fetch(runtime_event) &&
            indices.fetch(lock_event) < indices.fetch(runtime_event)
        end
      end

      Dir.mktmpdir("v91-topology-fault-") do |runtime_root|
        host = RealHost.new
        paths = configure_topology_fixture!(host, runtime_root)
        base = host.method(:strict_fsync_directory!)
        events = []
        host.define_singleton_method(:strict_fsync_directory!) do |path, label|
          events << path
          raise Failure, "injected update-root sync failure" if path == paths.fetch(:update_root)
          base.call(path, label)
        end
        expect_failure("transaction topology parent fsync failure") do
          host.send(
            :durably_sync_transaction_topology!,
            runtime_root: runtime_root,
            update_root: paths.fetch(:update_root),
            lock_path: paths.fetch(:lock_path)
          )
        end
        assert("topology failure cannot reach runtime-root certification") do
          !events.include?(runtime_root)
        end
      end
    end

    def verify_write_durable_mode_fixture!
      Dir.mktmpdir("v91-write-durable-") do |root|
        path = File.join(root, "executable")
        host = RealHost.new
        base_mode = host.method(:set_durable_mode!)
        base_sync = host.method(:strict_fsync_io!)
        events = []
        host.define_singleton_method(:set_durable_mode!) do |io, mode, label|
          events << [:chmod, label]
          base_mode.call(io, mode, label)
        end
        host.define_singleton_method(:strict_fsync_io!) do |io, label|
          events << [:fsync, label]
          base_sync.call(io, label)
        end
        host.send(:write_durable, path, "payload", 0o755, exclusive: true)
        label = "durable file #{path}"
        assert("durable chmod precedes file fsync") do
          events.index([:chmod, label]) < events.index([:fsync, label])
        end
        assert("durable file has exact requested mode") { (File.lstat(path).mode & 0o7777) == 0o755 }
      end

      Dir.mktmpdir("v91-write-durable-chmod-fault-") do |root|
        path = File.join(root, "file")
        host = RealHost.new
        identity = nil
        host.define_singleton_method(:set_durable_mode!) do |_io, _mode, _label|
          raise Failure, "injected chmod failure"
        end
        expect_failure("durable chmod failure") do
          host.send(:write_durable, path, "payload", 0o755, exclusive: true) do |created|
            identity = created
          end
        end
        assert("chmod failure records ownership before failing") do
          identity && host.send(:identity_matches?, path, identity)
        end
      end

      Dir.mktmpdir("v91-write-durable-fsync-fault-") do |root|
        path = File.join(root, "file")
        host = RealHost.new
        base = host.method(:strict_fsync_io!)
        host.define_singleton_method(:strict_fsync_io!) do |io, label|
          raise Failure, "injected file fsync failure" if label == "durable file #{path}"
          base.call(io, label)
        end
        expect_failure("durable file fsync failure") do
          host.send(:write_durable, path, "payload", 0o600, exclusive: true)
        end
      end
    end

    def verify_creation_signal_gap_fixture!
      Dir.mktmpdir("v91-directory-signal-") do |root|
        path = File.join(root, "owned")
        entered = Queue.new
        release = Queue.new
        host = RealHost.new
        host.define_singleton_method(:after_directory_create_before_identity!) do |_created|
          entered << true
          release.pop
          true
        end
        identity = nil
        worker_error = nil
        worker = Thread.new do
          Thread.current.report_on_exception = false
          begin
            host.send(:create_owned_directory!, path, 0o700, "fixture parent") do |created|
              identity = created
            end
          rescue Exception => error # rubocop:disable Lint/RescueException
            worker_error = error
          end
        end
        entered.pop
        worker.raise(Interrupt, "injected create gap interrupt")
        release << true
        worker.join(5)
        assert("directory create-gap worker exits") { !worker.alive? && worker_error.is_a?(Interrupt) }
        assert("directory ownership is published before deferred interrupt") do
          identity && host.send(:identity_matches?, path, identity)
        end
        host.send(:remove_empty_directory_exact!, path, identity)
        assert("directory create-gap residue is exactly removable") { !File.exist?(path) }
      ensure
        worker.kill if worker&.alive?
      end

      Dir.mktmpdir("v91-file-signal-") do |root|
        path = File.join(root, "owned")
        entered = Queue.new
        release = Queue.new
        host = RealHost.new
        host.define_singleton_method(:after_file_create_before_identity!) do |_created|
          entered << true
          release.pop
          true
        end
        identity = nil
        worker_error = nil
        worker = Thread.new do
          Thread.current.report_on_exception = false
          begin
            host.send(:write_durable, path, "payload", 0o600, exclusive: true) do |created|
              identity = created
            end
          rescue Exception => error # rubocop:disable Lint/RescueException
            worker_error = error
          end
        end
        entered.pop
        worker.raise(Interrupt, "injected file create gap interrupt")
        release << true
        worker.join(5)
        assert("file create-gap worker exits") { !worker.alive? && worker_error.is_a?(Interrupt) }
        assert("file ownership is published before deferred interrupt") do
          identity && host.send(:identity_matches?, path, identity)
        end
        host.send(:unlink_exact!, path, identity, expected_contents: "payload")
        assert("file create-gap residue is exactly removable") { !File.exist?(path) }
      ensure
        worker.kill if worker&.alive?
      end
    end

    def write_session_fence_log(path, pid, nonce)
      File.binwrite(
        path,
        "fixture-marker=A\n" \
        "Worldwide paired-device availability is online pid=#{pid} nonce=#{nonce}\n" \
        "Worldwide peer returned to idle\n"
      )
      File.chmod(0o600, path)
      true
    end

    def verify_session_fence_fixture!
      pid = 12_345
      nonce = "f" * 64
      Dir.mktmpdir("v91-session-fence-") do |root|
        path = File.join(root, "host.log")
        write_session_fence_log(path, pid, nonce)
        baseline = SessionFence.observe!(path, pid, nonce)
        File.open(path, "ab") { |file| file.write("health sample\n") }
        advanced = SessionFence.observe!(path, pid, nonce, prior: baseline)
        assert("session fence accepts append-only quiescent evidence") do
          advanced.size > baseline.size && advanced.last_reset_offset == baseline.last_reset_offset
        end

        candidate_pid = pid + 1
        candidate_nonce = "e" * 64
        File.open(path, "ab") do |file|
          file.write("Worldwide availability is waiting for the paired iPhone\n")
          file.write(
            "Worldwide paired-device availability is online " \
            "pid=#{candidate_pid} nonce=#{candidate_nonce}\n"
          )
        end
        candidate = SessionFence.observe!(
          path,
          candidate_pid,
          candidate_nonce,
          prior: advanced,
          fresh_generation: true
        )
        assert("session fence accepts one append-only candidate generation boundary") do
          candidate.last_reset_offset >= advanced.size
        end
        File.open(path, "ab") { |file| file.write("candidate health sample\n") }
        stable_candidate = SessionFence.observe!(
          path,
          candidate_pid,
          candidate_nonce,
          prior: candidate
        )
        assert("candidate session fence returns to same-generation stability") do
          stable_candidate.last_reset_offset == candidate.last_reset_offset
        end
        expect_failure("session fence requires a new boundary for another generation transition") do
          SessionFence.observe!(
            path,
            candidate_pid,
            candidate_nonce,
            prior: stable_candidate,
            fresh_generation: true
          )
        end

        File.open(path, "ab") do |file|
          file.write("Worldwide authenticated media route selected\n")
          file.write("Worldwide peer returned to idle\n")
        end
        expect_failure("session fence rejects a new reset boundary") do
          SessionFence.observe!(path, pid, nonce, prior: advanced)
        end
      end

      Dir.mktmpdir("v91-session-rewrite-") do |root|
        path = File.join(root, "host.log")
        write_session_fence_log(path, pid, nonce)
        baseline = SessionFence.observe!(path, pid, nonce)
        File.open(path, "r+b") do |file|
          offset = File.binread(path).index("A")
          file.pwrite("B", offset)
          file.flush
        end
        expect_failure("session fence rejects same-size historical rewrite") do
          SessionFence.observe!(path, pid, nonce, prior: baseline)
        end
      end

      Dir.mktmpdir("v91-session-stream-") do |root|
        path = File.join(root, "host.log")
        chunk = SessionFence::READ_CHUNK_BYTES
        online = "Worldwide paired-device availability is online pid=#{pid} nonce=#{nonce}\n"
        ended = "Worldwide media ended; the Mac remains available for the paired iPhone\n"
        contents = "x" * (chunk - 11) + online
        contents << "x" * (2 * chunk - 15 - contents.bytesize)
        contents << "Worldwide viewer disconnected\npeerConnected=true controlOpen=true\n"
        contents << "Stopping screen video capture\n"
        contents << "x" * (3 * chunk - 17 - contents.bytesize)
        expected_reset = contents.bytesize
        contents << ended
        File.binwrite(path, contents)
        File.chmod(0o600, path)
        baseline = SessionFence.observe!(path, pid, nonce)
        assert("streaming fence finds generation and final teardown markers across chunk boundaries") do
          baseline.last_reset_offset == expected_reset &&
            baseline.digest == Digest::SHA256.hexdigest(contents) && baseline.size == contents.bytesize
        end
        assert("late connected heartbeat before final host teardown is superseded") do
          baseline.last_reset_offset > contents.index("peerConnected=true")
        end
        File.open(path, "ab") { |file| file.write("health sample\n") }
        appended = SessionFence.observe!(path, pid, nonce, prior: baseline)
        assert("streaming prefix digest accepts a partial final prior chunk") do
          appended.digest == Digest::SHA256.hexdigest(contents + "health sample\n")
        end
        SessionFence::UNSAFE_MARKERS.each do |marker|
          File.binwrite(path, contents)
          File.open(path, "ab") do |file|
            file.write("x" * (4 * chunk - 5 - contents.bytesize))
            file.write(marker + "\n")
          end
          expect_failure("streaming fence rejects post-teardown active marker across chunk boundary: #{marker}") do
            SessionFence.observe!(path, pid, nonce, prior: baseline)
          end
        end
        File.binwrite(path, contents)
        File.open(path, "r+b") { |file| file.pwrite("y", chunk + online.bytesize) }
        expect_failure("streaming fence rejects multi-chunk same-size prefix rewrite") do
          SessionFence.observe!(path, pid, nonce, prior: baseline)
        end
        File.binwrite(path, contents)
        File.truncate(path, baseline.size - 1)
        expect_failure("streaming fence rejects truncated historical prefix") do
          SessionFence.observe!(path, pid, nonce, prior: baseline)
        end
      end
    end

    def stability_harness(fail_probe: nil, fail_call: nil, sample_seconds: 0.0)
      host = RealHost.new
      files = (Pins.fetch(:PREDECESSOR_IDENTITY_PATHS) + [Pins.fetch(:LAUNCH_AGENT)]).each_with_index.to_h do |path, index|
        [path, [1, index + 10, path == Pins.fetch(:LIVE_APP) ? "directory" : "file"]]
      end
      host.instance_variable_set(:@predecessor_runtime, PredecessorRuntimeSnapshot.new(
        pid: 12_344, runs: 1, start: "Thu Sep 24 12:04:54 2026", nonce: "d" * 64,
        files: files, lock_directory: [1, 30, "directory"], lock_file: [1, 31, "file"]
      ))
      counters = Hash.new(0)
      clock = [0.0]
      fail_now = lambda do |probe|
        counters[probe] += 1
        counters[probe] == fail_call && probe == fail_probe
      end
      pid = 12_345
      nonce = "a" * 64
      host.instance_variable_set(:@candidate_cdhash, "b" * 40)
      host.define_singleton_method(:launch_identity) do
        bad = fail_now.call(:launch)
        bad ? [pid + 1, 1] : [pid, 1]
      end
      host.define_singleton_method(:strict_lock_record) do |**_arguments|
        bad = fail_now.call(:lock)
        bad ? { pid: pid, nonce: "c" * 64 } : { pid: pid, nonce: nonce }
      end
      host.define_singleton_method(:verify_dynamic_process!) do |_pid, **_arguments|
        raise Failure, "process drift" if fail_now.call(:process)
        true
      end
      host.define_singleton_method(:capture_candidate_root_xattrs!) do
        @candidate_root_xattrs ||= {}.freeze
      end
      host.define_singleton_method(:verify_installed_candidate_bytes!) do
        raise Failure, "byte drift" if fail_now.call(:bytes)
        true
      end
      host.define_singleton_method(:readiness_generation!) do
        bad = fail_now.call(:readiness)
        clock[0] += sample_seconds
        bad ? 8 : 7
      end
      host.define_singleton_method(:current_display_mode) do
        bad = fail_now.call(:display)
        bad ? "drifted" : Pins.fetch(:LIVE_DISPLAY_MODE)
      end
      host.define_singleton_method(:observe_candidate_session!) do |_prior, **_arguments|
        raise Failure, "session drift" if fail_now.call(:session)
        Object.new
      end
      host.define_singleton_method(:verify_routes!) do
        raise Failure, "route drift" if fail_now.call(:routes)
        true
      end
      host.define_singleton_method(:route_monitor_clean!) do |**_arguments|
        raise Failure, "sticky monitor drift" if fail_now.call(:monitor)
        true
      end
      host.define_singleton_method(:monotonic_now) { clock.first }
      host.define_singleton_method(:stability_sleep) { |seconds| clock[0] += seconds }
      [host, counters, clock]
    end

    def verify_stability_fixture!
      host, counters, clock = stability_harness
      host.send(:establish_candidate_stability_baseline!)
      host.send(:run_candidate_stability_window!)
      %i[launch lock process bytes readiness display session routes monitor].each do |probe|
        assert("stability samples baseline plus 31 #{probe}") { counters[probe] == 32 }
      end
      assert("stability reaches full monotonic window") { clock.first >= 31.0 }

      %i[launch lock process bytes readiness display session routes monitor].each do |probe|
        [2, 17, 32].each do |call|
          host, = stability_harness(fail_probe: probe, fail_call: call)
          host.send(:establish_candidate_stability_baseline!)
          expect_failure("#{probe} drift at sample #{call - 1}") do
            host.send(:run_candidate_stability_window!)
          end
        end
      end
    end

    def verify_elapsed_stability_fixture!
      host, counters, clock = stability_harness(sample_seconds: 5.0)
      host.send(:establish_candidate_stability_baseline!)
      started = clock.first
      host.send(:run_candidate_stability_window!)
      assert("slow probes retain the full 31-second monotonic window") { clock.first - started == 31.0 }
      %i[launch lock process bytes readiness display session routes monitor].each do |probe|
        assert("slow probes complete baseline plus six full #{probe} samples") { counters[probe] == 7 }
      end

      # These probes fail after the last readiness call advances time across the deadline.
      # Reaching the deadline must never bypass the rest of the full sample's safety checks.
      %i[readiness display session routes monitor].each do |probe|
        host, counters, clock = stability_harness(fail_probe: probe, fail_call: 7, sample_seconds: 5.0)
        host.send(:establish_candidate_stability_baseline!)
        started = clock.first
        expect_failure("#{probe} drift in the deadline-crossing sample") do
          host.send(:run_candidate_stability_window!)
        end
        assert("#{probe} drift was checked after the full elapsed window") do
          clock.first - started == 31.0 && counters[probe] == 7
        end
      end
    end

    def verify_second_signal_deferral!
      %i[rollback abort].each do |mode|
        entered = Queue.new
        release = Queue.new
        host_class = Class.new(FakeHost) do
          attr_reader :cleanup_completed
        end
        host = host_class.new
        if mode == :rollback
          host.define_singleton_method(:verify_candidate_ready!) { raise Interrupt, "first interrupt" }
          base_cleanup = host.method(:rollback_exact_v90!)
          host.define_singleton_method(:rollback_exact_v90!) do
            entered << true
            release.pop
            base_cleanup.call
            @cleanup_completed = true
          end
        else
          host.define_singleton_method(:revalidate_immediately_before_stop!) do |_capsule|
            raise Interrupt, "first interrupt"
          end
          base_cleanup = host.method(:abort_before_stop!)
          host.define_singleton_method(:abort_before_stop!) do
            entered << true
            release.pop
            base_cleanup.call
            @cleanup_completed = true
          end
        end
        worker_error = nil
        worker = Thread.new do
          Thread.current.report_on_exception = false
          begin
            Coordinator.new(host, FakeCapsule.new).execute!
          rescue Exception => error # rubocop:disable Lint/RescueException
            worker_error = error
          end
        end
        entered.pop
        worker.raise(Interrupt, "second interrupt")
        release << true
        worker.join(5)
        assert("second signal worker exits #{mode}") { !worker.alive? && worker_error }
        assert("second signal cannot truncate #{mode}") { host.cleanup_completed }
        assert("second signal leaves clean namespace #{mode}") do
          mode == :rollback ? host.rollback_clean? : host.abort_clean?
        end
        if mode == :rollback
          assert("second signal preserves rollback terminal") { host.states.last == "ROLLED_BACK_EXACT_V90" }
        end
      ensure
        worker.kill if worker&.alive?
      end
    end

    def verify_predecessor_runtime_snapshots!
      identities = (Pins.fetch(:PREDECESSOR_IDENTITY_PATHS) + [Pins.fetch(:LAUNCH_AGENT)]).each_with_index.to_h do |path, index|
        [path, [1, index + 10, path == Pins.fetch(:LIVE_APP) ? "directory" : "file"]]
      end
      first_values = {
        pid: 12_345, runs: 1, start: "Thu Sep 24 12:04:54 2026", nonce: "a" * 64,
        files: identities, lock_directory: [1, 30, "directory"], lock_file: [1, 31, "file"]
      }
      first = PredecessorRuntimeSnapshot.new(**first_values)
      first.assert_same!(PredecessorRuntimeSnapshot.new(**first_values))
      second_values = first_values.merge(pid: 12_346, runs: 2, start: "Thu Sep 24 12:08:01 2026", nonce: "b" * 64)
      second = PredecessorRuntimeSnapshot.new(**second_values)
      first.fresh_generation!(second.pid, second.nonce)
      expect_failure("same PID cannot certify a fresh generation") { first.fresh_generation!(first.pid, second.nonce) }
      expect_failure("same nonce cannot certify a fresh generation") { first.fresh_generation!(second.pid, first.nonce) }

      {
        pid: second.pid, runs: second.runs, start: second.start, nonce: second.nonce,
        lock_directory: [1, 32, "directory"], lock_file: [1, 33, "file"],
        files: identities.merge(Pins.fetch(:LIVE_APP) => [1, 34, "directory"])
      }.each do |field, changed|
        expect_failure("predecessor runtime drift: #{field}") do
          first.assert_same!(PredecessorRuntimeSnapshot.new(**first_values.merge(field => changed)))
        end
      end
      expect_failure("predecessor launch count must be positive") do
        PredecessorRuntimeSnapshot.new(**first_values.merge(runs: 0))
      end
      identities.fetch(Pins.fetch(:LIVE_APP))[1] = 99
      assert("snapshot copies mutable source identities") { first.files.fetch(Pins.fetch(:LIVE_APP))[1] == 10 }
      expect_exception("snapshot nested identity is immutable") { first.files.fetch(Pins.fetch(:LIVE_APP))[1] = 99 }

      fixture = lambda do |observations|
        host = RealHost.new
        host.define_singleton_method(:capture_predecessor_runtime_snapshot!) do
          observations.shift || raise(Failure, "fixture snapshot sequence exhausted")
        end
        host.define_singleton_method(:verify_installed_v90_bytes!) { true }
        host.define_singleton_method(:verify_dynamic_process!) do |pid, expected_start:, expected_cdhash:|
          raise Failure, "fixture process trust mismatch" unless
            pid.positive? && !expected_start.empty? && expected_cdhash == Pins.fetch(:V90_CDHASH)
          true
        end
        host.define_singleton_method(:verify_routes!) { true }
        host.define_singleton_method(:verify_pairing_metadata!) { true }
        host.define_singleton_method(:current_display_mode) { Pins.fetch(:LIVE_DISPLAY_MODE) }
        host.define_singleton_method(:observe_predecessor_session!) { |_runtime, prior| prior || :idle }
        host
      end
      host = fixture.call([first, first, second])
      host.send(:verify_live_v90!, nil)
      expect_failure("same invocation cannot adopt a changed generation") { host.send(:verify_live_v90!, :idle) }
      assert("failed revalidation retains the original generation") do
        host.instance_variable_get(:@predecessor_runtime).equal?(first)
      end
      retry_host = fixture.call([second, second])
      retry_host.send(:verify_live_v90!, nil)
      assert("new invocation accepts verified fresh generation after a natural launchd restart") do
        retry_host.instance_variable_get(:@predecessor_runtime).equal?(second) && second.runs == 2
      end
      raced_host = fixture.call([first, second])
      expect_failure("runtime drift during initial verification") { raced_host.send(:verify_live_v90!, nil) }
      assert("raced initial verification never installs a snapshot") do
        raced_host.instance_variable_get(:@predecessor_runtime).nil?
      end
      untrusted_host = fixture.call([first, first])
      untrusted_host.define_singleton_method(:verify_installed_v90_bytes!) { raise Failure, "untrusted predecessor bytes" }
      expect_failure("runtime snapshot does not bypass trusted predecessor bytes") do
        untrusted_host.send(:verify_live_v90!, nil)
      end
      assert("untrusted bytes never install a runtime snapshot") do
        untrusted_host.instance_variable_get(:@predecessor_runtime).nil?
      end

      Dir.mktmpdir("v91-runtime-snapshot-") do |root|
        retry_host.instance_variable_set(:@transaction, root)
        retry_host.send(:persist_predecessor_runtime_snapshot!)
        path = File.join(root, "predecessor-runtime-snapshot.json")
        assert("transaction persists exact runtime snapshot privately") do
          JSON.parse(File.binread(path)) == second.record && (File.stat(path).mode & 0o7777) == 0o600
        end
        File.open(path, "ab") { |file| file.write("drift") }
        expect_failure("persisted predecessor runtime drift") do
          retry_host.send(:verify_predecessor_runtime_snapshot_evidence!)
        end
      end
    end

    def verify_v91_predecessor_receipt!
      host = RealHost.new
      proof = [
        "result=success-pending-terminal", "terminal_required=COMMITTED_V90",
        "point_of_no_return=V90_COMMIT_IRREVERSIBLE", "target=v90",
        "selected=#{Pins.fetch(:LIVE_DISPLAY_MODE)}",
        "candidate_executable_sha256=#{Pins.fetch(:V90_EXECUTABLE_SHA256)}",
        "route_monitor=#{Pins.fetch(:ROUTE_MONITOR_RESULT)}"
      ].join("\n") + "\n"
      journal = "OPENSTEAMER_PAIRED_HOST_UPDATE_V90\n#{Pins.fetch(:V90_TERMINAL)}\n"
      assert("committed predecessor receipt is accepted") do
        host.send(:verify_predecessor_commit_proof!, journal, proof)
      end
      [
        [journal.sub("COMMITTED_V90", "COMMITTED_V90_UNVERIFIED"), proof],
        [journal + "2026-09-24T19:00:00Z STATE ROLLED_BACK_EXACT_V86\n", proof],
        [journal, proof.sub(Pins.fetch(:V90_EXECUTABLE_SHA256), "f" * 64)],
        [journal, proof.sub("notifications=0", "notifications=1")],
        [journal, proof + "terminal_required=COMMITTED_V90\n"],
        [journal, proof.sub("teardown=clean", "teardown=unknown")]
      ].each_with_index do |(changed_journal, changed_proof), index|
        expect_failure("predecessor receipt mutation #{index}") do
          host.send(:verify_predecessor_commit_proof!, changed_journal, changed_proof)
        end
      end
      host.define_singleton_method(:path_present?) { |_path| false }
      assert("new V91 namespace may start absent without legacy history") do
        host.send(:verify_rollback_history!) && host.send(:verify_update_root_children!, [])
      end
      expect_failure("retained V91 history may not disappear") do
        host.send(:verify_update_root_children!, ["retained-transaction"])
      end
    end

    def verify_fresh_namespace_abort_fixture!
      Dir.mktmpdir("v91-fresh-namespace-abort-") do |runtime|
        update_root = File.join(runtime, "updates")
        host = RealHost.new
        host.send(:create_owned_directory!, update_root, 0o700, "fixture fresh update root") do |identity|
          host.instance_variable_set(:@update_root_created, true)
          host.instance_variable_set(:@update_root_identity, identity)
        end
        history = RollbackHistory.new(root: update_root, application_parent: runtime, launch_parent: runtime)
        history.capture!
        host.instance_variable_set(:@rollback_history, history)
        host.instance_variable_set(:@rollback_history_verified, true)
        cleanup = host.method(:remove_new_update_root_if_owned!)
        host.define_singleton_method(:remove_new_update_root_if_owned!) { cleanup.call(path: update_root) }
        host.define_singleton_method(:verify_retry_namespace_clean!) do
          @rollback_history.unchanged! if @rollback_history_verified
          raise Failure, "newly owned root or baseline survived abort" if
            File.exist?(update_root) || @rollback_history || @rollback_history_verified
          true
        end
        sync = host.method(:strict_fsync_directory!)
        host.define_singleton_method(:strict_fsync_directory!) do |path, label|
          sync.call(path == Pins.fetch(:RUNTIME_ROOT) ? runtime : path, label)
        end
        assert("fresh namespace prepare boundary abort cleans owned root and empty baseline") do
          host.abort_before_stop! && !File.exist?(update_root) &&
            !host.instance_variable_get(:@update_root_created)
        end
        assert("fresh namespace abort remains idempotent") { host.abort_before_stop! }
      end

      Dir.mktmpdir("v91-retained-namespace-abort-") do |runtime|
        update_root = File.join(runtime, "updates")
        Dir.mkdir(update_root, 0o700)
        history = RollbackHistory.new(root: update_root, application_parent: runtime, launch_parent: runtime)
        history.capture!
        host = RealHost.new
        host.instance_variable_set(:@rollback_history, history)
        host.instance_variable_set(:@rollback_history_verified, true)
        host.instance_variable_set(:@update_root_identity, host.send(:file_identity, update_root))
        host.send(:remove_new_update_root_if_owned!, path: update_root)
        assert("unowned history root and its baseline are retained") do
          File.directory?(update_root) && host.instance_variable_get(:@rollback_history).equal?(history) &&
            host.instance_variable_get(:@rollback_history_verified)
        end
        moved = File.join(runtime, "retained-original")
        File.rename(update_root, moved)
        Dir.mkdir(update_root, 0o700)
        expect_failure("retained history drift is not masked by abort cleanup") { history.unchanged! }
      end
    end

    def verify_pairing_metadata_fixture!
      success = Struct.new(:success?).new(true)
      failure = Struct.new(:success?).new(false)
      arguments = []
      runner = lambda do |query|
        arguments << query
        ["class: genp\nattributes: record#{arguments.length}\n", "", success]
      end
      first = PairingMetadata.observe!(runner: runner)
      assert("pairing proof observes exactly the two product records without secrets") do
        arguments == PairingMetadata::ACCOUNTS.map do |account|
          ["find-generic-password", "-s", PairingMetadata::SERVICE, "-a", account]
        end && arguments.flatten.none? { |argument| %w[-w -g].include?(argument) }
      end
      assert("pairing evidence contains digests only") do
        first.fetch("count") == 2 && first.fetch("attributeDigests").all? { |value| value.match?(/\A[0-9a-f]{64}\z/) } &&
          PairingMetadata::ACCOUNTS.none? { |account| JSON.generate(first).include?(account) }
      end
      assert("identical pairing metadata remains acceptable") { PairingMetadata.assert_same!(first, first.dup) }
      expect_failure("pairing attribute drift rejects commit") do
        PairingMetadata.assert_same!(first, first.merge("attributeDigests" => ["f" * 64, "e" * 64]))
      end
      [["", "", success], ["metadata", "", failure], ["metadata", "error", success], ["x" * 16_385, "", success]].each do |response|
        expect_failure("unavailable or malformed pairing metadata") do
          PairingMetadata.observe!(runner: ->(_arguments) { response })
        end
      end
    end

    def run!
      verify_v91_predecessor_receipt!
      verify_fresh_namespace_abort_fixture!
      verify_pairing_metadata_fixture!
      verify_artifact_build_provenance_fixture!
      verify_reusable_rollback_history_fixture!
      verify_deployment_observer_fixture!
      assert("sealed framework identity preserves the public bundle path") do
        Pins.fetch(:LIVE_FRAMEWORK_IDENTITY_PATH) ==
          "/Applications/opensteamer Host.app/Contents/Frameworks/LiveKitWebRTC.framework/LiveKitWebRTC" &&
          Pins.fetch(:LIVE_FRAMEWORK_IDENTITY_PATH) != Pins.fetch(:LIVE_FRAMEWORK)
      end
      assert("V90 verification keeps the historical media helper immutable and separate") do
        Pins.fetch(:V90_HELPERS)["verify-media-v1-host-bundle.sh"] ==
          "e8a486a8e7360e5d3c8517e237e046fc21b3ccc2a3eb5e14ccd5d40135742e0c" &&
          !Pins.fetch(:V90_HELPERS).key?("verify-mac-host-bundle.sh") &&
          Pins.fetch(:V90_BUNDLE_VERIFIER_SHA256) ==
            "02a348a88d25b76ab95d45620d823339212bb53ee0f39bfb3a52f04240d3d745"
      end
      assert("dynamic codesign verification uses the supported PID contract") do
        Pins.fetch(:DYNAMIC_CODESIGN_VERIFY_ARGUMENTS) == ["--verify"]
      end
      assert("readiness observer preserves executable source and owner-only staged modes") do
        Pins.fetch(:READINESS_SOURCE_MODE) == 0o755 && Pins.fetch(:READINESS_STAGED_MODE) == 0o500
      end

      capsule = FakeCapsule.new
      host = FakeHost.new
      Coordinator.new(host, capsule).preflight!
      assert("preflight is mutation-free") { host.events.all? { |kind, _| kind == :observe } }

      capsule = FakeCapsule.new
      host = FakeHost.new
      Coordinator.new(host, capsule).execute!
      assert("required journal states") do
        host.states == %w[
          BEGUN INPUTS_VERIFIED STOP_INTENT INSTALL_HOLDS_VERIFIED V90_STOPPED V90_HELD
          V91_PUBLISHED V91_BOOTSTRAPPED READY_VERIFIED COMMIT_INTENT
          V91_COMMIT_IRREVERSIBLE COMMITTED_V91
        ]
      end
      assert("terminal journal is last") { host.events.last == [:mutate, :"journal:COMMITTED_V91"] }
      assert("transitive capsule replay") { capsule.verify_count == 2 }
      assert("committed namespace has only active pointer") { host.commit_clean? }
      assert("initial topology barrier precedes INPUTS_VERIFIED") do
        host.events.index([:observe, :initial_topology_barrier]) <
          host.events.index([:mutate, :"journal:INPUTS_VERIFIED"])
      end
      assert("final topology barrier immediately precedes STOP_INTENT") do
        host.events.index([:observe, :final_topology_barrier]) <
          host.events.index([:mutate, :"journal:STOP_INTENT"])
      end

      host = FakeHost.new(fail_at: :verify_candidate_ready)
      expect_failure("candidate failure") { Coordinator.new(host, FakeCapsule.new).execute! }
      assert("pre-commit rollback") { host.events.count([:mutate, :rollback_exact_v90]) == 1 }
      assert("no commit after candidate failure") { !host.states.include?("COMMIT_INTENT") }
      assert("candidate failure rollback is clean") { host.rollback_clean? }
      assert("rollback terminal is last") { host.states.last == "ROLLED_BACK_EXACT_V90" }
      assert("required rollback journal topology") do
        host.states.last(6) == %w[
          ROLLBACK_STARTED V91_STOPPED FAILED_V91_ARCHIVED V90_RESTORED V90_BOOTSTRAPPED
          ROLLED_BACK_EXACT_V90
        ]
      end

      %i[
        write_pending_result publish_active_pointer unlink_pending_pointer
        pre_irreversible_safety_replay
      ].each do |boundary|
        host = FakeHost.new(fail_at: boundary)
        expect_failure("pre-irreversible boundary #{boundary}") do
          Coordinator.new(host, FakeCapsule.new).execute!
        end
        assert("pre-irreversible rollback #{boundary}") do
          host.events.count([:mutate, :rollback_exact_v90]) == 1
        end
        assert("pre-irreversible cleanup #{boundary}") { host.rollback_clean? }
        assert("pre-irreversible rollback terminal #{boundary}") do
          host.states.last == "ROLLED_BACK_EXACT_V90"
        end
      end

      host = FakeHost.new(fail_at: :"journal:V91_COMMIT_IRREVERSIBLE")
      expect_failure("pre-persist irreversible journal failure") do
        Coordinator.new(host, FakeCapsule.new).execute!
      end
      assert("pre-persist irreversible failure rolls back") do
        host.events.count([:mutate, :rollback_exact_v90]) == 1 && host.rollback_clean?
      end

      post_irreversible = %i[
        journal_irreversible_after_persist stop_route_monitor final_route_readback
        write_final_result remove_transaction_lock journal:COMMITTED_V91
      ]
      post_irreversible.each do |boundary|
        host = FakeHost.new(fail_at: boundary)
        expect_failure("post-irreversible boundary #{boundary}") do
          Coordinator.new(host, FakeCapsule.new).execute!
        end
        assert("post-irreversible boundary never rolls back #{boundary}") do
          host.events.none? { |event| event == [:mutate, :rollback_exact_v90] }
        end
        assert("post-irreversible boundary retains V91 #{boundary}") { host.committed_unverified? }
        assert("post-irreversible evidence is explicit #{boundary}") do
          host.states.include?("V91_COMMIT_IRREVERSIBLE") &&
            host.states.last == "COMMITTED_V91_UNVERIFIED" &&
            !host.states.include?("COMMITTED_V91")
        end
      end

      host = FakeHost.new(namespace_fresh: false)
      expect_failure("nonfresh namespace") { Coordinator.new(host, FakeCapsule.new).execute! }
      assert("nonfresh namespace fails before mutation") { host.events.all? { |kind, _| kind == :observe } }

      %i[
        prepare initial_durability_barrier initial_topology_barrier
        revalidate final_durability_barrier final_topology_barrier journal:STOP_INTENT
      ].each do |boundary|
        host = FakeHost.new(fail_at: boundary)
        expect_failure("pre-stop boundary #{boundary}") do
          Coordinator.new(host, FakeCapsule.new).execute!
        end
        assert("pre-stop boundary aborts once #{boundary}") do
          host.events.count([:mutate, :abort_before_stop]) == 1
        end
        assert("pre-stop boundary leaves no namespace residue #{boundary}") { host.abort_clean? }
        if %i[initial_durability_barrier initial_topology_barrier].include?(boundary)
          assert("initial fsync failure precedes INPUTS_VERIFIED") do
            !host.states.include?("INPUTS_VERIFIED")
          end
        elsif %i[final_durability_barrier final_topology_barrier].include?(boundary)
          assert("final fsync failure precedes STOP_INTENT") { !host.states.include?("STOP_INTENT") }
        end
      end

      %i[journal:INSTALL_HOLDS_VERIFIED stop_predecessor].each do |boundary|
        host = FakeHost.new(fail_at: boundary)
        expect_failure("post-intent boundary #{boundary}") do
          Coordinator.new(host, FakeCapsule.new).execute!
        end
        assert("post-intent boundary rolls back once #{boundary}") do
          host.events.count([:mutate, :rollback_exact_v90]) == 1
        end
        assert("post-intent boundary restores exact V90 #{boundary}") { host.rollback_clean? }
      end

      host = FakeHost.new(fail_at: :journal_stop_after_persist)
      expect_failure("visible STOP_INTENT fsync failure") do
        Coordinator.new(host, FakeCapsule.new).execute!
      end
      assert("visible STOP_INTENT failure uses rollback, never pre-stop abort") do
        host.events.count([:mutate, :rollback_exact_v90]) == 1 &&
          host.events.none? { |event| event == [:mutate, :abort_before_stop] } &&
          host.states.last == "ROLLED_BACK_EXACT_V90"
      end

      host = FakeHost.new
      expect_failure("last-moment capsule mutation") { Coordinator.new(host, FakeCapsule.new(fail_verify_at: 2)).execute! }
      assert("capsule mutation rejected before stop") { !host.states.include?("STOP_INTENT") }
      assert("pre-stop abort cleans prepared transaction") { host.events.include?([:mutate, :abort_before_stop]) }
      assert("pre-stop abort leaves no namespace residue") { host.abort_clean? }

      %i[
        rename_v90_app_to_hold rename_v90_plist_to_hold
        rename_v91_app_to_live rename_v91_plist_to_live
      ].each do |boundary|
        host = FakeHost.new(fail_at: boundary)
        expect_failure("rename boundary #{boundary}") { Coordinator.new(host, FakeCapsule.new).execute! }
        assert("single rollback at #{boundary}") { host.events.count([:mutate, :rollback_exact_v90]) == 1 }
        assert("no commit at #{boundary}") { !host.states.include?("COMMIT_INTENT") }
        assert("rename-boundary cleanup #{boundary}") { host.rollback_clean? }
      end

      duplicate = Tempfile.new("v91-duplicate-json")
      begin
        duplicate.write('{"schema":"x","schema":"x"}')
        duplicate.flush
        expect_failure("duplicate JSON key") { Util.strict_json(duplicate.path, ["schema"], "x") }
      ensure
        duplicate.close!
      end

      verify_v90_bundle_contract_fixture!
      verify_copy_stable_manifest_fixture!
      verify_published_candidate_root_xattrs_fixture!
      verify_predecessor_signature_layout_fixture!
      verify_predecessor_codesign_metadata_fixture!
      verify_dynamic_codesign_metadata_fixture!
      verify_predecessor_runtime_snapshots!
      verify_real_journal_state_machine!
      verify_journal_fault_reconciliation!
      verify_atomic_pointer_fixture!
      verify_real_inode_recovery_fixture!
      verify_recursive_fsync_fixture!
      verify_full_durability_barrier_fixture!
      verify_staged_install_layout_fixture!
      verify_cross_parent_rename_fsync_fixture!
      verify_transaction_topology_fixture!
      verify_write_durable_mode_fixture!
      verify_creation_signal_gap_fixture!
      verify_session_fence_fixture!
      verify_stability_fixture!
      verify_elapsed_stability_fixture!
      verify_second_signal_deferral!
      # This is read-only: it exercises the exact pinned compiler/SDK/source metadata path without
      # compiling or starting the CoreAudio observer.
      RealHost.new.send(:verify_route_monitor_tools!)

      puts "opensteamer V91 cutover self-test: PASS"
      true
    end
  end

  module CLI
    extend self

    SELF_TEST = "--self-test-v91-cutover"
    PREFLIGHT = "--verify-v91-cutover-preflight"
    EXECUTE = "--execute-authorized-v91-cutover"

    def run(argv)
      mode = argv.shift
      if mode == "--print-successor-tooling-contract"
        Util.fail!("profile inspection requires path and external digest") unless argv.length == 2
        require_relative "opensteamer-host-successor-contract"
        contract = OpenSteamerHostSuccessor::ReleaseContract.new(argv[0], argv[1])
        puts contract.profile.fetch("source").values_at("branch", "upstream")
        return 0
      end
      if %w[--verify-successor-cutover-preflight --execute-authorized-successor-cutover].include?(mode)
        Util.fail!("successor mode requires profile/digest and capsule/two digests") unless argv.length == 5
        require_relative "opensteamer-host-successor-contract"
        contract = OpenSteamerHostSuccessor::ReleaseContract.new(argv.shift, argv.shift)
        Pins.bind_contract!(contract)
        mode = mode == "--verify-successor-cutover-preflight" ? PREFLIGHT : EXECUTE
      end
      case mode
      when SELF_TEST
        Util.fail!("self-test accepts no arguments") unless argv.empty?
        SelfTest.run!
      when PREFLIGHT, EXECUTE
        Util.fail!("mode requires capsule root and exactly two external digests") unless argv.length == 3
        Util.fail!("live V91 modes require the independently pinned launcher") unless
          ENV["OPENSTEAMER_V91_LAUNCHER_ATTESTATION"] == Pins.fetch(:LAUNCHER_ATTESTATION)
        Util.fail!("live V91 modes require the pinned uid/euid 501 account") unless Process.uid == 501 && Process.euid == 501
        tooling = ToolingProof.verify!
        ToolingProof.verify_launcher_environment!(tooling)
        capsule = Capsule.new(argv[0], argv[1], argv[2], tooling: tooling)
        coordinator = Coordinator.new(RealHost.new, capsule)
        if mode == PREFLIGHT
          coordinator.preflight!
          puts(Pins.contract ? "successor_cutover_preflight=pass" : "v91_cutover_preflight=pass")
        else
          previous = {}
          %w[HUP INT TERM].each do |signal|
            previous[signal] = Signal.trap(signal) { raise Interrupt, "received #{signal}" }
          end
          begin
            coordinator.execute!
            puts(Pins.contract ? "successor_cutover=committed" : "v91_cutover=committed")
          ensure
            previous.each { |signal, handler| Signal.trap(signal, handler) }
          end
        end
      else
        Util.fail!("usage: controller #{SELF_TEST} | #{PREFLIGHT} <capsule> <handoff-sha256> <payload-sha256> | #{EXECUTE} <capsule> <handoff-sha256> <payload-sha256>")
      end
      0
    rescue Failure => error
      warn "opensteamer-host-v91-cutover-controller: #{error.message}"
      1
    end
  end
end

exit(OpenSteamerV91Cutover::CLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
