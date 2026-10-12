#!/usr/bin/ruby
# frozen_string_literal: true
require "minitest/autorun"
require_relative "../macOS/scripts/opensteamer-host-successor-inputs"

class HostSuccessorInputsTest < Minitest::Test
  Inputs = OpenSteamerHostSuccessorInputs

  def setup
    @root = File.realpath(Dir.mktmpdir("successor-input-fixture-", File.expand_path("..", __dir__)))
    @profile_path = File.join(@root, "profile.json")
    @data = {
      "schema" => Inputs::Profile::SCHEMA, "namespace" => "host-fixture",
      "source" => { "commit" => "a" * 40, "tree" => "b" * 40,
                    "branch" => "fixture/source", "upstream" => "origin/fixture/source" },
      "candidate" => { "appPath" => File.join(@root, "Beluga Host.app"),
                       "executableSHA256" => "c" * 64, "copyManifest" => nil, "buildEvidence" => nil },
      "predecessor" => { "executableSHA256" => "d" * 64, "receipt" => nil, "copyManifest" => nil },
      "bundleVerifier" => nil, "reference" => nil
    }
  end

  def teardown
    FileUtils.remove_entry_secure(@root)
  end

  def profile
    bytes = JSON.generate(@data)
    File.write(@profile_path, bytes)
    Inputs::Profile.new(@profile_path, expected_sha256: Digest::SHA256.hexdigest(bytes))
  end

  def descriptor(name, contents)
    path = File.join(@root, name)
    File.write(path, contents)
    { "path" => path, "sha256" => Digest::SHA256.hexdigest(contents) }
  end

  def rejects(message, &block)
    assert_match(message, assert_raises(Inputs::Failure, &block).message)
  end

  def test_draft_explicitly_reports_missing_evidence_without_reading_current_host
    value = profile
    assert_equal %w[candidate.copyManifest candidate.buildEvidence predecessor.receipt predecessor.copyManifest bundleVerifier reference], value.missing_evidence
    rejects(/predecessor.receipt/) { value.require_deployment_binding! }
  end

  def test_approved_profile_is_deeply_immutable
    value = profile
    assert_raises(FrozenError) { value.data["candidate"]["appPath"].replace("/Applications/Beluga Host.app") }
    assert_raises(FrozenError) { value.data["predecessor"]["unrecognized"] = {} }
  end

  def test_wrong_profile_digest
    File.write(@profile_path, JSON.generate(@data))
    rejects(/approval digest differs/) { Inputs::Profile.new(@profile_path, expected_sha256: "0" * 64) }
  end

  def test_duplicate_nested_fields
    bytes = JSON.generate(@data).sub('"receipt":null', '"receipt":null,"receipt":null')
    File.write(@profile_path, bytes)
    rejects(/duplicate key/) { Inputs::Profile.new(@profile_path, expected_sha256: Digest::SHA256.hexdigest(bytes)) }
  end

  def test_oversize_profile
    bytes = " " * 65_537
    File.write(@profile_path, bytes)
    rejects(/exceeds/) { Inputs::Profile.new(@profile_path, expected_sha256: Digest::SHA256.hexdigest(bytes)) }
  end

  def test_unknown_profile_fields
    @data["allowMissingReceipt"] = true
    rejects(/fields differ/) { profile }
  end

  def test_unknown_descriptor_fields
    @data["bundleVerifier"] = descriptor("verifier", "fixture").merge("skipSignature" => true)
    rejects(/fields differ/) { profile }
  end

  def test_no_legacy_namespace
    @data["namespace"] = "v91"
    rejects(/namespace/) { profile }
  end

  def test_no_unbounded_namespace
    @data["namespace"] = "host-" + "n" * 80
    rejects(/namespace/) { profile }
  end

  def test_source_commit_cannot_inject_git_arguments
    @data["source"]["commit"] = "--output=/Applications/overwrite"
    rejects(/commit/) { profile }
  end

  def test_source_upstream_must_match_branch
    @data["source"]["upstream"] = "origin/main"
    rejects(/upstream/) { profile }
  end

  def test_no_installed_candidate
    @data["candidate"]["appPath"] = "/Applications/Beluga Host.app"
    rejects(/installed\/runtime/) { profile }
  end

  def test_no_runtime_candidate
    @data["candidate"]["appPath"] = Inputs::Legacy::Pins::RUNTIME_ROOT + "/Beluga Host.app"
    rejects(/installed\/runtime/) { profile }
  end

  def test_no_path_traversal
    @data["candidate"]["appPath"] = @root + "/../Beluga Host.app"
    rejects(/normalized absolute/) { profile }
  end

  def test_exact_candidate_basename
    @data["candidate"]["appPath"] = @root + "/opensteamer Host.app"
    rejects(/basename/) { profile }
  end

  def test_same_candidate_and_predecessor_rejected
    @data["predecessor"]["executableSHA256"] = @data["candidate"]["executableSHA256"]
    rejects(/equals predecessor/) { profile }
  end

  def test_a_filled_receipt_does_not_enable_execution
    artifact = descriptor("not-a-real-receipt.txt", "this is not a successful deployment receipt\n")
    %w[copyManifest buildEvidence].each { |key| @data["candidate"][key] = artifact.dup }
    %w[receipt copyManifest].each { |key| @data["predecessor"][key] = artifact.dup }
    %w[bundleVerifier reference].each { |key| @data[key] = artifact.dup }
    value = profile
    assert_empty value.missing_evidence
    rejects(/execution is not implemented/) { value.require_deployment_binding! }
  end

  def test_import_refuses_missing_manifest_before_any_git_or_app_operation
    rejects(/copy manifest is missing/) { Inputs::PrebuiltImport.new(profile).verify!(source_repository: "/nonexistent") }
  end

  def test_file_hash_mutation
    value = descriptor("manifest.txt", "original")
    File.write(value["path"], "changed")
    rejects(/digest mismatch/) { Inputs::Checks.file!(value, "fixture") }
  end

  def test_descriptor_symlink_rejected
    value = descriptor("actual.txt", "original")
    path = File.join(@root, "alias.txt")
    File.symlink(value["path"], path)
    value["path"] = path
    rejects(/alias/) { Inputs::Checks.file!(value, "fixture") }
  end

  def test_descriptor_hardlink_rejected
    value = descriptor("actual.txt", "original")
    File.link(value["path"], File.join(@root, "hardlink.txt"))
    rejects(/hard-link/) { Inputs::Checks.file!(value, "fixture") }
  end

  def test_verifier_no_missing_or_arbitrary_reference
    rejects(/bundle verifier is missing/) { Inputs::VerifierAdapter.arguments(profile) }
    @data["bundleVerifier"] = descriptor("verify.sh", "fixture verifier")
    @data["reference"] = descriptor("reference", "fixture reference")
    [@data["bundleVerifier"], @data["reference"]].each { |value| File.chmod(0o755, value["path"]) }
    rejects(/approved compatibility reference/) { Inputs::VerifierAdapter.arguments(profile) }
  end

  def make_candidate
    app = @data.fetch("candidate").fetch("appPath")
    framework = File.join(app, "Contents/Frameworks/LiveKitWebRTC.framework")
    FileUtils.mkdir_p(File.join(app, "Contents/MacOS"), mode: 0o755)
    %w[Headers Modules Resources].each { |name| FileUtils.mkdir_p(File.join(framework, "Versions/A", name), mode: 0o755) }
    File.write(File.join(framework, "Versions/A/LiveKitWebRTC"), "framework fixture")
    File.chmod(0o755, File.join(framework, "Versions/A/LiveKitWebRTC"))
    Inputs::Legacy::Pins::ALLOWED_CANDIDATE_SYMLINKS.each do |relative, target|
      File.symlink(target, File.join(app, relative))
    end
    executable = File.join(app, "Contents/MacOS/CaptureServer")
    File.write(executable, "candidate fixture")
    File.chmod(0o755, executable)
    @data["candidate"]["executableSHA256"] = Digest::SHA256.file(executable).hexdigest
    rendered, = Inputs::Legacy::CopyManifest.new(app).render
    @data["candidate"]["copyManifest"] = descriptor("copy-manifest.txt", rendered)
    @data["candidate"]["buildEvidence"] = descriptor("fixture-build.txt", "synthetic artifact; no production proof")
    repository = File.join(@root, "source")
    FileUtils.mkdir_p(repository)
    commands = [
      ["init", "-q"], ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
      "commit", "--allow-empty", "--no-gpg-sign", "-qm", "offline fixture"]
    ]
    commands.each { |arguments| Inputs::Util.capture!("/usr/bin/git", "-C", repository, *arguments) }
    @data["source"]["commit"] = Inputs::Util.capture!("/usr/bin/git", "-C", repository, "rev-parse", "HEAD").strip
    @data["source"]["tree"] = Inputs::Util.capture!("/usr/bin/git", "-C", repository, "rev-parse", "HEAD^{tree}").strip
    [repository, app]
  end

  def test_positive_prebuilt_inputs_still_do_not_authorize_deployment
    repository, = make_candidate
    value = profile
    plan = Inputs::PrebuiltImport.new(value).verify!(source_repository: repository)
    assert_equal "ARTIFACT_INPUTS_ONLY_NOT_DEPLOYMENT_READY", plan.fetch("status")
    assert_equal value.sha256, plan.fetch("profileSHA256")
    rejects(/predecessor.receipt/) { value.require_deployment_binding! }
  end

  def test_prebuilt_copy_manifest_detects_extra_code
    repository, app = make_candidate
    File.write(File.join(app, "Contents/MacOS/Unexpected"), "unreviewed")
    rejects(/manifest mismatch/) { Inputs::PrebuiltImport.new(profile).verify!(source_repository: repository) }
  end

  def test_source_tree_mismatch
    repository, = make_candidate
    @data["source"]["tree"] = "1" * 40
    rejects(/commit\/tree binding/) { Inputs::PrebuiltImport.new(profile).verify!(source_repository: repository) }
  end

  def test_candidate_symlink_rejected
    repository, app = make_candidate
    replacement = File.join(@root, "real.app")
    File.rename(app, replacement)
    File.symlink(replacement, app)
    rejects(/app traverses an alias/) { Inputs::PrebuiltImport.new(profile).verify!(source_repository: repository) }
  end

  def test_no_cli_execution_or_preflight
    script = File.expand_path("../macOS/scripts/opensteamer-host-successor-inputs.rb", __dir__)
    output, status = Open3.capture2e("/usr/bin/ruby", script, "--execute-authorized-cutover")
    assert_equal 64, status.exitstatus
    assert_match(/not a preflight or execution command/, output)
  end
end
