# frozen_string_literal: true
require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative 'opensteamer-microphone-v9-input-staging'

class BelugaMicrophoneV9InputStagingTest < Minitest::Test
  Staging = BelugaMicrophoneV9InputStaging
  Contract = Staging::Contract

  def with_directory(prefix = 'beluga-microphone-v9-guards.offline-')
    skip 'staging requires the original UID 501' unless Process.uid == 501 && Process.euid == 501
    root = Dir.mktmpdir(prefix, '/private/tmp')
    File.chmod(0700, root)
    yield root
  ensure
    FileUtils.remove_entry_secure(root) if root && File.exist?(root)
  end

  def fixture_file(path, bytes = "offline input\n", mode = 0644)
    File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, mode) do |file|
      file.chmod(mode)
      file.write(bytes)
      file.flush
      file.fsync
    end
    Staging.record!(path)
  end

  def with_capsule
    with_directory do |root|
      original = fixture_file(root + '/original', "offline bytes\0\xff\n".b, 0755)
      capsule = Staging::Capsule.new(root)
      capsule.directory!('inputs')
      yield root, capsule, original
    ensure
      capsule&.close
    end
  end

  # The second read-open is the held source FD used for the copy, after the
  # independent pre-copy record check. No process or real artifact is involved.
  def during_copy_read(source, mutation)
    original_open = File.method(:open)
    source_opens = 0
    replacement = lambda do |path, *arguments, &block|
      if path == source && arguments.first == (File::RDONLY | File::NOFOLLOW)
        source_opens += 1
        if source_opens == 2
          return original_open.call(path, *arguments) do |file|
            original_read = file.method(:read)
            fired = false
            file.define_singleton_method(:read) do |*read_arguments|
              bytes = original_read.call(*read_arguments)
              unless fired
                fired = true
                mutation.call
              end
              bytes
            end
            block.call(file)
          end
        end
      end
      original_open.call(path, *arguments, &block)
    end
    File.stub(:open, replacement) { yield }
  end

  def with_release_fixture
    with_directory do |root|
      Dir.mkdir(root + '/originals', 0700)
      dependencies = Staging::DEPENDENCY_ROLES.each_with_index.to_h do |role, index|
        [role, fixture_file(root + "/originals/dependency-#{index}", "offline #{role}\n", index >= 5 ? 0755 : 0644)]
      end
      artifacts = Contract::ARTIFACT_FILES.each_key.with_index.to_h do |name, index|
        [name, fixture_file(root + "/originals/producer-#{index}", "offline #{name}\n")]
      end
      artifacts['bundle'] = Contract::BUNDLE_NODES.select { |type, _, _| type == 'Regular File' }.each_with_index.to_h do |(_, mode, relative), index|
        [relative, fixture_file(root + "/originals/candidate-#{index}", "offline #{relative}\n", mode)]
      end
      Contract.stub(:verify_artifacts!, [artifacts, nil]) do
        Contract.stub(:verify_bundle_bytes!, true) { yield root, dependencies, artifacts }
      end
    end
  end

  def with_staged_fixture
    with_release_fixture do |root, dependencies, artifacts|
      originals, sealed, release = Staging.stage!(root, dependencies)
      sealed['tools/gate_inputs.txt'] = fixture_file(root + '/gate_inputs.txt', "offline gate\n", 0600)
      yield root, dependencies, artifacts, originals, sealed, release
    end
  end

  def test_copy_preserves_original_and_copies_exact_bytes_mode_hash_with_distinct_identity
    with_capsule do |root, capsule, original|
      before = Staging.record!(original.fetch('path'))
      copied = capsule.copy!(original, 'inputs/fixture')
      assert_equal before, Staging.record!(original.fetch('path'))
      assert_equal File.binread(original.fetch('path')), File.binread(copied.fetch('path'))
      assert_equal original.fetch('sha256'), copied.fetch('sha256')
      assert_equal 0755, File.lstat(copied.fetch('path')).mode & 07777
      refute_equal original.fetch('identity')[0, 2], copied.fetch('identity')[0, 2]
      assert_equal root + '/inputs/fixture', copied.fetch('path')
      assert_equal copied, Staging.record!(copied.fetch('path'), internal: true)
      assert capsule.fence!
    end
  end

  def test_duplicate_destination_is_refused_without_overwrite
    with_capsule do |_, capsule, original|
      copied = capsule.copy!(original, 'inputs/fixture')
      assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      assert_equal copied, Staging.record!(copied.fetch('path'), internal: true)
      assert_equal original, Staging.record!(original.fetch('path'))
    end
  end

  def test_existing_destination_symlink_is_refused_without_touching_target
    with_capsule do |root, capsule, original|
      target = fixture_file(root + '/target', "untouched target\n")
      File.symlink(target.fetch('path'), root + '/inputs/fixture')
      assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      assert_equal target, Staging.record!(target.fetch('path'))
      assert File.symlink?(root + '/inputs/fixture')
    end
  end

  def test_source_symlink_replacement_is_refused
    with_capsule do |root, capsule, original|
      File.rename(original.fetch('path'), root + '/held-original')
      File.symlink(root + '/held-original', original.fetch('path'))
      assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      refute File.exist?(root + '/inputs/fixture')
    end
  end

  def test_source_hardlink_is_refused
    with_capsule do |root, capsule, original|
      File.link(original.fetch('path'), root + '/source-hardlink')
      assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      refute File.exist?(root + '/inputs/fixture')
    end
  end

  def test_source_writeable_metadata_is_refused
    with_capsule do |root, capsule, original|
      File.chmod(0777, original.fetch('path'))
      assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      refute File.exist?(root + '/inputs/fixture')
      assert_equal 0777, File.lstat(original.fetch('path')).mode & 07777
    end
  end

  def test_source_empty_file_is_refused
    with_directory do |root|
      File.open(root + '/empty', File::WRONLY | File::CREAT | File::EXCL, 0644) { |file| file.fsync }
      assert_raises(Staging::Refused) { Staging.record!(root + '/empty') }
    end
  end

  def test_source_growth_during_copy_is_refused
    with_capsule do |_, capsule, original|
      source = original.fetch('path')
      during_copy_read(source, -> { File.open(source, 'ab') { |file| file.write('extra fixture bytes') } }) do
        assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      end
      refute_equal original, Staging.record!(source)
    end
  end

  def test_source_truncation_during_copy_is_refused
    with_capsule do |_, capsule, original|
      source = original.fetch('path')
      during_copy_read(source, -> { File.truncate(source, 1) }) do
        assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      end
      assert_equal 1, File.size(source)
    end
  end

  def test_source_metadata_change_during_copy_is_refused
    with_capsule do |_, capsule, original|
      source = original.fetch('path')
      during_copy_read(source, -> { File.chmod(0600, source) }) do
        assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      end
      assert_equal 0600, File.lstat(source).mode & 07777
    end
  end

  def test_held_parent_replacement_is_refused_before_destination_creation
    with_capsule do |root, capsule, original|
      File.rename(root + '/inputs', root + '/held-inputs')
      Dir.mkdir(root + '/inputs', 0700)
      assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      assert_empty Dir.children(root + '/inputs')
    end
  end

  def test_held_parent_symlink_replacement_is_refused
    with_capsule do |root, capsule, original|
      File.rename(root + '/inputs', root + '/held-inputs')
      File.symlink(root + '/held-inputs', root + '/inputs')
      assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
      assert_empty Dir.children(root + '/held-inputs')
    end
  end

  def test_nested_and_aliased_capsule_roots_are_refused
    with_directory do |root|
      Dir.mkdir(root + '/nested', 0700)
      [root + '/nested', root + '/', root + '/.'].each do |invalid|
        assert_raises(Staging::Refused, invalid) { Staging::Capsule.new(invalid) }
      end
    end
    with_directory('beluga-microphone-v9-guards.offline.') do |dotted|
      assert_equal dotted, File.realpath(dotted)
      assert_raises(Staging::Refused) { Staging::Capsule.new(dotted) }
    end
  end

  def test_non_uid_501_capsule_is_refused
    with_directory do |root|
      Process.stub(:uid, 502) do
        assert_raises(Staging::Refused) { Staging::Capsule.new(root) }
      end
      Process.stub(:euid, 0) do
        assert_raises(Staging::Refused) { Staging::Capsule.new(root) }
      end
    end
  end

  def test_unsafe_relative_paths_and_unheld_parents_are_refused
    with_capsule do |root, capsule, original|
      ['../escape', 'inputs/../escape', 'inputs//fixture', '/absolute', 'inputs/file space', '.', 'inputs/.', 'missing/fixture'].each do |relative|
        assert_raises(Staging::Refused, relative) { capsule.copy!(original, relative) }
      end
      assert_empty Dir.children(root + '/inputs')
    end
  end

  def test_null_acl_with_unknown_error_is_refused
    with_capsule do |root, capsule, original|
      Staging::EmptyACL::GET.stub(:call, 0) do
        Fiddle.stub(:last_error, 13) do
          assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
        end
      end
      refute File.exist?(root + '/inputs/fixture')
    end
  end

  def test_non_null_acl_is_refused_even_with_no_reported_entry
    with_capsule do |root, capsule, original|
      Staging::EmptyACL::GET.stub(:call, 1) do
        Staging::EmptyACL::ENTRY.stub(:call, 0) do
          Staging::EmptyACL::FREE.stub(:call, 0) do
            assert_raises(Staging::Refused) { capsule.copy!(original, 'inputs/fixture') }
          end
        end
      end
      refute File.exist?(root + '/inputs/fixture')
    end
  end

  def test_roles_have_exact_internal_path_mapping
    assert_equal 8, Staging::DEPENDENCY_ROLES.length
    assert_equal 16, Staging::RELEASE_ROLES.length
    (Staging::DEPENDENCY_ROLES + Staging::RELEASE_ROLES).each do |role|
      expected = 'inputs/' + (role.start_with?('candidate/') ? role.sub('candidate/', 'candidate.driver/') : role)
      assert_equal expected, Staging.internal_relative(role)
    end
  end

  def test_stage_and_audit_keep_originals_distinct_and_preserve_exact_candidate_layout
    with_staged_fixture do |root, dependencies, _, originals, sealed, release|
      assert_equal (Staging::DEPENDENCY_ROLES + Staging::RELEASE_ROLES).sort, originals.keys.sort
      assert_equal (Staging::DEPENDENCY_ROLES + ['tools/gate_inputs.txt']).sort, sealed.keys.sort
      assert_equal Staging::RELEASE_ROLES.sort, release.keys.sort
      originals.each do |role, original|
        copy = sealed[role] || release.fetch(role)
        assert_equal root + '/' + Staging.internal_relative(role), copy.fetch('path')
        assert_equal original.fetch('sha256'), copy.fetch('sha256')
        assert_equal original.fetch('identity')[4] & 07777, copy.fetch('identity')[4] & 07777
        refute_equal original.fetch('identity')[0, 2], copy.fetch('identity')[0, 2]
        assert_equal original, Staging.record!(original.fetch('path'))
      end
      Contract::BUNDLE_NODES.each do |type, mode, relative|
        path = root + '/inputs/candidate.driver' + (relative == '.' ? '' : '/' + relative)
        stat = File.lstat(path)
        assert_equal type == 'Directory', stat.directory?, relative
        assert_equal mode, stat.mode & 07777, relative
      end
      assert Staging.audit!(root, dependencies, originals, sealed, release)
    end
  end

  def test_unknown_dependency_role_is_refused_without_real_artifact_access
    with_directory do |root|
      original = fixture_file(root + '/original')
      dependencies = Staging::DEPENDENCY_ROLES.to_h { |role| [role, original] }
      unknown = dependencies.merge('tools/unknown' => original)
      Contract.stub(:verify_artifacts!, -> { flunk 'invalid role must be refused before artifact access' }) do
        assert_raises(Staging::Refused) { Staging.original_records!(unknown) }
      end
    end
  end

  def test_audit_refuses_missing_or_unknown_sealed_role
    with_staged_fixture do |root, dependencies, _, originals, sealed, release|
      missing = sealed.reject { |role, _| role == Staging::DEPENDENCY_ROLES.first }
      assert_raises(Staging::Refused) { Staging.audit!(root, dependencies, originals, missing, release) }
      unknown = sealed.merge('tools/unknown' => sealed.values.first)
      assert_raises(Staging::Refused) { Staging.audit!(root, dependencies, originals, unknown, release) }
    end
  end

  def test_audit_refuses_original_provenance_rebound_to_copy
    with_staged_fixture do |root, dependencies, _, originals, sealed, release|
      role = Staging::DEPENDENCY_ROLES.first
      rebound = originals.merge(role => sealed.fetch(role))
      assert_raises(Staging::Refused) { Staging.audit!(root, dependencies, rebound, sealed, release) }
    end
  end

  def test_audit_refuses_wrong_copy_role_path
    with_staged_fixture do |root, dependencies, _, originals, sealed, release|
      role = Staging::DEPENDENCY_ROLES.first
      wrong = sealed.merge(role => sealed.fetch(role).merge('path' => root + '/inputs/tools/wrong-path'))
      assert_raises(Staging::Refused) { Staging.audit!(root, dependencies, originals, wrong, release) }
    end
  end

  def test_audit_refuses_extra_file_and_empty_directory
    [:file, :directory].each do |extra|
      with_staged_fixture do |root, dependencies, _, originals, sealed, release|
        path = root + '/inputs/unrecorded'
        extra == :file ? fixture_file(path) : Dir.mkdir(path, 0700)
        assert_raises(Staging::Refused, extra.to_s) { Staging.audit!(root, dependencies, originals, sealed, release) }
      end
    end
  end

  def test_audit_refuses_copied_bytes_mutation
    with_staged_fixture do |root, dependencies, _, originals, sealed, release|
      copy = release.values.first
      File.open(copy.fetch('path'), 'ab') { |file| file.write('fixture mutation') }
      assert_raises(Staging::Refused) { Staging.audit!(root, dependencies, originals, sealed, release) }
    end
  end
end
