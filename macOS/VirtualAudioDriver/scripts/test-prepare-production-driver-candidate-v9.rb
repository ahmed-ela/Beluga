# Offline primitive/refusal fixtures only, never successful release preparation.
# The private revalidation fixture substitutes a CLI record producer and the
# Git/tool closure branch; the real byte/stat and comparison functions still run.
require 'digest'
require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'tmpdir'

class ProductionDriverCandidateV9Tests < Minitest::Test
  SCRIPT = File.realpath(File.join(__dir__, 'prepare-production-driver-candidate-v9.sh')).freeze
  TEXT = File.binread(SCRIPT).freeze
  MAIN = "\n(( $# == 6 )) || usage\n".freeze
  PREFIX = TEXT.split(MAIN, 2).first.freeze
  RUNNER = TEXT[/^build_root=""\nbuild_root_identity=""\ncandidate_run\(\) \{\n.*?^\}\n/m].freeze
  ENVIRONMENT = { 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME' => '/var/empty', 'LC_ALL' => 'C' }.freeze

  def setup
    @scratch = File.realpath(Dir.mktmpdir('beluga-candidate-v9-test-', '/private/tmp'))
    File.chmod(0700, @scratch)
    @request = @scratch + '/request.json'
    File.binwrite(@request, '{}'); File.chmod(0600, @request)
    @output = @scratch + '/production-driver-v9'
  end

  def teardown
    FileUtils.remove_entry_secure(@scratch) if @scratch && File.directory?(@scratch)
  end

  def command(arguments, environment = {})
    output, error, status = Open3.capture3(ENVIRONMENT.merge(environment), *arguments,
                                         chdir: @scratch, unsetenv_others: true)
    assert_operator output.bytesize + error.bytesize, :<, 65_536
    [output, error, status]
  end

  def cli(extra = [], environment = {})
    before = Dir.glob('/private/tmp/opensteamer-production-driver-v9.*').sort
    result = command(['/bin/zsh', '-f', SCRIPT] + extra, environment)
    assert_equal before, Dir.glob('/private/tmp/opensteamer-production-driver-v9.*').sort
    refute File.exist?(@output)
    assert_empty Dir.glob(@scratch + '/.production-driver-v9.stage.*')
    result
  end

  def arguments(path = @request, digest = Digest::SHA256.file(@request).hexdigest)
    [@output, 'A' * 40, 'B' * 40, 'offline-fixture-never-looked-up', path, digest]
  end

  def functions(body, *values, environment: {})
    source = PREFIX + "\n" + RUNNER + "\nscript_path=#{Shellwords.escape(SCRIPT)}\n" + body
    command(['/bin/zsh', '-f', '-c', source, 'offline-functions'] + values, environment)
  end

  def test_actual_cli_requires_six_arguments_and_has_no_public_skip
    [arguments.first(4), ['--self-test-candidate-publication-v9'], ['--skip-receipt']].each do |args|
      _, error, status = cli(args)
      assert_equal 64, status.exitstatus
      assert_includes error, 'usage:'
    end
  end

  def test_actual_cli_missing_and_wrong_independent_request_digest
    [arguments(@request + '.missing', '0' * 64), arguments(@request, '0' * 64)].each do |args|
      _, error, status = cli(args)
      assert_equal 65, status.exitstatus
      assert_includes error, 'candidate entry input identity refused'
      refute_includes error, 'Developer ID'
    end
  end

  def test_actual_cli_calls_real_adapter_and_refuses_incomplete_request
    _, error, status = cli(arguments)
    assert_equal 65, status.exitstatus
    assert_includes error, 'microphone receipt binding refused'
    assert_includes error, 'mandatory microphone receipt binding refused'
  end

  def test_actual_cli_refuses_malformed_digest_before_adapter
    _, error, status = cli(arguments(@request, 'not-a-digest'))
    assert_equal 65, status.exitstatus
    assert_includes error, 'independent SHA-256 is malformed'
  end

  def test_actual_direct_cli_shebang_disables_inherited_zsh_startup
    marker = @scratch + '/unexpected-zsh-startup'
    File.binwrite(@scratch + '/.zshenv', "printf bad > #{Shellwords.escape(marker)}\n")
    _, error, status = command([SCRIPT] + arguments(@request, 'not-a-digest'), 'ZDOTDIR' => @scratch)
    assert_equal 65, status.exitstatus
    assert_includes error, 'independent SHA-256 is malformed'
    refute File.exist?(marker)
    refute File.exist?(@output)
    assert_empty Dir.glob(@scratch + '/.production-driver-v9.stage.*')
  end

  def test_actual_cli_rejects_interpreter_loader_git_and_python_environment
    %w[RUBYOPT RUBYLIB GIT_CONFIG_GLOBAL PYTHONPATH PYTHONHOME].each do |key|
      _, error, status = cli(arguments, key => 'offline-secret-never-loaded')
      assert_equal 65, status.exitstatus
      assert_includes error, 'overrides are forbidden'
      refute_includes error, 'offline-secret'
    end
  end

  def test_actual_entry_guard_rejects_loader_override_in_same_process
    # SIP strips DYLD_* from system-zsh startup; set it after startup to exercise
    # the exact production entry guard without relying on that separate defense.
    entry = TEXT.split(MAIN, 2).last.split('export PATH=', 2).first
    body = "set -- #{arguments.map { |value| Shellwords.escape(value) }.join(' ')}\nexport DYLD_INSERT_LIBRARIES=offline-fixture\n" + entry
    _, error, status = functions(body)
    assert_equal 65, status.exitstatus
    assert_includes error, 'overrides are forbidden'
  end

  def test_actual_cli_refuses_line_control_path
    path = @scratch + "/request\nmutant.json"
    File.binwrite(path, '{}'); File.chmod(0600, path)
    _, error, status = cli(arguments(path, Digest::SHA256.file(path).hexdigest))
    assert_equal 65, status.exitstatus
    assert_includes error, 'candidate entry input identity refused'
  end

  def test_actual_atomic_publication_and_collision_symlink_identity_mutants
    output, error, status = functions('publication_self_test')
    assert status.success?, error
    assert_includes output, 'PASS atomic no-clobber candidate publication rejected collision, symlink, and identity mutants'
  end

  def test_actual_file_fingerprint_has_digest_stat_and_request_parent
    output, error, status = functions('candidate_input_identity files "$1" "$2" "$3" directory0700',
                                      @request, Digest::SHA256.file(@request).hexdigest, @scratch)
    assert status.success?, error
    value = JSON.parse(output)
    assert_equal Digest::SHA256.file(@request).hexdigest, value[0]['sha256']
    assert_equal File.stat(@request).ino, value[0]['stat'][1]
    assert_equal 1, value[0]['stat'][5]
    assert_equal File.stat(@scratch).ino, value[1]['stat'][1]
  end

  def test_actual_fingerprint_refuses_missing_digest_symlink_and_hardlink
    link = @scratch + '/symlink'; File.symlink(@request, link)
    hardlink = @scratch + '/hardlink'; File.link(@request, hardlink)
    [[@request + '.missing', ''], [@request, '0' * 64], [link, ''], [@request, '']].each do |path, digest|
      _, error, status = functions('candidate_input_identity files "$1" "$2"', path, digest)
      assert_equal 65, status.exitstatus
      assert_includes error, 'identity refused'
    end
  end

  def test_actual_fingerprint_detects_content_restore_mode_restore_and_same_byte_replacement
    mutations = [
      'print -rn -- changed >"$1"; print -rn -- "{}" >"$1"',
      '/bin/chmod 0400 "$1"; /bin/chmod 0600 "$1"',
      'print -rn -- "{}" >"$1.replacement"; /bin/chmod 0600 "$1.replacement"; /bin/mv "$1.replacement" "$1"'
    ]
    mutations.each do |mutation|
      body = 'baseline="$(candidate_input_identity files "$1" "")" || exit 90' + "\n" + mutation +
             '\n[[ "$(candidate_input_identity files "$1" "")" != "$baseline" ]] || exit 91'.gsub('\\n', "\n")
      _, error, status = functions(body, @request)
      assert status.success?, error
    end
  end

  def test_actual_tree_fingerprint_detects_empty_directory_and_mode_changes
    tree = @scratch + '/stage'; Dir.mkdir(tree, 0700)
    File.binwrite(tree + '/payload', 'artifact'); File.chmod(0400, tree + '/payload')
    ['mkdir "$1/extra-empty"', '/bin/chmod 0600 "$1/payload"'].each do |mutation|
      body = 'baseline="$(candidate_input_identity tree "$1")" || exit 90' + "\n" + mutation +
             '\n[[ "$(candidate_input_identity tree "$1")" != "$baseline" ]] || exit 91'.gsub('\\n', "\n")
      _, error, status = functions(body, tree)
      assert status.success?, error
    end
  end

  def fixture_tree(root, paths)
    paths.each do |relative, (bytes, mode)|
      path = root + '/' + relative
      FileUtils.mkdir_p(File.dirname(path), mode: 0700)
      File.binwrite(path, bytes); File.chmod(mode, path)
    end
    prefix = ['/usr/bin/git', '-c', 'core.hooksPath=/dev/null', '-C', root]
    [%w[init --quiet], %w[add --all], ['-c', 'user.name=Offline Fixture', '-c', 'user.email=offline-fixture@example.invalid',
                                    '-c', 'commit.gpgsign=false', 'commit', '--quiet', '--no-verify', '-m', 'Offline closure fixture']].each do |argv|
      _, error, status = command(prefix + argv)
      assert status.success?, error
    end
    output, error, status = command(prefix + ['rev-parse', 'HEAD^{tree}'])
    assert status.success?, error
    output.chomp
  end

  def test_actual_complete_closure_pins_mixed_regular_and_alias_receipt_tools
    product = @scratch + '/closure-product'; tooling = @scratch + '/closure-tooling'
    [product, tooling].each { |path| Dir.mkdir(path, 0700) }
    leaves = %w[scripts/build-driver.sh scripts/verify-driver-bundle.sh Driver/Info.plist Driver/OpensteamerVirtualMicrophone.c
                src/OpensteamerVirtualAudioCore.c Driver/OpensteamerVirtualMicrophone.exports APPLE_SAMPLE_LICENSE.txt
                Resources/en.lproj/Localizable.strings include/Fixture.h]
    product_tree = fixture_tree(product, leaves.to_h { |leaf| ['macOS/VirtualAudioDriver/' + leaf, ['private build-source fixture', 0644]] })
    relative = 'macOS/VirtualAudioDriver/scripts/'
    tooling_files = %w[prepare-production-driver-candidate-v9.sh verify-production-driver-package-v9.sh beluga-production-driver-plist.py parse-installer-signature-v8.sh]
      .to_h { |leaf| [relative + leaf, [File.binread(__dir__ + '/' + leaf), File.stat(__dir__ + '/' + leaf).mode & 0777]] }
    adapter = 'macOS/scripts/opensteamer-microphone-receipt-binding.rb'
    tooling_files[adapter] = [File.binread(__dir__ + '/../../scripts/opensteamer-microphone-receipt-binding.rb'), 0644]
    tooling_tree = fixture_tree(tooling, tooling_files)
    regular = @scratch + '/regular-tool'; target = @scratch + '/swift-frontend'; alias_path = @scratch + '/swift'
    [regular, target].each { |path| File.binwrite(path, 'not executed fixture tool'); File.chmod(0755, path) }
    File.symlink('swift-frontend', alias_path)
    developer = File.realpath('/Applications/Xcode-26.6.0.app/Contents/Developer')
    record = { 'request' => { 'productRoot' => product, 'productTree' => product_tree, 'toolingRoot' => tooling,
                              'toolingTree' => tooling_tree, 'developerDirectory' => developer },
               'inputs' => { 'developerGit' => { 'path' => developer + '/usr/bin/git' }, 'receiptTools' =>
                 [regular, alias_path].to_h { |path| [path, { 'path' => path, 'sha256' => Digest::SHA256.file(path).hexdigest }] } } }
    fixture = @scratch + '/closure-record.json'; File.binwrite(fixture, JSON.generate(record))
    # This executes the unchanged whole closure branch. xcrun resolves paths only;
    # no compiler, signer, notary, builder or release preparation is executed.
    output, error, status = functions('candidate_input_identity closure <"$1"', fixture)
    assert status.success?, error
    tools = JSON.parse(output).fetch('tools')
    assert_equal regular, tools.fetch(regular).fetch('canonical')
    assert_equal target, tools.fetch(alias_path).fetch('canonical')
    assert_equal File.lstat(alias_path).ino, tools.fetch(alias_path).fetch('stat')[1]
    assert_equal File.stat(target).ino, tools.fetch(alias_path).fetch('targetStat')[1]
    assert_equal Digest::SHA256.file(target).hexdigest, tools.fetch(alias_path).fetch('sha256')
  end

  def test_actual_clean_runner_pins_cwd_and_blocks_json_shadow_bash_env_and_zsh_startup
    product = @scratch + '/bound-product'; Dir.mkdir(product, 0700)
    build = @scratch + '/private-build'; Dir.mkdir(build, 0700)
    marker = @scratch + '/unexpected-import-or-startup'
    File.binwrite(@scratch + '/json.py', "open(#{marker.inspect}, 'w').write('shadow'); raise RuntimeError('shadow imported')")
    startup = @scratch + '/bash-startup'
    File.binwrite(startup, "printf bad > #{Shellwords.escape(marker)}\n")
    File.binwrite(@scratch + '/.zshenv', "printf bad > #{Shellwords.escape(marker)}\n")
    worker = @scratch + '/offline-zsh-worker'
    File.binwrite(worker, "#!/bin/zsh\nexec /bin/bash -c 'exec /usr/bin/python3 -c \"$1\"' offline-worker \"$1\"\n")
    File.chmod(0700, worker)
    code = 'import json,os; print(json.dumps({"cwd":os.getcwd(),"environment":dict(os.environ)}))'
    body = <<~SH
      repo="$1"; candidate_home="$6"; developer_dir="$7"
      if [[ "$3" == build ]]; then
          build_root="$2"
          build_root_identity="$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$build_root")"
      fi
      candidate_run "$5" "$4"
    SH
    %w[product build].each do |phase|
      output, error, status = functions(body, product, build, phase, code, worker, @scratch,
                                        '/Applications/Xcode-26.6.0.app/Contents/Developer',
                                        environment: { 'BASH_ENV' => startup, 'ZDOTDIR' => @scratch,
                                                       'build_root' => @scratch,
                                                       'build_root_identity' => [File.stat(@scratch).dev, File.stat(@scratch).ino,
                                                                                 Process.uid, '700'].join(':') })
      assert status.success?, error
      result = JSON.parse(output)
      assert_equal phase == 'build' ? build : product, result['cwd']
      assert_equal 'en_US.UTF-8', result['environment']['LC_ALL']
      assert_equal 'en_US.UTF-8', result['environment']['LANG']
      assert_equal @scratch, result['environment']['HOME']
      assert_equal '/var/empty', result['environment']['ZDOTDIR']
      refute result['environment'].key?('BASH_ENV')
      refute File.exist?(marker)
    end
  end

  def revalidation_fixture(change)
    adapter = @scratch + '/fixture-record-cli.rb'
    record = @scratch + '/fixture-record.json'; File.binwrite(record, '{"fixture":true}')
    # Fixed production Ruby CLI is exercised, but this private fixture is not
    # the real receipt adapter and cannot claim receipt acceptance.
    File.binwrite(adapter, 'exit 1 unless ARGV[0] == "--request" && ARGV[2] == "--request-sha256"; puts File.binread(ARGV[1])')
    File.chmod(0600, adapter)
    body = <<~SH
      binding_adapter="$1"; binding_request="$2"; binding_request_sha256=fixture
      entry_boundary_files=("$2" "")
      entry_boundary="$(candidate_input_identity files "${entry_boundary_files[@]}")" || exit 90
      binding_record="$(invoke_receipt_binding)" || exit 91
      functions[_fixture_actual_identity]=$functions[candidate_input_identity]
      candidate_input_identity() {
          if [[ "$1" == closure ]]; then
              _fixture_actual_identity files "$binding_request" ""
          else
              _fixture_actual_identity "$@"
          fi
      }
      candidate_closure="$(candidate_input_identity closure)" || exit 92
      #{change}
      revalidate_candidate_inputs
    SH
    functions(body, adapter, record)
  end

  def test_actual_revalidation_comparison_accepts_only_unchanged_private_fixture
    _, error, status = revalidation_fixture(':')
    assert status.success?, error
    _, error, status = revalidation_fixture('print -rn -- "{\\\"fixture\\\":false}" >"$binding_request"')
    assert_equal 65, status.exitstatus
    assert_includes error, 'entry input identity changed'
    _, error, status = revalidation_fixture('binding_record=wrong')
    assert_equal 65, status.exitstatus
    assert_includes error, 'receipt binding changed'
    _, error, status = revalidation_fixture('print -rn -- "exit 1" >"$binding_adapter"')
    assert_equal 65, status.exitstatus
    assert_includes error, 'mandatory microphone receipt binding refused'
  end
end
