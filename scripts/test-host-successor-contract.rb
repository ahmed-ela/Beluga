#!/usr/bin/ruby
# frozen_string_literal: true
require "minitest/autorun"
require_relative "../macOS/scripts/import-prebuilt-host-successor"

class HostSuccessorContractTest < Minitest::Test
  Engine = OpenSteamerV91Cutover
  Successor = OpenSteamerHostSuccessor

  def setup
    @root = File.realpath(Dir.mktmpdir("successor-contract-", File.expand_path("..", __dir__)))
    @baseline = {
      "schema" => Successor::ReleaseContract::BASELINE_SCHEMA,
      "mode" => Successor::ReleaseContract::MODE, "sourceBuildProvenance" => "unestablished",
      "executableSHA256" => "1" * 64, "frameworkSHA256" => "2" * 64,
      "infoPlistSHA256" => "3" * 64, "executableCDHash" => "4" * 40,
      "designatedRequirement" => Engine::Pins::APPROVED_PREDECESSOR_REFERENCE_DESIGNATED_REQUIREMENT,
      "launchPlistSHA256" => Engine::Pins::LAUNCH_AGENT_SHA256,
      "copyManifest" => descriptor("baseline-manifest", "synthetic baseline manifest"),
      "bundleVerifier" => { "path" => Engine::Pins::TOOLING_ROOT + "/macOS/scripts/verify-beluga-host-bundle.sh", "sha256" => "5" * 64 },
      "observerDirectory" => Engine::Pins::OBSERVER_EVIDENCE
    }
    @profile = {
      "schema" => Successor::ReleaseContract::PROFILE_SCHEMA,
      "namespace" => "host-fixture-001",
      "source" => { "commit" => "a" * 40, "tree" => "b" * 40,
                    "branch" => "fixture/source", "upstream" => "origin/fixture/source" },
      "candidate" => {
        "appPath" => @root + "/Beluga Host.app", "executableSHA256" => "6" * 64,
        "frameworkSHA256" => "7" * 64, "infoPlistSHA256" => "8" * 64,
        "executableCDHash" => "9" * 40, "frameworkCDHash" => "a" * 40,
        "copyManifest" => descriptor("candidate-manifest", "synthetic candidate manifest"),
        "buildEvidence" => descriptor("build-evidence", "synthetic reviewed build evidence")
      },
      "reference" => { "path" => @root + "/reference", "sha256" => Engine::Pins::APPROVED_PREDECESSOR_REFERENCE_SHA256 },
      "launchSnapshot" => { "path" => @root + "/launch.plist", "sha256" => Engine::Pins::LAUNCH_AGENT_SHA256 }
    }
  end

  def teardown
    FileUtils.remove_entry_secure(@root)
  end

  def descriptor(name, bytes)
    path = File.join(@root, name)
    File.write(path, bytes)
    File.chmod(0o600, path)
    { "path" => path, "sha256" => Digest::SHA256.hexdigest(bytes) }
  end

  def contract
    @profile["baseline"] = descriptor("baseline.json", JSON.generate(@baseline))
    @attestation ||= {
      "schema" => Successor::ReleaseContract::BUILD_SCHEMA,
      "review" => "independently-reviewed-source-build",
      "sourceCommit" => @profile["source"]["commit"], "sourceTree" => @profile["source"]["tree"],
      "copyManifestSHA256" => @profile["candidate"]["copyManifest"]["sha256"],
      "buildLog" => descriptor("reviewed-build.log", "synthetic fixture build log")
    }.merge(@profile["candidate"].select { |key, _| %w[executableSHA256 frameworkSHA256 infoPlistSHA256 executableCDHash frameworkCDHash].include?(key) })
    @profile["candidate"]["buildEvidence"] = descriptor("reviewed-build.json", JSON.generate(@attestation)) if @profile["candidate"]["buildEvidence"]
    @profile_descriptor = descriptor("profile.json", JSON.generate(@profile))
    Successor::ReleaseContract.new(@profile_descriptor["path"], @profile_descriptor["sha256"])
  end

  def rejects(pattern, &block)
    assert_match(pattern, assert_raises(Engine::Failure, &block).message)
  end

  def in_child(body)
    value = contract
    entry = File.expand_path("../macOS/scripts/import-prebuilt-host-successor.rb", __dir__)
    code = <<~RUBY
      require #{entry.inspect}
      E = OpenSteamerV91Cutover
      S = OpenSteamerHostSuccessor
      c = S::ReleaseContract.new(#{value.profile_path.inspect}, #{value.profile_sha.inspect})
      #{body}
    RUBY
    output, result = Open3.capture2e("/usr/bin/ruby", "-e", code)
    assert result.success?, output
    JSON.parse(output)
  end

  def test_contract_contains_only_release_specific_pins
    value = contract
    assert_equal Engine::Pins::RELEASE_KEYS.sort, value.pins.keys.sort
    refute value.pins.key?(:LIVE_APP)
    refute value.pins.key?(:LAUNCH_ARGUMENTS)
    refute value.pins.key?(:ROUTES)
    refute value.pins.key?(:TEAM_ID)
    assert value.frozen?
    assert value.pins.frozen?
    assert value.baseline.frozen?
  end

  def test_namespaces_and_headers_bind_exact_profile
    value = contract
    assert_includes value.pins.fetch(:V91_UPDATE_ROOT), "paired-host-updates-host-fixture-001"
    assert_includes value.pins.fetch(:V91_JOURNAL_HEADER), value.profile_sha
    refute_equal Engine::Pins::V91_ACTIVE_POINTER, value.pins.fetch(:V91_ACTIVE_POINTER)
  end

  def test_observed_baseline_cannot_claim_historical_source_build_proof
    @baseline["sourceBuildProvenance"] = "220f24"
    rejects(/independently reviewed/) { contract }
  end

  def test_observed_baseline_cannot_be_renamed_committed_receipt
    @baseline["mode"] = "COMMITTED_V91"
    rejects(/independently reviewed/) { contract }
  end

  def test_unknown_baseline_fields_rejected
    @baseline["terminal"] = "COMMITTED_V91"
    rejects(/fields differ/) { contract }
  end

  def test_launch_identity_cannot_be_changed
    @baseline["launchPlistSHA256"] = "0" * 64
    rejects(/launch contract/) { contract }
  end

  def test_signing_requirement_cannot_be_changed
    @baseline["designatedRequirement"] = "anchor trusted"
    rejects(/signing requirement/) { contract }
  end

  def test_arbitrary_verifier_is_not_accepted
    @baseline["bundleVerifier"]["path"] = @root + "/evil-verifier.sh"
    rejects(/reviewed tracked Beluga verifier/) { contract }
  end

  def test_observer_helpers_cannot_be_substituted
    @baseline["observerDirectory"] = @root
    rejects(/trusted observer/) { contract }
  end

  def test_reference_cannot_be_changed
    @profile["reference"]["sha256"] = "0" * 64
    rejects(/compatibility reference/) { contract }
  end

  def test_installed_candidate_cannot_be_imported
    @profile["candidate"]["appPath"] = "/Applications/Beluga Host.app"
    rejects(/approved artifact root/) { contract }
  end

  def test_candidate_and_predecessor_cannot_be_identical
    @profile["candidate"]["executableSHA256"] = @baseline["executableSHA256"]
    rejects(/equals predecessor/) { contract }
  end

  def test_missing_candidate_evidence_rejected
    @profile["candidate"]["buildEvidence"] = nil
    rejects(/buildEvidence is missing/) { contract }
  end

  def test_missing_baseline_cannot_be_filled_by_unknown_receipt
    value = contract
    @profile["baseline"] = nil
    file = descriptor("incomplete.json", JSON.generate(@profile))
    rejects(/baseline is missing/) { Successor::ReleaseContract.new(file["path"], file["sha256"]) }
    assert value.baseline.fetch("sourceBuildProvenance") == "unestablished"
  end

  def test_baseline_evidence_change_rejected_before_any_live_probe
    value = contract
    File.write(@profile["baseline"]["path"], "changed")
    rejects(/digest mismatch/) { value.verify_baseline_evidence! }
  end

  def test_one_time_binding_preserves_invariant_pins
    result = in_child(<<~'RUBY')
      E::Pins.bind_contract!(c)
      again = begin; E::Pins.bind_contract!(c); false; rescue E::Failure; true; end
      puts JSON.generate({ again: again, app: E::Pins.fetch(:LIVE_APP), routes: E::Pins.fetch(:ROUTES),
                           predecessor: E::Pins.fetch(:V90_EXECUTABLE_SHA256), name: E::Pins.release_name })
    RUBY
    assert result["again"]
    assert_equal Engine::Pins::LIVE_APP, result["app"]
    assert_equal Engine::Pins::ROUTES, result["routes"]
    assert_equal @baseline["executableSHA256"], result["predecessor"]
    assert_equal @profile["namespace"], result["name"]
  end

  def test_late_binding_forbidden
    result = in_child(<<~'RUBY')
      E::Pins.fetch(:V90_EXECUTABLE_SHA256)
      failed = begin; E::Pins.bind_contract!(c); false; rescue E::Failure; true; end
      puts JSON.generate(failed)
    RUBY
    assert result
  end

  def test_successor_state_mapping_roundtrip_and_legacy_replay_rejection
    value = contract
    Engine::RealHost::JOURNAL_TRANSITIONS.values.flatten.uniq.each do |state|
      assert_equal state, value.state_in(value.state_out(state))
    end
    rejects(/legacy generation/) { value.state_in("COMMITTED_V91") }
    rejects(/legacy generation/) { value.state_in("ROLLED_BACK_EXACT_V90") }
  end

  def test_proof_record_mapping_does_not_rewrite_unrelated_evidence
    value = contract
    text = "result=pending-terminal\nterminal_required=V91_COMMIT_IRREVERSIBLE,COMMITTED_V91\ntarget=v91\noriginal_error=V91 fake COMMITTED_V91\n"
    external = value.record_out(text)
    assert_includes external, "target=candidate\n"
    assert_includes external, "original_error=V91 fake COMMITTED_V91\n"
    assert_equal text, value.record_in(external)
    rejects(/legacy target/) { value.record_in("target=exact-v90\n") }
  end

  def test_real_journal_roundtrip_preserves_graph_and_irreversibility
    result = in_child(<<~RUBY)
      E::Pins.bind_contract!(c)
      path = #{File.join(@root, "journal.log").inspect}
      File.write(path, E::Pins.fetch(:V91_JOURNAL_HEADER) + "\n")
      File.chmod(0600, path)
      h = E::RealHost.new
      h.instance_variable_set(:@journal, path)
      E::RealHost::SUCCESS_STATES.each { |state| h.journal!(state) }
      bytes = File.read(path)
      states = h.send(:parse_journal_bytes!, bytes)
      replay = begin; h.send(:parse_journal_bytes!, bytes.sub("COMMITTED_CANDIDATE", "COMMITTED_V91")); false; rescue E::Failure; true; end
      puts JSON.generate({ bytes: bytes, states: states, irreversible: h.irreversible_on_disk?, replay: replay })
    RUBY
    assert_equal Engine::RealHost::SUCCESS_STATES, result["states"]
    assert_includes result["bytes"], "STATE COMMITTED_CANDIDATE\n"
    refute_includes result["bytes"], "STATE COMMITTED_V91\n"
    assert result["irreversible"]
    assert result["replay"]
  end

  def test_original_coordinator_order_and_failures_with_bound_successor
    result = in_child(<<~'RUBY')
      E::Pins.bind_contract!(c)
      results = {}
      [nil, :verify_candidate_ready, :journal_irreversible_after_persist, :stop_route_monitor, :final_route_readback].each do |fault|
        host = E::FakeHost.new(fail_at: fault)
        error = begin; E::Coordinator.new(host, E::FakeCapsule.new).execute!; nil; rescue E::Failure => e; e.class.name; end
        results[fault || :success] = { states: host.states.map { |state| E::Pins.state_out(state) },
                                     rollback: host.events.count([:mutate, :rollback_exact_v90]), error: error }
      end
      puts JSON.generate(results)
    RUBY
    assert_equal "COMMITTED_CANDIDATE", result["success"]["states"].last
    assert_equal 1, result["verify_candidate_ready"]["rollback"]
    assert_equal "ROLLED_BACK_EXACT_PREDECESSOR", result["verify_candidate_ready"]["states"].last
    %w[journal_irreversible_after_persist stop_route_monitor final_route_readback].each do |fault|
      assert_equal 0, result[fault]["rollback"]
      assert_equal "COMMITTED_CANDIDATE_UNVERIFIED", result[fault]["states"].last
    end
  end

  def test_successor_staging_paths_and_history_do_not_match_consumed_v91_namespace
    result = in_child(<<~'RUBY')
      E::Pins.bind_contract!(c)
      token = "12345678-1234-4234-8234-123456789abc"
      root = "/Applications/.opensteamer-paired-#{E::Pins.release_name}-install-#{token}"
      h = E::RealHost.new
      h.instance_variable_set(:@token, token)
      h.instance_variable_set(:@staged_root, root)
      h.instance_variable_set(:@staged_app, File.join(root, "Beluga Host.app"))
      accepted = h.send(:verify_staged_install_layout!)
      h.instance_variable_set(:@staged_root, root.sub(E::Pins.release_name, "v91"))
      refused = begin; h.send(:verify_staged_install_layout!); false; rescue E::Failure; true; end
      history = E::RollbackHistory.new(root: E::Pins.fetch(:V91_UPDATE_ROOT), application_parent: "/Applications",
                                      launch_parent: File.dirname(E::Pins::LAUNCH_AGENT))
      puts JSON.generate({ accepted: accepted, refused: refused, paths: history.paths(token) })
    RUBY
    assert result["accepted"]
    assert result["refused"]
    assert result["paths"].all? { |path| path.include?(@profile["namespace"]) && !path.include?("v91") }
  end

  def test_importer_refuses_existing_or_installed_destination_before_operations
    importer = Successor::PrebuiltCapsuleImporter.new(contract)
    rejects(/already consumed/) { importer.import!(@root) }
    rejects(/installed\/runtime/) { importer.import!("/Applications/new-capsule") }
  end

  def test_payload_metadata_and_sidecar_roundtrip_without_build_or_launch
    result = in_child(<<~RUBY)
      E::Pins.bind_contract!(c)
      root = #{File.join(@root, "synthetic-capsule").inspect}
      FileUtils.mkdir_p(File.join(root, "v91-screen-oracle-handoff"))
      %w[v91-source-export-tree-manifest.txt v91-candidate-app-tree-manifest.txt v91-candidate-app-copy-manifest.txt].each do |name|
        File.write(File.join(root, name), "synthetic manifest")
      end
      importer = S::PrebuiltCapsuleImporter.new(c)
      importer.instance_variable_set(:@root, root)
      importer.instance_variable_set(:@tooling, { commit: "b" * 40, tree: "c" * 40,
        blobs: { "macOS/scripts/import-prebuilt-host-successor.rb" => "d" * 40 } })
      payload = importer.send(:make_payload, root)
      importer.send(:write_metadata!, payload)
      handoff = File.join(root, payload.fetch("handoffRelativePath"))
      E::Util.sidecar!(handoff, handoff + ".sha256", payload.fetch("handoffSHA256"), "fixture handoff")
      puts JSON.generate({ keys: payload.keys.sort, schema: payload["schema"], app: payload["candidateAppRelativePath"],
                           profile: payload["successorProfileSHA256"], manifest: JSON.parse(File.read(handoff)) })
    RUBY
    assert_equal (Engine::Pins::PAYLOAD_KEYS + %w[successorProfileSHA256 artifactBuildEvidenceSHA256 artifactBuildLogSHA256]).sort, result["keys"]
    assert_equal "opensteamer.prebuilt-host-successor-payload.v1", result["schema"]
    assert_equal "candidate/Beluga Host.app", result["app"]
    assert_equal @profile["candidate"]["executableSHA256"], result["manifest"]["candidateExecutableSHA256"]
  end

  def test_artifact_roots_and_case_or_firmlink_aliases_rejected_before_reads
    importer = Successor::PrebuiltCapsuleImporter.new(contract)
    ["/Applications", "/applications", "/applications/new-capsule", "/System/Volumes/Data/Applications/new-capsule",
     Engine::Pins::RUNTIME_ROOT, Engine::Pins::RUNTIME_ROOT.downcase + "/new-capsule", "/Volumes/t7"].each do |path|
      rejects(/approved artifact root/) { importer.import!(path) }
      rejects(/approved artifact root/) { Successor::Checks.artifact_path!(path, "input") }
    end
    alias_path = File.join(@root, "alias")
    File.symlink("/Applications", alias_path)
    rejects(/alias/) { importer.import!(alias_path + "/new-capsule") }
    refute File.exist?(File.join(alias_path, "new-capsule"))
  end

  def test_artifact_ancestor_inode_alias_rejected_before_content_reads
    real_lstat = File.method(:lstat)
    protected = File.stat("/Applications")
    fake = Struct.new(:dev, :ino) { def symlink?; false; end }.new(protected.dev, protected.ino)
    File.stub(:lstat, ->(path) { path == @root ? fake : real_lstat.call(path) }) do
      rejects(/aliases an installed/) { Successor::Checks.artifact_path!(@root + "/future", "destination") }
    end
  end

  def test_profile_and_descriptors_cannot_point_to_installed_aliases
    rejects(/approved artifact root/) { Successor::ReleaseContract.new("/applications/unread-profile", "0" * 64) }
    @profile["candidate"]["copyManifest"]["path"] = "/System/Volumes/Data/Applications/unread-manifest"
    rejects(/approved artifact root/) { contract }
  end

  def test_reviewed_build_attestation_rejects_every_source_and_artifact_mismatch
    contract
    %w[sourceCommit sourceTree executableSHA256 frameworkSHA256 infoPlistSHA256 executableCDHash frameworkCDHash copyManifestSHA256].each do |key|
      original = @attestation[key]
      @attestation[key] = "0" * original.length
      rejects(/build attestation differs/) { contract }
      @attestation[key] = original
    end
    @attestation["review"] = "imported-opaque-log"
    rejects(/independent source-build review/) { contract }
  end

  def test_build_log_and_attestation_bytes_remain_bound
    value = contract
    File.write(@attestation["buildLog"]["path"], "changed log")
    rejects(/digest mismatch/) { value.verify_candidate_evidence! }
    File.write(@profile["candidate"]["buildEvidence"]["path"], "opaque log")
    rejects(/digest mismatch/) { value.verify_candidate_evidence! }
  end

  def test_payload_cannot_substitute_other_valid_signed_candidate_or_review
    value = contract
    candidate = @profile.fetch("candidate")
    payload = { "successorProfileSHA256" => value.profile_sha,
                "artifactBuildEvidenceSHA256" => candidate["buildEvidence"]["sha256"],
                "artifactBuildLogSHA256" => @attestation["buildLog"]["sha256"],
                "candidateExecutableSHA256" => candidate["executableSHA256"],
                "candidateMediaFrameworkExecutableSHA256" => candidate["frameworkSHA256"],
                "candidateInfoPlistSHA256" => candidate["infoPlistSHA256"],
                "candidateAppCopyManifestSHA256" => candidate["copyManifest"]["sha256"] }
    identity = { "executableCDHash" => candidate["executableCDHash"], "mediaFrameworkExecutableCDHash" => candidate["frameworkCDHash"] }
    assert value.validate_payload_binding!(payload, identity: identity)
    payload.each do |key, original|
      rejects(/differs from approved/) { value.validate_payload_binding!(payload.merge(key => "0" * 64)) }
    end
    identity.each_key do |key|
      rejects(/code identity differs/) { value.validate_payload_binding!(payload, identity: identity.merge(key => "0" * 40)) }
    end
  end

  def test_successor_rollback_history_requires_exact_terminal_and_clean_monitor
    result = in_child(<<~RUBY)
      E::Pins.bind_contract!(c)
      transaction = #{File.join(@root, "rollback-proof").inspect}
      Dir.mkdir(transaction, 0700)
      states = %w[BEGUN INPUTS_VERIFIED STOP_INTENT INSTALL_HOLDS_VERIFIED V90_STOPPED V90_HELD V91_PUBLISHED V91_BOOTSTRAPPED ROLLBACK_STARTED V91_STOPPED FAILED_V91_ARCHIVED V90_RESTORED V90_BOOTSTRAPPED ROLLED_BACK_EXACT_V90]
      records = {
        "journal.log" => E::Pins.fetch(:V91_JOURNAL_HEADER) + "\n" + states.map { |s| "2026-09-30T00:00:00Z STATE " + E::Pins.state_out(s) + "\n" }.join,
        "rollback-result.txt" => E::Pins.record_out("result=pending-terminal\nterminal_required=ROLLED_BACK_EXACT_V90\npid=1\nnonce=" + "a" * 64 + "\ntarget=exact-v90\nselected=" + E::Pins.fetch(:LIVE_DISPLAY_MODE) + "\n"),
        "sticky-coreaudio-route-monitor.stdout" => E::Pins.fetch(:ROUTE_MONITOR_READY) + "\n" + E::Pins.fetch(:ROUTE_MONITOR_RESULT) + "\n",
        "sticky-coreaudio-route-events.log" => "", "sticky-coreaudio-route-monitor.stderr" => ""
      }
      records.each { |name, bytes| File.write(File.join(transaction, name), bytes); File.chmod(0600, File.join(transaction, name)) }
      history = E::RollbackHistory.new(root: File.dirname(transaction), application_parent: #{ @root.inspect }, launch_parent: #{ @root.inspect })
      history.send(:verify_terminal_proof!, transaction)
      failures = []
      mutations = [
        ["journal.log", records["journal.log"].sub(E::Pins.fetch(:V91_JOURNAL_HEADER), "OPENSTEAMER_PAIRED_HOST_UPDATE_V91")],
        ["journal.log", records["journal.log"].sub("ROLLED_BACK_EXACT_PREDECESSOR", "ROLLED_BACK_EXACT_V90")],
        ["rollback-result.txt", records["rollback-result.txt"].sub("exact-predecessor", "exact-v90")],
        ["sticky-coreaudio-route-events.log", "route changed\n"],
        ["sticky-coreaudio-route-monitor.stdout", E::Pins.fetch(:ROUTE_MONITOR_READY) + "\n"]
      ]
      mutations.each do |name, bytes|
        File.write(File.join(transaction, name), bytes)
        failures << (begin; history.send(:verify_terminal_proof!, transaction); false; rescue E::Failure; true; end)
        File.write(File.join(transaction, name), records.fetch(name))
      end
      puts JSON.generate(failures)
    RUBY
    assert_equal [true] * 5, result
  end
end
