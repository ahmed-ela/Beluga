# Pure fixture proof for the boundary adapter, not an actual microphone receipt
# or deployment proof. Only the private verifier-executor seam is substituted.
# Git and all file/stat/digest fences run on fresh private throwaway repositories.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'
require 'digest'

# Optional retained-evidence locale replay only, not successful adapter binding.
if ARGV.first == '--actual-unicode-receipt-replay'
  arguments = ARGV.shift(4)
  raise 'usage: --actual-unicode-receipt-replay PRODUCT_ROOT ORIGINAL_RECEIPT INDEPENDENT_SHA256' unless arguments.length == 4
  root, receipt_path, expected_digest = arguments.drop(1)
  raise 'noncanonical replay input' unless File.realpath(root) == root && File.realpath(receipt_path) == receipt_path
  raise 'independent replay digest differs' unless expected_digest.match?(/\A[0-9a-f]{64}\z/) && Digest::SHA256.file(receipt_path).hexdigest == expected_digest
  require_relative 'opensteamer-microphone-receipt-binding'
  require root + '/scripts/microphone-regression-gate'
  receipt = JSON.parse(File.binread(receipt_path))
  raise 'replay root differs' unless receipt.fetch('root') == root
  snapshot = lambda do
    source = MicrophoneRegressionGate.source_identity(root)
    paths = receipt.fetch('tools').keys + [receipt_path, File.realpath(__dir__ + '/opensteamer-microphone-receipt-binding.rb')]
    source.fetch('files').each { |entry| paths << root + '/' + entry[0] }
    nodes = paths.uniq.sort.to_h do |path|
      stat = File.lstat(path)
      [path, [stat.dev, stat.ino, stat.uid, stat.gid, stat.mode, stat.nlink, stat.size,
              stat.mtime.to_i * 1_000_000_000 + stat.mtime.nsec,
              stat.ctime.to_i * 1_000_000_000 + stat.ctime.nsec]]
    end
    tools = {}
    receipt.fetch('tools').each { |path, digest| raise 'replay tool pin differs' unless Digest::SHA256.file(path).hexdigest == digest; tools[path] = digest }
    [source, nodes, tools, Digest::SHA256.file(receipt_path).hexdigest]
  end
  before = snapshot.call
  developer = receipt.fetch('invocation').fetch('developer_directory')
  environment = { 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME' => '/var/empty',
    'LC_ALL' => 'en_US.UTF-8', 'LANG' => 'en_US.UTF-8', 'DEVELOPER_DIR' => developer,
    'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_SYSTEM' => '/dev/null',
    'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_OPTIONAL_LOCKS' => '0', 'GIT_TERMINAL_PROMPT' => '0' }
  argv = ['/usr/bin/ruby', root + '/scripts/microphone-regression-gate.rb', '--verify-receipt', receipt_path, '--receipt-sha256', expected_digest]
  executor = OpensteamerMicrophoneReceiptBinding.const_get(:Executor).new
  output, status = executor.call(argv, environment, root, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 180, 65_536)
  raise 'actual UTF-8 receipt replay did not pass' unless status == 0 && output == OpensteamerMicrophoneReceiptBinding::MARKER + "\n"
  raise 'retained replay source/tool/input identity changed' unless snapshot.call == before
  puts 'ACTUAL_UTF8_RECEIPT_LOCALE_REPLAY_PASSED (locale proof only; no binding or deployment authority)'
end

