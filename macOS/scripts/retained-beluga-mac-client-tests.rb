# frozen_string_literal: true

require_relative 'retained-beluga-mac-client'

module BelugaMacClientRetainedTests
  B = BelugaMacClient::RetainedProductBinding
  R = BelugaMacClient::Refusal

  def setup_retained_model
    developer = '/synthetic/Xcode.app/Contents/Developer'
    output = '/synthetic/product'
    @context = {
      'originalProduct' => { 'commit' => '1' * 40, 'tree' => '2' * 40 },
      'currentTooling' => { 'commit' => '3' * 40, 'tree' => '4' * 40 },
      'originalReceipt' => { 'path' => '/synthetic/original/receipt.json', 'sha256' => '5' * 64 },
      'currentReceipt' => { 'path' => '/synthetic/current/receipt.json', 'sha256' => '6' * 64 },
      'app' => { 'path' => output + '/Beluga Host.app', 'treeSHA256' => '7' * 64 },
      'identitySHA1' => 'A' * 40,
      'gitDelta' => [
        { 'path' => 'MAC_CLIENT_ROADMAP.md', 'originalMode' => 100644, 'currentMode' => 100644,
          'originalBlobSHA1' => '8' * 40, 'currentBlobSHA1' => '9' * 40 },
        { 'path' => 'macOS/scripts/build-beluga-mac-client-contract.rb', 'originalMode' => 100644,
          'currentMode' => 100644, 'originalBlobSHA1' => 'a' * 40, 'currentBlobSHA1' => 'b' * 40 }
      ],
      'failedBuild' => {
        'builderScriptSHA256' => '8' * 64,
        'argv' => ['/usr/bin/ruby', B::BUILDER, '--output', output, '--scratch', '/synthetic/scratch', '--identity', 'A' * 40],
        'environment' => {
          'PATH' => developer + '/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin',
          'HOME' => '/synthetic/account', 'DEVELOPER_DIR' => developer, 'TMPDIR' => '/synthetic/scratch',
          'LC_ALL' => 'C', 'MACOSX_DEPLOYMENT_TARGET' => '14.0', 'SWIFT_TREAT_WARNINGS_AS_ERRORS' => 'YES'
        },
        'logs' => B::PRODUCTS.each_with_index.map do |product, index|
          { 'product' => product, 'path' => output + '/' + product + '-build.log', 'sha256' => (index + 9).to_s(16) * 64 }
        end,
        'failureLog' => { 'path' => '/synthetic/evidence/failure.log', 'sha256' => 'c' * 64 },
        'observerAttestation' => { 'path' => '/synthetic/evidence/root-attestation.json', 'sha256' => 'd' * 64 },
        'originalFinalChecksCompleted' => false, 'successfulBuildReport' => false, 'stage' => 'artifact-verification'
      }
    }
    # Mutable synthetic caller inputs make copy tests independent of frozen literals.
    @context = clone_data(@context)
    @manifest = clone_data(@context).merge('schema' => B::SCHEMA, 'authority' => B::AUTHORITY)
  end

  def test_keeps_original_product_and_current_tooling_sources_separate
    binding = parse
    assert_equal @context['originalProduct'], binding.expected_product_source
    assert_equal @context['currentTooling'], binding.current_tooling
    refute_equal binding.original_product, binding.current_tooling
    assert_equal @context['originalReceipt'], binding.original_receipt
    assert_equal @context['currentReceipt'], binding.current_receipt
    assert_equal @context['app'], binding.app
    assert_equal @context['gitDelta'], binding.git_delta
    assert_equal @context['identitySHA1'], binding.identity_sha1
    refute binding.successful_build_report?
    refute binding.original_final_checks_completed?
    assert binding.retrospective_observer_claim?
    refute_respond_to binding, :build_report
  end

  def test_all_retained_context_and_nested_outputs_are_copied_and_frozen
    binding = parse
    @context['originalProduct']['commit'].replace('f' * 40)
    @context['failedBuild']['argv'].clear
    @context['failedBuild']['environment']['HOME'].replace('/other/account')
    @context['gitDelta'][0]['path'].replace('other.md')
    assert_equal '1' * 40, binding.original_product['commit']
    assert_equal 8, binding.failed_build['argv'].length
    assert_equal '/synthetic/account', binding.failed_build['environment']['HOME']
    assert_equal 'MAC_CLIENT_ROADMAP.md', binding.git_delta[0]['path']
    [binding.original_product, binding.current_tooling, binding.original_receipt,
     binding.current_receipt, binding.app, binding.failed_build, binding.git_delta].each { |value| deeply_frozen(value) }
    assert_raises(FrozenError) { binding.failed_build['argv'] << '--unreviewed' }
    assert_raises(FrozenError) { binding.original_product['commit'].replace('f' * 40) }
  end

  def test_exact_original_current_source_and_receipt_distinction_is_required
    %w[originalProduct currentTooling].each do |name|
      %w[commit tree].each { |field| refused_change { |m| m[name][field] = 'e' * 40 } }
    end
    %w[originalReceipt currentReceipt].each do |name|
      %w[path sha256].each { |field| refused_change { |m| m[name][field] = field == 'path' ? '/other' : 'e' * 64 } }
    end
    context = clone_data(@context)
    context['currentTooling'] = clone_data(context['originalProduct'])
    assert_context_refused(context)
    context = clone_data(@context)
    context['currentReceipt'] = clone_data(context['originalReceipt'])
    assert_context_refused(context)
  end

  def test_exact_app_identity_builder_logs_and_external_attestation_binding_required
    refused_change { |m| m['app']['treeSHA256'] = 'e' * 64 }
    refused_change { |m| m['identitySHA1'] = 'E' * 40 }
    refused_change { |m| m['failedBuild']['builderScriptSHA256'] = 'e' * 64 }
    refused_change { |m| m['failedBuild']['logs'][0]['sha256'] = 'e' * 64 }
    refused_change { |m| m['failedBuild']['failureLog']['sha256'] = 'e' * 64 }
    refused_change { |m| m['failedBuild']['observerAttestation']['sha256'] = 'e' * 64 }
    refused_change { |m| m['failedBuild'].delete('observerAttestation') }
    refused_change { |m| m['failedBuild']['observerAttestation'] = m['failedBuild']['failureLog'] }
  end

  def test_a_success_report_or_machine_journal_claim_cannot_replace_failed_observation
    [true, 0, 'false', nil].each do |value|
      %w[originalFinalChecksCompleted successfulBuildReport].each do |field|
        context = clone_data(@context)
        context['failedBuild'][field] = value
        assert_context_refused(context)
      end
    end
    refused_change { |m| m['failedBuild']['stage'] = 'build-complete' }
    refused_change { |m| m['authority'] = 'machine-journal' }
    refused_change { |m| m['buildReport'] = { 'status' => 'SIGNED_VERIFIED_NOT_NOTARIZED' } }
    refused_change { |m| m['failedBuild']['success'] = false }
  end

  def test_three_fixed_products_logs_and_observed_outer_argument_order
    context = clone_data(@context)
    context['failedBuild']['argv'][1] = '/synthetic/source/' + B::BUILDER
    assert_equal context['failedBuild']['argv'], parse(context: context, manifest: manifest_for(context)).failed_build['argv']
    [[], @context['failedBuild']['logs'].reverse, @context['failedBuild']['logs'][0, 2]].each do |logs|
      context = clone_data(@context)
      context['failedBuild']['logs'] = logs
      assert_context_refused(context)
    end
    context = clone_data(@context)
    context['failedBuild']['logs'][1]['product'] = 'OtherProduct'
    assert_context_refused(context)
    context = clone_data(@context)
    context['failedBuild']['logs'][0]['path'] = '/other/CaptureServer-build.log'
    assert_context_refused(context)
    context = clone_data(@context)
    context['failedBuild']['argv'][2], context['failedBuild']['argv'][4] = '--scratch', '--output'
    assert_context_refused(context)
    context = clone_data(@context)
    context['failedBuild']['argv'][0] = '/other/ruby'
    assert_context_refused(context)
    context = clone_data(@context)
    context['failedBuild']['argv'][1] = 'other-builder.rb'
    assert_context_refused(context)
  end

  def test_only_pinned_derived_swift_child_environment_not_parent_shell_metadata
    %w[PATH TMPDIR LC_ALL MACOSX_DEPLOYMENT_TARGET SWIFT_TREAT_WARNINGS_AS_ERRORS].each do |field|
      context = clone_data(@context)
      context['failedBuild']['environment'][field] = 'unreviewed'
      assert_context_refused(context)
    end
    context = clone_data(@context)
    context['failedBuild']['environment']['SWIFT_EXEC'] = '/other/compiler'
    assert_context_refused(context)
    context = clone_data(@context)
    context['failedBuild']['environment']['HOME'] = true
    assert_context_refused(context)
    refused_change { |m| m['failedBuild']['environment']['HOME'] = '/different/account' }
  end

  def test_reviewed_git_delta_is_exact_sorted_unique_and_native_mode_typed
    refused_change { |m| m['gitDelta'][0]['currentBlobSHA1'] = 'e' * 40 }
    [[], @context['gitDelta'].reverse, [@context['gitDelta'][0]] * 2].each do |entries|
      context = clone_data(@context)
      context['gitDelta'] = entries
      assert_context_refused(context)
    end
    [100644.0, '100644', true, nil, 120000, 100600].each do |mode|
      context = clone_data(@context)
      context['gitDelta'][0]['currentMode'] = mode
      assert_context_refused(context)
    end
    ['../escape.rb', '/absolute.rb', 'a//b.rb', 'a/./b.rb', 'a\\b.rb'].each do |path|
      context = clone_data(@context)
      context['gitDelta'][0]['path'] = path
      assert_context_refused(context)
    end
  end

  def test_explicit_added_deleted_and_mode_only_git_entries_without_actual_git_claim
    context = clone_data(@context)
    context['gitDelta'][0]['originalMode'] = 0
    context['gitDelta'][0]['originalBlobSHA1'] = '0' * 40
    assert_equal 0, parse(context: context, manifest: manifest_for(context)).git_delta[0]['originalMode']
    context = clone_data(@context)
    context['gitDelta'][0]['currentMode'] = 0
    context['gitDelta'][0]['currentBlobSHA1'] = '0' * 40
    assert_equal 0, parse(context: context, manifest: manifest_for(context)).git_delta[0]['currentMode']
    context = clone_data(@context)
    context['gitDelta'][0]['currentMode'] = 100755
    context['gitDelta'][0]['currentBlobSHA1'] = context['gitDelta'][0]['originalBlobSHA1']
    assert_equal 100755, parse(context: context, manifest: manifest_for(context)).git_delta[0]['currentMode']
    context['gitDelta'][0]['currentMode'] = 100644
    assert_context_refused(context)
  end

  def test_unknown_missing_nested_fields_and_digest_shapes_are_refused
    B::CONTEXT_KEYS.each { |key| refused_change { |m| m.delete(key) } }
    refused_change { |m| m['originalProduct']['version'] = 1 }
    refused_change { |m| m['failedBuild']['logs'][0]['exitCode'] = 0 }
    refused_change { |m| m['originalProduct']['commit'] = '0' * 40 }
    refused_change { |m| m['app']['treeSHA256'] = 'A' * 64 }
    refused_change { |m| m['identitySHA1'] = 'a' * 40 }
    refused_change { |m| m['currentReceipt']['sha256'] = nil }
  end

  def test_bounded_duplicate_free_json_and_independent_raw_digest
    bytes = JSON.generate(@manifest)
    assert_raises(R) { parse_bytes(bytes, expected: 'e' * 64) }
    assert_equal Digest::SHA256.hexdigest(bytes), parse_bytes(bytes).manifest_sha256
    assert_refused_bytes(bytes.sub('"authority":', '"authority":"' + B::AUTHORITY + '","authority":'))
    assert_refused_bytes(bytes.sub('"commit":', '"\\u0063ommit":"' + '1' * 40 + '","commit":'))
    assert_refused_bytes(bytes.sub('"stage":', '"stage":"artifact-verification","stage":'))
    ['', '{}', '[]', 'null', bytes + '{}', bytes + "\xff".b,
     ' ' * (B::MAXIMUM_MANIFEST_BYTES + 1), '[' * 10 + '0' + ']' * 10].each { |input| assert_refused_bytes(input) }
  end

  def test_collected_context_types_bounds_and_no_direct_constructor
    context = clone_data(@context)
    context['failedBuild']['argv'] = ['x'] * 65
    assert_context_refused(context)
    context = clone_data(@context)
    context['app']['path'] = 'x' * 4097
    assert_context_refused(context)
    context = clone_data(@context)
    context['failedBuild']['cycle'] = context
    assert_raises(R) { parse(context: context) }
    assert_raises(NoMethodError) { B.new({}, '') }
    refute_includes parse.inspect, '/synthetic/'
  end

  def test_retained_factory_requires_actual_current_receipt_before_reading_evidence
    fake = Object.new
    fake.define_singleton_method(:verify!) { raise 'must not call a fake validator' }
    assert_raises(R) do
      BelugaMacClient::AdmittedRetainedProduct.open('/nonexistent', 'a' * 64, receipt: fake,
        app: '/nonexistent/Beluga Host.app', identity: 'A' * 40)
    end
  end

  def test_retained_native_source_boundary_rejects_raw_hash_or_data_parser
    require_relative 'verify-beluga-mac-client'
    [@context['originalProduct'], parse, Object.new].each do |binding|
      assert_raises(R) { BelugaMacClient.product_source_for!('/nonexistent', binding) }
    end
    assert_raises(NoMethodError) { BelugaMacClient::AdmittedRetainedProduct.new }
  end

  def test_package_authority_requires_exactly_one_build_or_complete_retained_binding
    app = File.join(@directory, 'Beluga Host.app')
    build = File.join(@directory, 'build.json')
    assert_raises(R) { BelugaMacClient.package_evidence_mode!(app, nil, nil) }
    [[nil, 'a' * 64], ['/manifest', nil], ['', 'a' * 64], ['/manifest', 'bad']].each do |path, sha|
      assert_raises(R) { BelugaMacClient.package_evidence_mode!(app, path, sha) }
    end
    assert_equal :retained, BelugaMacClient.package_evidence_mode!(app, '/manifest', 'a' * 64)
    File.write(build, '{}', perm: 0o600)
    assert_equal :build, BelugaMacClient.package_evidence_mode!(app, nil, nil)
    assert_raises(R) { BelugaMacClient.package_evidence_mode!(app, '/manifest', 'a' * 64) }
    File.unlink(build)
    File.symlink('/nonexistent-build', build)
    assert_raises(R) { BelugaMacClient.package_evidence_mode!(app, '/manifest', 'a' * 64) }
  end

  def test_retained_admitted_provenance_cannot_mutate_product_or_tooling_fences
    shape = parse
    receipt = Object.new
    receipt.define_singleton_method(:evidence_binding) { shape.current_receipt }
    # Exercise storage only, not the production factory's admission authority.
    binding = BelugaMacClient::AdmittedRetainedProduct.send(:new, nil, receipt,
      @context['currentTooling'], shape, '/synthetic/manifest', 'e' * 64, @context['app']['path'],
      { 'source' => {}, 'tools' => {} })
    @context['currentTooling']['commit'].replace('f' * 40)
    @context['app']['path'].replace('/other')
    assert_equal '3' * 40, binding.provenance['currentTooling']['commit']
    deeply_frozen(binding.provenance)
    assert_raises(FrozenError) { binding.provenance['currentTooling']['commit'].replace('f' * 40) }
    assert_raises(FrozenError) { binding.provenance['manifest']['path'].replace('/other') }
    assert binding.frozen?
    assert_equal shape.original_product, binding.product_source
  end

  def test_retained_product_log_requires_one_exact_success_terminal
    evidence = BelugaMacClient::RetainedEvidence
    product = 'CaptureServer'
    terminal = "Build of product 'CaptureServer' complete! (64.76s)\n"
    assert evidence.completed_product_log!("compiling\n" + terminal + "fetching stderr\n", product)
    ['', terminal.sub(product, 'OtherProduct'), terminal.sub('complete!', 'failed!'),
      terminal + terminal, terminal.sub('(64.76s)', '(unknown)')].each do |bytes|
      assert_raises(R) { evidence.completed_product_log!(bytes, product) }
    end
  end

  def test_retained_boundary_rechecks_ignored_input_inventory_and_tested_tool_bytes
    gate = MicrophoneRegressionGate
    original = gate.method(:source_identity)
    expected = { 'fixture' => 'original inventory' }
    observed = expected.dup
    gate.define_singleton_method(:source_identity) { |_root| observed }
    tool = File.join(@directory, 'tested-tool-fixture')
    File.write(tool, 'tested bytes', perm: 0o600)
    tools = { tool => Digest::SHA256.file(tool).hexdigest }
    assert BelugaMacClient::RetainedEvidence.fresh_inputs!(expected, tools)
    observed['fixture'] = 'ignored artifact drift'
    assert_raises(R) { BelugaMacClient::RetainedEvidence.fresh_inputs!(expected, tools) }
    observed['fixture'] = expected['fixture']
    File.write(tool, 'replacement tool')
    assert_raises(R) { BelugaMacClient::RetainedEvidence.fresh_inputs!(expected, tools) }
  ensure
    gate.define_singleton_method(:source_identity, original) if original
  end

  private

  def parse(context: @context, manifest: @manifest)
    parse_bytes(JSON.generate(manifest), context: context)
  end

  def parse_bytes(bytes, context: @context, expected: Digest::SHA256.hexdigest(bytes))
    B.parse(bytes, expected_manifest_sha256: expected, collected_context: context)
  end

  def manifest_for(context)
    clone_data(context).merge('schema' => B::SCHEMA, 'authority' => B::AUTHORITY)
  end

  def assert_context_refused(context)
    assert_raises(R) { parse(context: context, manifest: manifest_for(context)) }
  end

  def refused_change
    manifest = clone_data(@manifest)
    yield manifest
    assert_raises(R) { parse(manifest: manifest) }
  end

  def assert_refused_bytes(bytes)
    assert_raises(R) { parse_bytes(bytes) }
  end

  def clone_data(value)
    Marshal.load(Marshal.dump(value))
  end

  def deeply_frozen(value)
    assert value.frozen?
    case value
    when Hash
      value.each { |key, item| assert key.frozen?; deeply_frozen(item) }
    when Array
      value.each { |item| deeply_frozen(item) }
    end
  end
