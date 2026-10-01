# Unprivileged original-product-CLI source preflight only. This record grants no
# build, signing, installation, migration, rollback, or deployment authority.
require 'digest'
require 'json'
require 'set'

module OpensteamerMicrophoneReceiptBinding
  class Refusal < StandardError; end
  class DuplicateKey < StandardError; end
  class UniqueObject < Hash
    def []=(key, value)
      raise FrozenError, 'binding object is immutable' if frozen?
      raise DuplicateKey, 'duplicate JSON member' if key?(key)
      super
    end
  end

  ADAPTER_PATH = File.realpath(__FILE__).freeze
  ADAPTER_RELATIVE = 'macOS/scripts/opensteamer-microphone-receipt-binding.rb'.freeze
  RUBY = '/usr/bin/ruby'.freeze
  GIT = '/usr/bin/git'.freeze
  VERIFIERS = %w[scripts/validate-microphone-regressions.sh scripts/microphone-regression-gate.rb scripts/microphone-simulator-signing.rb].freeze
  MARKER = 'microphone-regressions: receipt verified for current source and tools (offline source evidence only)'.freeze
  SCHEMA = 'opensteamer.microphone-receipt-binding.unprivileged.v1'.freeze
  SCOPE = 'unprivileged-original-product-cli-source-preflight-only'.freeze
  REQUEST_KEYS = %w[callerUid productRoot productCommit productTree toolingRoot toolingCommit toolingTree receiptPath receiptSha256 verifierSha256 rubySha256 gitSha256 developerDirectory developerGitSha256 xcodebuildSha256 timeoutSeconds].freeze
  MAX_JSON = 8 * 1024 * 1024
  MAX_TOOLS = 64
  MAX_TOOL_BYTES = 1024 * 1024 * 1024
  MAX_OUTPUT = 65_536
  MAX_GIT_OUTPUT = 8 * 1024 * 1024

  def self.require!(condition, message)
    raise Refusal, message, cause: nil unless condition
  end

  def self.keys!(value, keys)
    require!(value.is_a?(Hash) && value.keys.sort == keys.sort, 'binding field set is missing or unrecognized')
  end

  def self.sha?(value)
    value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
  end

  def self.parse_json(text)
    require!(text.is_a?(String) && text.bytesize <= MAX_JSON, 'binding JSON exceeds its bound')
    text = text.dup.force_encoding(Encoding::UTF_8)
    require!(text.valid_encoding?, 'binding JSON encoding is invalid')
    JSON.parse(text, object_class: UniqueObject, max_nesting: 16, allow_nan: false, create_additions: false)
  rescue JSON::ParserError, JSON::NestingError, DuplicateKey
    raise Refusal, 'binding JSON is malformed (contents redacted)', cause: nil
  end

  def self.deep_freeze(value)
    value.each { |key, item| key.freeze; deep_freeze(item) } if value.is_a?(Hash)
    value.each { |item| deep_freeze(item) } if value.is_a?(Array)
    value.freeze
  end

  def self.unprivileged!
    require!(Process.uid != 0 && Process.euid != 0 && Process.uid == Process.euid,
             'binding requires an unelevated original caller UID')
    require!(ENV.keys.none? { |key| key.match?(/\A(?:RUBY|GEM_|BUNDLE_|GIT_|DYLD_|LD_PRELOAD\z|LD_LIBRARY_PATH\z)/) },
             'inherited interpreter, loader or Git overrides are forbidden')
  end

  def self.stat_record(stat)
    { 'device' => stat.dev, 'inode' => stat.ino, 'uid' => stat.uid, 'gid' => stat.gid,
      'mode' => stat.mode, 'links' => stat.nlink, 'size' => stat.size,
      'mtimeNs' => stat.mtime.to_i * 1_000_000_000 + stat.mtime.nsec,
      'ctimeNs' => stat.ctime.to_i * 1_000_000_000 + stat.ctime.nsec }
  end

  def self.canonical!(path)
    require!(path.is_a?(String) && path.start_with?('/') && !path.include?("\0") && File.realpath(path) == path,
             'binding input path is not canonical')
  end

  def self.time_left!(deadline)
    left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    require!(left > 0, 'binding verification exceeded its deadline')
    left
  end

  def self.directory_record(path, owner: nil, mode: nil)
    canonical!(path)
    stat = File.lstat(path)
    require!(stat.directory? && !stat.symlink? && (stat.mode & 0022) == 0 &&
             (!owner || stat.uid == owner) && (!mode || stat.mode & 0777 == mode),
             'binding directory identity or permissions are unsafe')
    { 'path' => path, 'stat' => stat_record(stat) }
  end

  # Opened-file and terminal path fences include ctime/inode, not only bytes.
  # Thus same-byte replacement and transient mode/content restoration invalidate.
  def self.file_record(path, deadline, expected: nil, owner: nil, mode: nil, executable: false, maximum: MAX_TOOL_BYTES, retain: false, single_link: true)
    time_left!(deadline); canonical!(path)
    before = File.lstat(path)
    require!(before.file? && !before.symlink? && before.nlink > 0 && (!single_link || before.nlink == 1) && before.size.between?(1, maximum) &&
             (before.mode & 0022) == 0 && (!owner || before.uid == owner) && (!mode || before.mode & 0777 == mode) &&
             (!executable || (before.mode & 0111) != 0), 'binding file identity, links, size or permissions are unsafe')
    digest = Digest::SHA256.new; bytes = retain ? ''.b : nil; count = 0
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      require!(stat_record(file.stat) == stat_record(before), 'binding input changed while opening')
      while (chunk = file.read(65_536))
        time_left!(deadline); count += chunk.bytesize
        require!(count <= maximum, 'binding file exceeds its bound')
        digest.update(chunk); bytes << chunk if bytes
      end
      require!(stat_record(file.stat) == stat_record(before), 'binding input changed while reading')
    end
    canonical!(path)
    require!(stat_record(File.lstat(path)) == stat_record(before), 'binding input path identity changed')
    require!(!expected || digest.hexdigest == expected, 'independently pinned binding digest differs')
    record = { 'path' => path, 'sha256' => digest.hexdigest, 'stat' => stat_record(before) }
    retain ? [record, bytes] : record
  end

  # The receipt names Apple's Swift dispatch alias, not only its canonical tool.
  # No other symlink or chain is admitted at this dependency-only boundary.
  def self.receipt_tool_record(path, deadline, expected:, developer:)
    time_left!(deadline)
    require!(path.is_a?(String) && path.start_with?('/') && !path.include?("\0"), 'binding receipt tool path is malformed')
    before = File.lstat(path)
    return file_record(path, deadline, expected: expected, executable: true, single_link: false) unless before.symlink?
    require!(path == developer + '/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift', 'binding receipt tool alias is not the reviewed Apple Swift path')
    parent = directory_record(File.dirname(path))
    link = File.readlink(path)
    require!(before.nlink == 1 && (before.mode & 0022) == 0 && link == 'swift-frontend' && before.size == link.bytesize,
             'binding receipt tool alias identity or target is unsafe')
    target_path = File.dirname(path) + '/swift-frontend'
    require!(File.realpath(path) == target_path, 'binding receipt tool alias target is not canonical and adjacent')
    target = file_record(target_path, deadline, expected: expected, executable: true)
    require!(stat_record(File.lstat(path)) == stat_record(before) && File.readlink(path) == link &&
             File.realpath(path) == target_path && directory_record(parent['path']) == parent,
             'binding receipt tool alias changed while reading')
    { 'path' => path, 'sha256' => target['sha256'], 'kind' => 'apple-swift-adjacent-alias.v1',
      'linkBytes' => link, 'linkStat' => stat_record(before), 'parent' => parent, 'target' => target }
  end

  class Executor
    def call(argv, environment, directory, deadline, maximum)
      reader, writer = IO.pipe
      pid = Process.spawn(environment, *argv, chdir: directory, in: File::NULL,
                          out: writer, err: writer, pgroup: true, unsetenv_others: true)
      group = pid; writer.close; output = ''.b; status = nil; eof = false
      until eof && status
        left = OpensteamerMicrophoneReceiptBinding.send(:time_left!, deadline)
        ready = IO.select([reader], nil, nil, [left, 0.05].min) unless eof
        if ready
          chunk = reader.read_nonblock(4096, exception: false)
          if chunk.nil? then eof = true
          elsif chunk != :wait_readable
            output << chunk
            OpensteamerMicrophoneReceiptBinding.send(:require!, output.bytesize <= maximum, 'binding verifier output exceeded its bound')
          end
        end
        unless status
          result = Process.waitpid2(pid, Process::WNOHANG)
          status = result[1] if result
        end
        sleep([left, 0.01].min) if eof && !status
      end
      [output, status.exitstatus]
    ensure
      writer.close if writer && !writer.closed?
      reader.close if reader && !reader.closed?
      if group && (!status || !status.success?)
        %w[TERM KILL].each do |signal|
          begin
            Process.kill(signal, -group)
          rescue Errno::ESRCH
          rescue Errno::EPERM
            # Darwin may retain only this exited group leader's zombie. Admit
            # that case only after reaping the exact child owned by this call.
            reaped = Process.waitpid2(pid, Process::WNOHANG) unless status
            raise unless reaped && reaped[0] == pid
            status = reaped[1]
            break
          end
        end
      end
      if pid && !status
        begin
          Process.waitpid(pid)
        rescue Errno::ECHILD
        end
      end
    end
  end
  private_constant :Executor

  def self.environment(developer)
    { 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME' => '/var/empty',
      'LC_ALL' => 'en_US.UTF-8', 'LANG' => 'en_US.UTF-8', 'DEVELOPER_DIR' => developer,
      'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_SYSTEM' => '/dev/null',
      'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_OPTIONAL_LOCKS' => '0', 'GIT_TERMINAL_PROMPT' => '0' }
  end

  def self.git(root, arguments, environment, deadline)
    argv = [environment.fetch('DEVELOPER_DIR') + '/usr/bin/git', '--no-optional-locks', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null',
            '-c', 'core.untrackedCache=false', '-c', 'core.ignoreStat=false', '-C', root] + arguments
    output, status = Executor.new.call(argv, environment, root, deadline, MAX_GIT_OUTPUT)
    require!(status == 0, 'binding Git identity check failed')
    output
  end

  def self.git_record(root, commit, tree, tracked, environment, deadline)
    directory = directory_record(root, owner: Process.uid)
    require!(git(root, %w[rev-parse --show-toplevel], environment, deadline) == root + "\n", 'binding root is not the exact Git top level')
    require!(git(root, %w[rev-parse HEAD], environment, deadline) == commit + "\n" &&
             git(root, ['rev-parse', 'HEAD^{tree}'], environment, deadline) == tree + "\n", 'independently pinned source commit or tree differs')
    require!(git(root, %w[status --porcelain=v1 --untracked-files=all], environment, deadline).empty?, 'binding source root is not clean')
    flags = git(root, %w[ls-files -v -z], environment, deadline).split("\0")
    require!(!flags.empty? && flags.all? { |entry| entry.start_with?('H ') }, 'binding source uses hidden or sparse index flags')
    observed = git(root, ['ls-files', '--error-unmatch', '--'] + tracked, environment, deadline).lines.map(&:chomp).sort
    require!(observed == tracked.sort, 'binding helper is not tracked in the pinned source tree')
    directory.merge('commit' => commit, 'tree' => tree)
  end

  def self.validate_request(request)
    keys!(request, REQUEST_KEYS)
    require!(request['callerUid'].is_a?(Integer) && request['callerUid'] > 0 &&
             request['callerUid'] == Process.uid && request['callerUid'] == Process.euid, 'binding caller UID differs')
    %w[productCommit productTree toolingCommit toolingTree].each do |key|
      require!(request[key].is_a?(String) && request[key].match?(/\A[0-9a-f]{40}\z/), 'binding requires independent exact source commit and tree pins')
    end
    %w[receiptSha256 rubySha256 gitSha256 developerGitSha256 xcodebuildSha256].each { |key| require!(sha?(request[key]), 'binding requires independent SHA-256 pins') }
    keys!(request['verifierSha256'], VERIFIERS)
    require!(request['verifierSha256'].values.all? { |value| sha?(value) }, 'binding verifier digest is malformed')
    %w[productRoot toolingRoot receiptPath developerDirectory].each { |key| canonical!(request[key]) }
    require!(request['productRoot'] != request['toolingRoot'] &&
             ADAPTER_PATH == request['toolingRoot'] + '/' + ADAPTER_RELATIVE, 'binding product/tooling roots are equal or adapter root differs')
    require!(request['timeoutSeconds'].is_a?(Integer) && request['timeoutSeconds'].between?(1, 180), 'binding deadline is invalid')
  end

  def self.inputs(request, environment, deadline)
    ruby = file_record(RUBY, deadline, expected: request['rubySha256'], owner: 0, executable: true)
    # Apple's /usr/bin/git dispatcher has multiple legitimate hardlinks. Its
    # complete link count is pinned; the receipt/helpers still require one link.
    git_tool = file_record(GIT, deadline, expected: request['gitSha256'], owner: 0, executable: true, single_link: false)
    developer_git = file_record(request['developerDirectory'] + '/usr/bin/git', deadline,
                                expected: request['developerGitSha256'], executable: true, single_link: false)
    product = git_record(request['productRoot'], request['productCommit'], request['productTree'], VERIFIERS, environment, deadline)
    tooling = git_record(request['toolingRoot'], request['toolingCommit'], request['toolingTree'], [ADAPTER_RELATIVE], environment, deadline)
    adapter = file_record(ADAPTER_PATH, deadline)
    verifiers = VERIFIERS.map do |relative|
      [relative, file_record(request['productRoot'] + '/' + relative, deadline, expected: request['verifierSha256'].fetch(relative))]
    end.to_h
    receipt_path = request['receiptPath']
    parent = directory_record(File.dirname(receipt_path), owner: request['callerUid'], mode: 0700)
    receipt, text = file_record(receipt_path, deadline, expected: request['receiptSha256'], owner: request['callerUid'], mode: 0600, maximum: MAX_JSON, retain: true)
    # This is only dependency extraction from independently hashed bytes. The
    # actual product verifier remains authoritative for all result/expiry checks.
    declared = parse_json(text)
    require!(declared.is_a?(Hash) && declared['root'] == request['productRoot'] &&
             declared['tools'].is_a?(Hash) && declared['tools'].length.between?(1, MAX_TOOLS), 'binding receipt root or dependency fields differ')
    require!(declared['tools'].all? { |path, digest| path.is_a?(String) && sha?(digest) }, 'binding receipt tool declaration is malformed')
    developer = directory_record(request['developerDirectory'])
    xcodebuild = request['developerDirectory'] + '/usr/bin/xcodebuild'
    require!(declared['tools'][xcodebuild] == request['xcodebuildSha256'] &&
             declared['tools'][RUBY] == request['rubySha256'], 'binding receipt lacks reviewed Xcode or fixed Ruby identity')
    tools = declared['tools'].sort.map do |path, digest|
      [path, receipt_tool_record(path, deadline, expected: digest, developer: request['developerDirectory'])]
    end.to_h
    { 'product' => product, 'tooling' => tooling, 'adapter' => adapter,
      'receipt' => receipt, 'receiptParent' => parent, 'verifierSources' => verifiers,
      'ruby' => ruby, 'git' => git_tool, 'developerGit' => developer_git, 'developer' => developer, 'receiptTools' => tools }
  end

  def self.bind_with_executor(request, executor)
    unprivileged!
    # The caller cannot mutate the request while verification is in flight.
    request = parse_json(JSON.generate(request))
    validate_request(request); deep_freeze(request)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + request['timeoutSeconds']
    env = environment(request['developerDirectory'])
    before = inputs(request, env, deadline)
    argv = [RUBY, request['productRoot'] + '/scripts/microphone-regression-gate.rb',
            '--verify-receipt', request['receiptPath'], '--receipt-sha256', request['receiptSha256']]
    output, status = executor.call(argv, env, request['productRoot'], deadline, MAX_OUTPUT)
    require!(output.is_a?(String) && output.bytesize <= MAX_OUTPUT && status == 0 && output == MARKER + "\n",
             'actual product receipt verifier did not return its sole successful marker')
    unprivileged!
    require!(inputs(request, env, deadline) == before, 'binding input identity changed during verification')
    record = { 'schema' => SCHEMA, 'scope' => SCOPE, 'deploymentAuthority' => false,
               'callerUid' => request['callerUid'], 'request' => request, 'inputs' => before,
               'invocation' => { 'argv' => argv, 'environment' => env, 'outputSha256' => Digest::SHA256.hexdigest(output) } }
    require!(JSON.generate(record).bytesize <= MAX_JSON, 'binding record exceeds its bound')
    deep_freeze(record)
  rescue SystemCallError, IOError, ArgumentError, TypeError, JSON::GeneratorError, JSON::NestingError
    raise Refusal, 'binding input is missing, unreadable or malformed (contents redacted)', cause: nil
  end
  private_class_method :bind_with_executor

  def self.bind(request)
    bind_with_executor(request, Executor.new)
  end

  def self.revalidate_with_executor(record, request, executor)
    unprivileged!
    require!(record.is_a?(Hash) && JSON.generate(record).bytesize <= MAX_JSON, 'binding record is malformed')
    fresh = bind_with_executor(request, executor)
    require!(fresh == record, 'binding record no longer matches its independent request and inputs')
    fresh
  rescue JSON::GeneratorError, JSON::NestingError, ArgumentError, TypeError
    raise Refusal, 'binding record is malformed (contents redacted)', cause: nil
  end
  private_class_method :revalidate_with_executor

  def self.revalidate(record, request)
    revalidate_with_executor(record, request, Executor.new)
  end

  def self.main(arguments)
    unprivileged!
    require!(arguments.length == 4 && arguments[0] == '--request' && arguments[2] == '--request-sha256' && sha?(arguments[3]),
             'usage: --request CANONICAL_REQUEST_JSON --request-sha256 INDEPENDENT_SHA256')
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 190
    parent = directory_record(File.dirname(arguments[1]), owner: Process.uid, mode: 0700)
    file, text = file_record(arguments[1], deadline, expected: arguments[3], owner: Process.uid, mode: 0600, maximum: MAX_JSON, retain: true)
    request = parse_json(text); record = bind(request)
    require!(file_record(arguments[1], deadline, expected: arguments[3], owner: Process.uid, mode: 0600, maximum: MAX_JSON) == file &&
             directory_record(parent['path'], owner: Process.uid, mode: 0700) == parent, 'binding request identity changed')
    puts JSON.generate(record)
  rescue SystemCallError, IOError, ArgumentError, TypeError
    raise Refusal, 'binding request is missing or malformed (contents redacted)', cause: nil
  end

  private_class_method :require!, :keys!, :sha?, :parse_json, :deep_freeze,
                       :unprivileged!, :stat_record, :canonical!, :time_left!,
                       :directory_record, :file_record, :receipt_tool_record, :environment, :git,
                       :git_record, :validate_request, :inputs
end

if $PROGRAM_NAME == __FILE__
  begin
    OpensteamerMicrophoneReceiptBinding.main(ARGV)
  rescue OpensteamerMicrophoneReceiptBinding::Refusal
    warn 'microphone receipt binding refused (contents redacted; no deployment authority)'
    exit 1
  end
end