class OpensteamerMicrophoneReceiptBindingTests < Minitest::Test
  SOURCE = File.join(__dir__, 'opensteamer-microphone-receipt-binding.rb').freeze
  RELATIVE = 'macOS/scripts/opensteamer-microphone-receipt-binding.rb'.freeze

  class FixtureVerifier
    attr_accessor :output, :status, :during
    attr_reader :calls
    def initialize(marker)
      @output = marker + "\n"; @status = 0; @calls = []
    end
    def call(argv, environment, root, deadline, maximum)
      @calls << [argv.dup, environment.dup, root, deadline, maximum]
      @during.call if @during
      [@output, @status]
    end
  end

  def setup
    @temporary = File.realpath(Dir.mktmpdir('opensteamer-receipt-binding-unit-'))
    @product = File.join(@temporary, 'product')
    @tooling = File.join(@temporary, 'tooling')
    [@product, @tooling].each { |root| Dir.mkdir(root, 0700) }
    copy = File.join(@tooling, RELATIVE)
    write(copy, File.binread(SOURCE))
    # Evaluate unchanged production bytes at their actual private fixture path.
    # No public root override or skipped source-location check is introduced.
    namespace = Module.new
    namespace.module_eval(File.read(copy), copy)
    @binding = namespace.const_get(:OpensteamerMicrophoneReceiptBinding)
    @verifiers = @binding::VERIFIERS.to_h do |relative|
      path = File.join(@product, relative)
      write(path, '# independently pinned fixture verifier source ' + relative)
      [relative, sha(path)]
    end
    @product_commit, @product_tree = commit_fixture(@product)
    @tooling_commit, @tooling_tree = commit_fixture(@tooling)
    @evidence = File.join(@temporary, 'evidence'); Dir.mkdir(@evidence, 0700)
    @receipt_path = File.join(@evidence, 'receipt.json')
    # The system Git dispatcher needs an installed developer directory. These
    # existing tools are read-only; only Git runs, exclusively on fixture repos.
    @developer = File.realpath('/Applications/Xcode-26.6.0.app/Contents/Developer')
    @xcode = @developer + '/usr/bin/xcodebuild'
    @tool = File.join(@temporary, 'fixture-tool')
    write(@tool, 'not executed fixture receipt tool', 0755)
    @receipt = { 'root' => @product, 'tools' => {
      '/usr/bin/ruby' => sha('/usr/bin/ruby'), @xcode => sha(@xcode), @tool => sha(@tool)
    }, 'created_at' => Time.now.to_i }
    write(@receipt_path, JSON.generate(@receipt), 0600)
    @request = {
      'callerUid' => Process.uid, 'productRoot' => @product, 'productCommit' => @product_commit,
      'productTree' => @product_tree, 'toolingRoot' => @tooling, 'toolingCommit' => @tooling_commit,
      'toolingTree' => @tooling_tree, 'receiptPath' => @receipt_path, 'receiptSha256' => sha(@receipt_path),
      'verifierSha256' => @verifiers, 'rubySha256' => sha('/usr/bin/ruby'), 'gitSha256' => sha('/usr/bin/git'),
      'developerDirectory' => @developer, 'developerGitSha256' => sha(@developer + '/usr/bin/git'),
      'xcodebuildSha256' => sha(@xcode), 'timeoutSeconds' => 30
    }
    @executor = FixtureVerifier.new(@binding::MARKER)
  end

  def teardown
    FileUtils.remove_entry_secure(@temporary) if @temporary && File.directory?(@temporary)
  end

  def write(path, bytes, mode = 0644)
    FileUtils.mkdir_p(File.dirname(path), mode: 0700)
    File.binwrite(path, bytes); File.chmod(mode, path)
  end

  def sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def git(root, *arguments)
    environment = { 'PATH' => '/usr/bin:/bin', 'HOME' => '/var/empty', 'GIT_CONFIG_NOSYSTEM' => '1',
                    'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_SYSTEM' => '/dev/null', 'GIT_OPTIONAL_LOCKS' => '0' }
    output, status = Open3.capture2e(environment, '/usr/bin/git', '-c', 'core.hooksPath=/dev/null', '-C', root, *arguments, unsetenv_others: true)
    raise 'private fixture Git setup failed' unless status.success?
    output
  end

  def commit_fixture(root)
    git(root, 'init', '--quiet')
    git(root, 'add', '--all')
    git(root, '-c', 'user.name=Offline Fixture', '-c', 'user.email=offline-fixture@example.invalid',
        '-c', 'commit.gpgsign=false', 'commit', '--quiet', '--no-verify', '-m', 'Offline fixture only')
    [git(root, 'rev-parse', 'HEAD').strip, git(root, 'rev-parse', 'HEAD^{tree}').strip]
  end

  def bind(request = @request, executor = @executor)
    @binding.send(:bind_with_executor, request, executor)
  end

  def refuses(message = nil)
    error = assert_raises(@binding::Refusal) { yield }
    assert_includes error.message, message if message
    error
  end

  def replace_same_bytes(path)
    stat = File.stat(path); bytes = File.binread(path)
    replacement = path + '.private-replacement'
    write(replacement, bytes, stat.mode & 0777)
    File.rename(replacement, path)
  end

  def test_positive_private_fixture_binds_two_clean_roots_without_authority
    record = bind
    assert_equal @product, record['inputs']['product']['path']
    assert_equal @tooling, record['inputs']['tooling']['path']
    assert_equal @product_commit, record['inputs']['product']['commit']
    assert_equal @tooling_tree, record['inputs']['tooling']['tree']
    assert_equal false, record['deploymentAuthority']
    assert_equal 'unprivileged-original-product-cli-source-preflight-only', record['scope']
    assert record.frozen?
    assert record['inputs']['receipt']['stat'].frozen?
    assert_raises(FrozenError) { record['request']['callerUid'] = 0 }
    assert_equal record, bind
    assert_equal record, @binding.send(:revalidate_with_executor, record, @request, @executor)
  end

  def test_actual_command_and_scrubbed_environment_are_fixed
    bind
    argv, environment, directory, _deadline, maximum = @executor.calls.fetch(0)
    assert_equal ['/usr/bin/ruby', @product + '/scripts/microphone-regression-gate.rb',
                  '--verify-receipt', @receipt_path, '--receipt-sha256', @request['receiptSha256']], argv
    assert_equal @product, directory
    assert_equal '/var/empty', environment['HOME']
    assert_equal '/usr/bin:/bin:/usr/sbin:/sbin', environment['PATH']
    assert_equal @developer, environment['DEVELOPER_DIR']
    assert_equal 'en_US.UTF-8', environment['LC_ALL']
    assert_equal 'en_US.UTF-8', environment['LANG']
    refute environment.key?('RUBYOPT')
    refute environment.key?('RUBYLIB')
    refute environment.key?('GIT_CONFIG_COUNT')
    assert_equal 65_536, maximum
  end

  def test_actual_executor_fixed_utf8_roundtrips_unicode_and_refuses_invalid_encodings
    bind
    environment = @executor.calls.fetch(0)[1]
    path = File.join(@evidence, 'unicode-log.json')
    write(path, JSON.generate('microphone' => "Beluga ✓ — PCM"), 0600)
    child = 'require "json"; text=File.read(ARGV.fetch(0)); raise "invalid encoded log" unless text.valid_encoding?; puts JSON.generate(JSON.parse(text))'
    executor = @binding.const_get(:Executor).new
    invoke = lambda do |env|
      executor.call(['/usr/bin/ruby', '-e', child, path], env, @product,
                    Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10, 65_536)
    end
    output, status = invoke.call(environment)
    assert_equal 0, status
    assert_equal({ 'microphone' => "Beluga ✓ — PCM" }, JSON.parse(output))
    _, status = invoke.call(environment.merge('LC_ALL' => 'C', 'LANG' => 'C'))
    refute_equal 0, status
    write(path, "{\"microphone\":\"\xff\"}".b, 0600)
    _, status = invoke.call(environment)
    refute_equal 0, status
  end

  def test_root_euid_root_and_caller_uid_mismatch_refuse_before_executor
    Process.stub(:uid, 0) { refuses('unelevated') { bind } }
    Process.stub(:euid, 0) { refuses('unelevated') { bind } }
    Process.stub(:euid, Process.uid + 1) { refuses('unelevated') { bind } }
    request = @request.merge('callerUid' => Process.uid + 1)
    refuses('caller UID') { bind(request) }
    assert_empty @executor.calls
  end

  def test_inherited_interpreter_git_and_loader_injection_refuse
    %w[RUBYOPT RUBYLIB GEM_HOME BUNDLE_GEMFILE GIT_CONFIG_COUNT GIT_EXEC_PATH DYLD_INSERT_LIBRARIES LD_PRELOAD].each do |key|
      saved = ENV[key]
      begin
        ENV[key] = 'untrusted-fixture-override'
        refuses('overrides') { bind }
      ensure
        saved.nil? ? ENV.delete(key) : ENV[key] = saved
      end
    end
    assert_empty @executor.calls
  end

  def test_no_public_executor_skip_or_test_mode
    assert_raises(ArgumentError) { @binding.bind(@request, executor: @executor) }
    refuses('field set') { bind(@request.merge('testMode' => true)) }
    refuses('field set') { bind(@request.merge('skipVerification' => true)) }
    refute @binding.respond_to?(:bind_with_executor)
    refute @binding.respond_to?(:revalidate_with_executor)
    refuses('usage') { @binding.main(['--skip-verification']) }
  end

  def test_missing_wrong_and_malformed_independent_pins_refuse
    %w[receiptSha256 rubySha256 gitSha256 developerGitSha256 xcodebuildSha256].each do |key|
      request = @request.dup; request.delete(key)
      refuses('field set') { bind(request) }
      refuses { bind(@request.merge(key => '0' * 64)) }
      refuses { bind(@request.merge(key => 'not-a-digest')) }
    end
    @binding::VERIFIERS.each do |relative|
      pins = @verifiers.dup; pins.delete(relative)
      refuses('field set') { bind(@request.merge('verifierSha256' => pins)) }
      pins = @verifiers.merge(relative => '0' * 64)
      refuses('pinned binding digest') { bind(@request.merge('verifierSha256' => pins)) }
    end
    assert_empty @executor.calls
  end

  def test_clean_independently_pinned_distinct_root_commit_tree_are_required
    %w[productCommit productTree toolingCommit toolingTree].each do |key|
      refuses('source commit or tree') { bind(@request.merge(key => '0' * 40)) }
    end
    refuses('equal or adapter root') { bind(@request.merge('productRoot' => @tooling)) }
    refuses('equal or adapter root') { bind(@request.merge('toolingRoot' => @product)) }
    write(File.join(@product, 'unrelated-uncommitted-feature.swift'), 'new feature')
    refuses('not clean') { bind }
    assert_empty @executor.calls
  end

  def test_tooling_dirt_and_untracked_or_hidden_adapter_cannot_bind
    write(File.join(@tooling, 'unrelated-change'), 'dirty tooling')
    refuses('not clean') { bind }
    File.unlink(File.join(@tooling, 'unrelated-change'))
    git(@tooling, 'update-index', '--assume-unchanged', RELATIVE)
    refuses('hidden or sparse') { bind }
  end

  def test_canonical_paths_symlinks_and_receipt_hardlinks_refuse
    alias_root = File.join(@temporary, 'product-alias'); File.symlink(@product, alias_root)
    refuses('not canonical') { bind(@request.merge('productRoot' => alias_root)) }
    alias_receipt = File.join(@evidence, 'alias.json'); File.symlink(@receipt_path, alias_receipt)
    refuses('not canonical') { bind(@request.merge('receiptPath' => alias_receipt)) }
    File.link(@receipt_path, File.join(@evidence, 'hardlink.json'))
    refuses('links') { bind }
  end

  def test_receipt_owner_mode_and_private_parent_are_mandatory
    File.chmod(0644, @receipt_path)
    refuses('permissions') { bind }
    File.chmod(0600, @receipt_path); File.chmod(0755, @evidence)
    refuses('permissions') { bind }
  end

  def test_receipt_dependency_root_fields_are_strict_and_bounded
    mutants = [@receipt.merge('root' => @tooling), @receipt.merge('tools' => nil),
               @receipt.merge('tools' => {}), @receipt.merge('tools' => { @tool => 'bad-hash' }),
               @receipt.merge('tools' => @receipt['tools'].reject { |path, _| path == '/usr/bin/ruby' })]
    mutants.each do |value|
      write(@receipt_path, JSON.generate(value), 0600)
      refuses { bind(@request.merge('receiptSha256' => sha(@receipt_path))) }
    end
    write(@receipt_path, '{"root":"first","root":"second","tools":{}}', 0600)
    refuses('redacted') { bind(@request.merge('receiptSha256' => sha(@receipt_path))) }
  end

  def test_fake_duplicate_partial_and_nonzero_success_markers_refuse
    outputs = [@binding::MARKER, @binding::MARKER + "\n" + @binding::MARKER + "\n",
               'fake PASS', '', @binding::MARKER + "\nextra output\n"]
    outputs.each { |output| @executor.output = output; refuses('sole successful marker') { bind } }
    @executor.output = @binding::MARKER + "\n"; @executor.status = 1
    refuses('sole successful marker') { bind }
  end

  def test_expiry_and_malformed_receipt_failures_are_delegated_to_actual_verifier
    @receipt['created_at'] = Time.now.to_i - 8 * 86_400
    write(@receipt_path, JSON.generate(@receipt), 0600)
    @executor.output = 'microphone-regressions: FAIL: future or expired receipt'; @executor.status = 1
    refuses('sole successful marker') { bind(@request.merge('receiptSha256' => sha(@receipt_path))) }
    assert_equal '--verify-receipt', @executor.calls.first[0][2]
    @executor.output = 'microphone-regressions: FAIL: malformed result'; @executor.status = 1
    refuses('sole successful marker') { bind(@request.merge('receiptSha256' => sha(@receipt_path))) }
  end

  def test_source_and_every_verifier_file_drift_during_verification_refuse
    paths = @binding::VERIFIERS.map { |relative| File.join(@product, relative) } + [File.join(@tooling, RELATIVE)]
    paths.each do |path|
      original = File.binread(path)
      @executor.during = lambda { File.binwrite(path, original + '\nmutation'); File.binwrite(path, original) }
      refuses('identity changed') { bind }
    end
  end

  def test_same_byte_helper_replacement_and_transient_mode_are_not_content_only
    path = File.join(@product, 'scripts/microphone-simulator-signing.rb')
    @executor.during = lambda { replace_same_bytes(path) }
    refuses('identity changed') { bind }
    @executor.during = lambda { File.chmod(0600, path); File.chmod(0644, path) }
    refuses('identity changed') { bind }
  end

  def test_receipt_content_same_bytes_file_and_parent_mode_replacements_refuse
    original = File.binread(@receipt_path)
    @executor.during = lambda { File.binwrite(@receipt_path, 'mutated'); File.binwrite(@receipt_path, original) }
    refuses('identity changed') { bind }
    @executor.during = lambda { replace_same_bytes(@receipt_path) }
    refuses('identity changed') { bind }
    @executor.during = lambda { File.chmod(0755, @evidence); File.chmod(0700, @evidence) }
    refuses('identity changed') { bind }
  end

  def test_declared_receipt_tool_bytes_inode_and_transient_mode_are_fenced
    original = File.binread(@tool)
    @executor.during = lambda { File.binwrite(@tool, 'replaced'); File.binwrite(@tool, original) }
    refuses('identity changed') { bind }
    @executor.during = lambda { replace_same_bytes(@tool) }
    refuses('identity changed') { bind }
    @executor.during = lambda { File.chmod(0644, @tool); File.chmod(0755, @tool) }
    refuses('identity changed') { bind }
  end

  def private_swift_alias
    source_git = @developer + '/usr/bin/git'
    @developer = @temporary + '/Developer'
    developer_git = @developer + '/usr/bin/git'
    write(developer_git, File.binread(source_git), 0755)
    old_xcode = @xcode; @xcode = @developer + '/usr/bin/xcodebuild'
    write(@xcode, 'private not-executed Xcode dependency fixture', 0755)
    target = @developer + '/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend'
    write(target, 'private not-executed Swift dependency fixture', 0755)
    path = File.dirname(target) + '/swift'; File.symlink('swift-frontend', path)
    @receipt['tools'].delete(old_xcode)
    @receipt['tools'][@xcode] = sha(@xcode); @receipt['tools'][path] = sha(target)
    write(@receipt_path, JSON.generate(@receipt), 0600)
    @request = @request.merge('developerDirectory' => @developer, 'developerGitSha256' => sha(developer_git),
                              'xcodebuildSha256' => sha(@xcode), 'receiptSha256' => sha(@receipt_path))
    [path, target]
  end

  def test_exact_swift_alias_keeps_declared_key_link_and_canonical_target
    path, target = private_swift_alias
    record = bind
    tool = record['inputs']['receiptTools'].fetch(path)
    assert_equal path, tool['path']
    assert_equal 'apple-swift-adjacent-alias.v1', tool['kind']
    assert_equal 'swift-frontend', tool['linkBytes']
    assert_equal File.lstat(path).ino, tool['linkStat']['inode']
    assert_equal sha(target), tool['sha256']
    assert_equal File.dirname(path), tool['parent']['path']
    assert_equal target, tool['target']['path']
    assert_equal sha(target), tool['target']['sha256']
    assert_equal File.stat(target).ino, tool['target']['stat']['inode']
    assert tool.frozen?
    refute record['deploymentAuthority']
    assert_equal record, @binding.send(:revalidate_with_executor, record, @request, @executor)
    refuses('not canonical') { @binding.send(:file_record, path, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10) }
  end

  def test_swift_alias_retargets_chains_and_unsafe_target_are_refused
    path, target = private_swift_alias
    adjacent = File.dirname(path) + '/other-tool'; write(adjacent, File.binread(target), 0755)
    ['other-tool', target, '../bin/swift-frontend', 'swift'].each do |link|
      File.unlink(path); File.symlink(link, path)
      refuses('alias') { bind }
    end
    File.unlink(path); File.symlink('swift-frontend', path)
    File.unlink(target); File.symlink('other-tool', target)
    refuses('canonical and adjacent') { bind }
    File.unlink(target); write(target, 'private not-executed Swift dependency fixture', 0775)
    refuses('permissions') { bind }
    File.chmod(0755, target); File.chmod(0775, File.dirname(path))
    refuses('directory') { bind }
    assert_empty @executor.calls
  end

  def test_swift_alias_missing_nonexecutable_wrong_digest_and_target_hardlink_refuse
    path, target = private_swift_alias
    @receipt['tools'][path] = '0' * 64; write(@receipt_path, JSON.generate(@receipt), 0600)
    refuses('pinned binding digest') { bind(@request.merge('receiptSha256' => sha(@receipt_path))) }
    @receipt['tools'][path] = sha(target); write(@receipt_path, JSON.generate(@receipt), 0600)
    @request['receiptSha256'] = sha(@receipt_path)
    File.chmod(0644, target)
    refuses('permissions') { bind }
    File.chmod(0755, target); File.link(target, target + '.hardlink')
    refuses('links') { bind }
    File.unlink(target + '.hardlink'); File.unlink(target)
    refuses('missing') { bind }
    assert_empty @executor.calls
  end

  def test_receipt_alias_exception_does_not_accept_other_declared_tool_aliases
    path = @temporary + '/other-tool-alias'; File.symlink('fixture-tool', path)
    @receipt['tools'][path] = sha(@tool); write(@receipt_path, JSON.generate(@receipt), 0600)
    refuses('reviewed Apple Swift path') { bind(@request.merge('receiptSha256' => sha(@receipt_path))) }
    assert_empty @executor.calls
  end

  def test_swift_alias_link_and_target_drift_during_verification_are_fenced
    path, target = private_swift_alias
    replacement = File.dirname(path) + '/other-tool'; write(replacement, File.binread(target), 0755)
    original = File.binread(target)
    mutations = [
      lambda { File.unlink(path); File.symlink('other-tool', path) },
      lambda { File.unlink(path); File.symlink('other-tool', path); File.unlink(path); File.symlink('swift-frontend', path) },
      lambda { copy = path + '.replacement'; File.symlink('swift-frontend', copy); File.rename(copy, path) },
      lambda { File.binwrite(target, 'changed'); File.binwrite(target, original) },
      lambda { replace_same_bytes(target) },
      lambda { File.chmod(0644, target); File.chmod(0755, target) }
    ]
    mutations.each do |mutation|
      File.unlink(path); File.symlink('swift-frontend', path)
      @executor.during = mutation
      refuses { bind }
    end
  end

  def test_swift_alias_parent_mode_restore_and_directory_replacement_are_fenced
    path, target = private_swift_alias
    parent = File.dirname(path)
    @executor.during = lambda { File.chmod(0750, parent); File.chmod(0700, parent) }
    refuses('identity changed') { bind }
    @executor.during = lambda do
      held = parent + '.held'
      File.rename(parent, held); Dir.mkdir(parent, 0700)
      File.rename(held + '/swift', path); File.rename(held + '/swift-frontend', target)
    end
    refuses('identity changed') { bind }
  end

  def test_receipt_git_commit_and_new_feature_drift_during_verification_refuse
    @executor.during = lambda { write(File.join(@product, 'late-source.swift'), 'late feature') }
    refuses('not clean') { bind }
    File.unlink(File.join(@product, 'late-source.swift'))
    @executor.during = lambda do
      git(@tooling, '-c', 'user.name=Offline Fixture', '-c', 'user.email=offline-fixture@example.invalid',
          '-c', 'commit.gpgsign=false', 'commit', '--quiet', '--allow-empty', '--no-verify', '-m', 'changed fixture HEAD')
    end
    refuses('source commit or tree') { bind }
  end

  def test_current_uid_cannot_change_during_verifier
    @executor.during = lambda { Process.stub(:euid, 0) { @binding.send(:unprivileged!) } }
    refuses('unelevated') { bind }
  end

  def test_binding_record_is_exactly_revalidated_not_a_pass_string
    record = bind
    wrong = JSON.parse(JSON.generate(record)); wrong['deploymentAuthority'] = true
    refuses('record no longer matches') { @binding.send(:revalidate_with_executor, wrong, @request, @executor) }
    write(@tool, 'changed declared dependency', 0755)
    refuses('pinned binding digest') { @binding.send(:revalidate_with_executor, record, @request, @executor) }
  end

  def test_deadline_and_output_bounds_are_enforced_independent_of_executor
    @executor.output = 'x' * (@binding::MAX_OUTPUT + 1)
    refuses('sole successful marker') { bind }
    @executor.output = @binding::MARKER + "\n"
    @executor.during = lambda { sleep 1.05 }
    refuses('deadline') { bind(@request.merge('timeoutSeconds' => 1)) }
    [0, 181, 1.0, '30'].each { |value| refuses('deadline') { bind(@request.merge('timeoutSeconds' => value)) } }
  end

  def test_real_bounded_executor_refuses_deadline_and_excess_output
    executor = @binding.const_get(:Executor).new
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.1
    refuses('deadline') { executor.call(['/usr/bin/ruby', '-e', 'sleep 2'], {}, @temporary, deadline, 1024) }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    refuses('output exceeded') { executor.call(['/usr/bin/ruby', '-e', 'print "x" * 4096'], {}, @temporary, deadline, 1024) }
  end

  def test_sensitive_malformed_input_and_parser_causes_are_redacted
    secret_like = 'secret-like-unit-fixture-never-print'
    error = refuses('redacted') { @binding.send(:parse_json, '{"key":"' + secret_like + '",') }
    refute_includes error.full_message, secret_like
    assert_nil error.cause
    malformed = @request.merge('receiptSha256' => secret_like)
    error = refuses { bind(malformed) }
    refute_includes error.full_message, secret_like
    refuses { @binding.send(:parse_json, ' ' * (@binding::MAX_JSON + 1)) }
  end
end