end

module BelugaMacClientRetainedTests
  def test_retained_collector_uses_raw_blob_sha256_and_actual_receipt_modes
    old, now, delta, blobs = retained_collector_inputs
    assert_equal 0o600, old.fetch('files').last[2]
    assert_equal 0o644, now.fetch('files').last[2]
    assert_equal 100644, delta.first.fetch('originalMode')
    assert BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, now, delta, blobs)
    mutated = clone_data(now.fetch('files'))
    bytes = blobs.fetch(delta.first.fetch('currentBlobSHA1'))
    mutated.last[3] = Digest::SHA256.hexdigest("blob #{bytes.bytesize}\0" + bytes)
    assert_raises(R) do
      BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, retained_collector_inventory(mutated), delta, blobs)
    end
  end

  def test_retained_collector_refuses_ignored_dependency_mode_bytes_and_membership_drift
    old, now, delta, blobs = retained_collector_inputs
    [lambda { |rows| rows.first[2] = 0o600 },
     lambda { |rows| rows.first[3] = Digest::SHA256.hexdigest('drift') },
     lambda { |rows| rows.shift }].each do |change|
      rows = clone_data(now.fetch('files'))
      change.call(rows)
      assert_raises(R) do
        BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, retained_collector_inventory(rows), delta, blobs)
      end
    end
  end

  def test_retained_collector_refuses_wrong_blob_executable_class_and_missing_tooling
    old, now, delta, blobs = retained_collector_inputs
    wrong_blobs = blobs.merge(delta.first.fetch('currentBlobSHA1') => 'wrong bytes')
    assert_raises(R) { BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, now, delta, wrong_blobs) }
    wrong_mode = clone_data(delta)
    wrong_mode.first['currentMode'] = 100755
    assert_raises(R) { BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, now, wrong_mode, blobs) }
    missing = retained_collector_inventory(now.fetch('files')[0...-1])
    assert_raises(R) { BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, missing, delta, blobs) }
  end

  def test_retained_collector_added_deleted_and_mode_only_entries_are_exact
    old, now, delta, blobs = retained_collector_inputs
    absent = retained_collector_inventory(old.fetch('files')[0...-1])
    added = clone_data(delta)
    added.first.merge!('originalMode' => 0, 'originalBlobSHA1' => '0' * 40)
    assert BelugaMacClient::RetainedEvidence.equivalent_inputs!(absent, now, added, blobs)
    assert_raises(R) { BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, now, added, blobs) }
    deleted = clone_data(delta)
    deleted.first.merge!('currentMode' => 0, 'currentBlobSHA1' => '0' * 40)
    assert BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, absent, deleted, blobs)
    deleted.first['currentBlobSHA1'] = '1' * 40
    assert_raises(R) { BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, absent, deleted, blobs) }
    rows = clone_data(old.fetch('files'))
    rows.last[2] = 0o700
    mode_only = clone_data(delta)
    mode_only.first.merge!('currentMode' => 100755, 'currentBlobSHA1' => delta.first.fetch('originalBlobSHA1'))
    assert BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, retained_collector_inventory(rows), mode_only, blobs)
  end

  def test_retained_collector_inventory_and_reviewed_delta_cannot_hide_mutations
    old, now, delta, blobs = retained_collector_inputs
    [old.fetch('files').reverse, old.fetch('files') + [old.fetch('files').last],
     [[ '../escape', 'file', 0o600, 'a' * 64 ]]].each do |rows|
      assert_raises(R) { BelugaMacClient::RetainedEvidence.inventory!(retained_collector_inventory(rows)) }
    end
    wrong_digest = clone_data(old)
    wrong_digest['sha256'] = '0' * 64
    assert_raises(R) { BelugaMacClient::RetainedEvidence.inventory!(wrong_digest) }
    [[], delta + delta, [delta.first.merge('path' => 'shared/Sources/Product.swift')]].each do |entries|
      assert_raises(R) { BelugaMacClient::RetainedEvidence.equivalent_inputs!(old, now, entries, blobs) }
    end
  end

  def test_retained_collector_reader_accepts_exact_empty_log_and_preserves_digest_guards
    path = retained_collector_write(@directory, 'empty-history.log', ''.b)
    sha = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    reader = BelugaMacClient::RetainedEvidence::Reader.new
    bytes = reader.read(path, expected: sha, limit: 0)
    assert_instance_of String, bytes
    assert_equal Encoding::BINARY, bytes.encoding
    assert_equal ''.b, bytes
    assert_equal sha, Digest::SHA256.hexdigest(bytes)
    assert_equal ''.b, reader.read(path, expected: sha)
    assert reader.verify!
    assert_raises(R) { reader.read(path, expected: '0' * 64) }
    File.binwrite(path, 'x')
    assert_raises(R) { reader.read(path, expected: sha, limit: 1) }
    assert_raises(R) { reader.verify! }
  end

  def test_retained_collector_reader_empty_bytes_do_not_hide_inode_replacement
    path = retained_collector_write(@directory, 'empty-record', ''.b)
    reader = BelugaMacClient::RetainedEvidence::Reader.new
    sha = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    assert_equal ''.b, reader.read(path, expected: sha)
    File.rename(path, File.join(@directory, 'original-empty-record'))
    retained_collector_write(@directory, 'empty-record', ''.b)
    assert_raises(R) { reader.read(path, expected: sha) }
    assert_raises(R) { reader.verify! }
  end

  def test_retained_collector_reader_pins_exact_bytes_digest_bound_and_inode
    path = retained_collector_write(@directory, 'record', 'retained bytes')
    reader = BelugaMacClient::RetainedEvidence::Reader.new
    sha = Digest::SHA256.hexdigest('retained bytes')
    assert_equal 'retained bytes', reader.read(path, expected: sha, limit: 14)
    assert reader.verify!
    assert_raises(R) { reader.read(path, expected: '0' * 64) }
    assert_raises(R) { reader.read(path, limit: 13) }
    File.rename(path, File.join(@directory, 'original-record'))
    retained_collector_write(@directory, 'record', 'retained bytes')
    assert_raises(R) { reader.read(path, expected: sha) }
    assert_raises(R) { reader.verify! }
  end

  def test_retained_collector_reader_refuses_file_and_parent_aliases
    path = retained_collector_write(@directory, 'record', 'bytes')
    reader = BelugaMacClient::RetainedEvidence::Reader.new
    linked = File.join(@directory, 'linked')
    File.symlink(path, linked)
    assert_raises(R) { reader.read(linked) }
    File.link(path, File.join(@directory, 'hardlinked'))
    assert_raises(R) { reader.read(path) }
    child = File.join(@directory, 'private')
    Dir.mkdir(child, 0o700)
    nested = retained_collector_write(child, 'record', 'bytes')
    File.symlink(child, File.join(@directory, 'parent-alias'))
    assert_raises(R) { reader.read(File.join(@directory, 'parent-alias', 'record')) }
    assert_equal 'bytes', reader.read(nested)
  end

  def test_retained_collector_reader_requires_private_modes_and_retained_directory_inode
    child = File.join(@directory, 'evidence')
    Dir.mkdir(child, 0o700)
    path = retained_collector_write(child, 'record', 'bytes')
    File.chmod(0o755, child)
    assert_raises(R) { BelugaMacClient::RetainedEvidence::Reader.new.read(path) }
    assert_equal 'bytes', BelugaMacClient::RetainedEvidence::Reader.new.read(path, private_parent: false)
    File.chmod(0o777, child)
    assert_raises(R) { BelugaMacClient::RetainedEvidence::Reader.new.read(path, private_parent: false) }
    File.chmod(0o700, child)
    reader = BelugaMacClient::RetainedEvidence::Reader.new
    reader.read(path)
    File.rename(child, File.join(@directory, 'original-evidence'))
    Dir.mkdir(child, 0o700)
    retained_collector_write(child, 'record', 'bytes')
    assert_raises(R) { reader.read(path) }
    assert_raises(R) { reader.verify! }
  end

  private

  def retained_collector_inventory(rows)
    { 'files' => rows, 'sha256' => Digest::SHA256.hexdigest(JSON.generate(rows)) }
  end

  def retained_collector_inputs
    path = 'macOS/scripts/verify-beluga-mac-client.rb'
    before = 'old reviewed tooling'
    after = 'new reviewed tooling'
    old_oid = Digest::SHA1.hexdigest("blob #{before.bytesize}\0" + before)
    new_oid = Digest::SHA1.hexdigest("blob #{after.bytesize}\0" + after)
    stable = ['.build/checkouts/Synthetic/Package.swift', 'file', 0o644, Digest::SHA256.hexdigest('unchanged ignored input')]
    old = retained_collector_inventory([stable, [path, 'file', 0o600, Digest::SHA256.hexdigest(before)]])
    now = retained_collector_inventory([stable.dup, [path, 'file', 0o644, Digest::SHA256.hexdigest(after)]])
    delta = [{ 'path' => path, 'originalMode' => 100644, 'currentMode' => 100644,
               'originalBlobSHA1' => old_oid, 'currentBlobSHA1' => new_oid }]
    [old, now, delta, { old_oid => before, new_oid => after }]
  end

  def retained_collector_write(directory, name, bytes)
    path = File.join(directory, name)
    File.binwrite(path, bytes)
    File.chmod(0o600, path)
    path
  end
end
