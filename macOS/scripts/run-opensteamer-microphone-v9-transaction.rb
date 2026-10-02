#!/usr/bin/env ruby
# Original UID supervisor. Never executes a user-writable image as root, sends
# audio commands itself, or kills a privileged transaction after publication.
require 'shellwords'
require_relative 'build-opensteamer-microphone-v9-guards'
require_relative 'opensteamer-microphone-v9-transaction-contract'

module BelugaMicrophoneV9Supervisor
  Build = BelugaMicrophoneV9GuardBuild
  Contract = OpensteamerMicrophoneV9TransactionContract
  class Refused < StandardError; end
  class RecoveryPending < Refused; end
  BASE = '/Library/Application Support/opensteamer'.freeze
  STATES = BASE + '/microphone-v9-transactions'
  EXECUTABLES = BASE + '/microphone-v9-executables'
  MAX_LOG = 1_048_576
  SEAL_SCHEMA = 'opensteamer.microphone-v9-seal-outcome.v1'.freeze
  RUN_SCHEMA = 'opensteamer.microphone-v9-transaction-outcome.v1'.freeze
  OUTCOME_KEYS = %w[schema namespace request_sha256 terminal normal_restarts rollback_restarts reason].freeze
  SEAL_KEYS = %w[schema namespace nonce request_sha256 build_manifest_sha256 worker_sha256 terminal authority_sha256].freeze
  TERMINALS = %w[REFUSED COMMITTED_V9 COMMITTED_V9_UNVERIFIED ROLLED_BACK_EXACT_V8 RECOVERY_REQUIRED].freeze

  def self.require!(value, message)
    raise Refused, message unless value
  end

  def self.original_uid!
    Contract.unelevated!
    require!(ENV.keys.none? { |key| key.match?(/\A(?:RUBY|GEM|BUNDLE|DYLD_|LD_|GIT_CONFIG|RUSTC_WRAPPER|RUSTFLAGS|SWIFT_)/) }, 'inherited supervisor loader refused')
  end

  def self.flat(bytes, keys)
    require!(bytes.is_a?(String) && bytes.bytesize.between?(1, 8192) && bytes.end_with?("\n") && bytes.ascii_only?, 'transaction result extent refused')
    fields = {}
    bytes.lines.each do |line|
      match = /\A([a-z][a-z0-9_]*)=([A-Za-z0-9_.-]+)\n\z/.match(line)
      require!(match && !fields.key?(match[1]), 'transaction result syntax/duplicate refused')
      fields[match[1]] = match[2]
    end
    require!(fields.keys.sort == keys.sort, 'transaction result fields refused')
    fields
  end

  def self.validate_outcome!(bytes, native, request_sha)
    fields = flat(bytes, OUTCOME_KEYS)
    require!(fields['schema'] == RUN_SCHEMA && fields['namespace'] == native.fetch('namespace') &&
             fields['request_sha256'] == request_sha && TERMINALS.include?(fields['terminal']), 'transaction result binding refused')
    require!(%w[normal_restarts rollback_restarts].all? { |key| %w[0 1].include?(fields[key]) } &&
             fields['rollback_restarts'].to_i <= fields['normal_restarts'].to_i, 'transaction restart budget exceeded')
    if fields['terminal'].start_with?('COMMITTED_V9')
      require!(fields['normal_restarts'] == '1' && fields['rollback_restarts'] == '0', 'committed restart counts differ')
    elsif fields['terminal'] == 'ROLLED_BACK_EXACT_V8'
      require!(fields['normal_restarts'] == fields['rollback_restarts'], 'restored restart counts differ')
    end
    fields
  end

  def self.sealed_execution_script(native, mode, request_sha, worker_sha)
    Contract.validate_native!(native); Contract.sha!(request_sha); Contract.sha!(worker_sha)
    require!(%w[--execute-authorized --resume-authorized].include?(mode) && native['worker_sha256'] == worker_sha, 'sealed dispatch role refused')
    parent = EXECUTABLES + '/' + native.fetch('namespace'); executable = parent + '/worker'
    root_request = STATES + '/' + native.fetch('namespace') + '/request.txt'
    ancestors = [ ['/', '0:0:755:1048576', 'drwxr-xr-x '], ['/Library', '0:0:755:1048576', 'drwxr-xr-x '],
      ['/Library/Application Support', '0:80:755:0', 'drwxr-xr-x '], [BASE, '0:0:755:0', 'drwxr-xr-x '],
      [EXECUTABLES, '0:0:711:0', 'drwx--x--x '], [parent, '0:0:711:0', 'drwx--x--x '] ]
    quote = ->(value) { Shellwords.escape(value) }
    guards = ancestors.each_with_index.flat_map do |(path, metadata, permissions), index|
      [ "test -d #{quote.call(path)} && test ! -L #{quote.call(path)}",
        "test \"$(/usr/bin/stat -f '%u:%g:%Lp:%f' #{quote.call(path)})\" = '#{metadata}'",
        "test \"$(/bin/ls -lde #{quote.call(path)} | /usr/bin/cut -c 1-11)\" = '#{permissions}'",
        "ancestor_#{index}=\"$(/usr/bin/stat -f '%d:%i:%u:%g:%Lp:%f' #{quote.call(path)})\"" ]
    end
    rechecks = ancestors.each_with_index.map { |(path, _, _), index| "test \"$(/usr/bin/stat -f '%d:%i:%u:%g:%Lp:%f' #{quote.call(path)})\" = \"$ancestor_#{index}\"" }
    ([ 'set -eu', 'umask 077' ] + guards + [
      "test -f #{quote.call(executable)} && test ! -L #{quote.call(executable)}",
      "test \"$(/usr/bin/stat -f '%u:%g:%Lp:%l:%f' #{quote.call(executable)})\" = '0:0:555:1:0'",
      "test \"$(/bin/ls -lde #{quote.call(executable)} | /usr/bin/cut -c 1-11)\" = '-r-xr-xr-x '",
      "test \"$(/usr/bin/shasum -a 256 #{quote.call(executable)})\" = #{quote.call(worker_sha + '  ' + executable)}"
    ] + rechecks + ["exec /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C #{quote.call(executable)} #{mode} #{quote.call(root_request)} #{request_sha}"]).join("\n")
  end

  # This is a fixed OS copy-and-verify dispatch, not a shell loaded from the
  # request. A new root directory is exclusive and retained on every failure.
  # Only exact verified bytes in that root-owned directory may then execute.
  def self.bootstrap_script(native, request_path, request_sha, manifest_path, manifest_sha, worker_path)
    Contract.validate_native!(native)
    [request_path, manifest_path, worker_path].each { |path| Contract.absolute!(path) }
    [request_sha, manifest_sha].each { |digest| Contract.sha!(digest) }
    require!(request_path.start_with?('/Volumes/t7/') && manifest_path.match?(%r{\A/private/tmp/beluga-microphone-v9-guards\.[A-Za-z0-9_-]+/build-proof\.json\z}) &&
             worker_path == File.join(File.dirname(manifest_path), 'transaction'), 'bootstrap input roles refused')
    directory = BASE + '/microphone-v9-bootstrap-' + native.fetch('nonce')
    destination = directory + '/worker'
    quote = ->(value) { Shellwords.escape(value) }
    # Environment is erased before executing native code. Native code repeats
    # ancestry/ACL/inode/current_exe/hash checks and owns all sealing admission.
    ancestors = [ ['/', '0:0:755:1048576'], ['/Library', '0:0:755:1048576'],
                  ['/Library/Application Support', '0:80:755:0'], [BASE, '0:0:755:0'] ]
    guards = ancestors.each_with_index.flat_map do |(path, metadata), index|
      [ "test -d #{quote.call(path)} && test ! -L #{quote.call(path)}",
        "test \"$(/usr/bin/stat -f '%u:%g:%Lp:%f' #{quote.call(path)})\" = '#{metadata}'",
        "test \"$(/bin/ls -lde #{quote.call(path)} | /usr/bin/cut -c 1-11)\" = 'drwxr-xr-x '",
        "ancestor_#{index}=\"$(/usr/bin/stat -f '%d:%i:%u:%g:%Lp:%f' #{quote.call(path)})\"" ]
    end
    rechecks = ancestors.each_with_index.map do |(path, _metadata), index|
      "test \"$(/usr/bin/stat -f '%d:%i:%u:%g:%Lp:%f' #{quote.call(path)})\" = \"$ancestor_#{index}\""
    end
    ([ 'set -eu', 'umask 077' ] + guards + [
      "test ! -e #{quote.call(directory)} && test ! -L #{quote.call(directory)}",
      "/bin/mkdir -m 0711 #{quote.call(directory)}",
      "/bin/chmod -N #{quote.call(directory)}",
      "/bin/cp -X #{quote.call(worker_path)} #{quote.call(destination)}",
      "/usr/sbin/chown 0:0 #{quote.call(destination)}",
      "/bin/chmod -N #{quote.call(destination)}",
      "/bin/chmod 0555 #{quote.call(destination)}",
      "test \"$(/usr/bin/stat -f '%u:%g:%Lp:%f' #{quote.call(directory)})\" = '0:0:711:0'",
      "test \"$(/bin/ls -lde #{quote.call(directory)} | /usr/bin/cut -c 1-11)\" = 'drwx--x--x '",
      "test \"$(/usr/bin/stat -f '%u:%g:%Lp:%l' #{quote.call(destination)})\" = '0:0:555:1'",
      "test \"$(/bin/ls -lde #{quote.call(destination)} | /usr/bin/cut -c 1-11)\" = '-r-xr-xr-x '",
      "test \"$(/usr/bin/shasum -a 256 #{quote.call(destination)})\" = #{quote.call(native.fetch('worker_sha256') + '  ' + destination)}",
    ] + rechecks + [
      "exec /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C #{quote.call(destination)} --seal-authorized-v9-inputs #{quote.call(request_path)} #{request_sha} #{quote.call(manifest_path)} #{manifest_sha} #{native.fetch('worker_sha256')}"
    ]).join("\n")
  end

  class OwnedSession
    attr_reader :pid, :abort_reason, :records
    def initialize(directory, seconds:, recovery_seconds: 240)
      @directory = directory; @seconds = seconds; @recovery_seconds = recovery_seconds
      @records = []; @abort_reason = nil
    end

    def abort!(reason)
      @abort_reason ||= reason
    end

    def run(argv)
      raise Refused, 'supervisor already owns a live dispatcher' if @pid
      output_path = File.join(@directory, 'transaction.stdout')
      errors_path = File.join(@directory, 'transaction.stderr')
      output = File.open(output_path, File::WRONLY | File::CREAT | File::EXCL, 0600)
      errors = File.open(errors_path, File::WRONLY | File::CREAT | File::EXCL, 0600)
      reader, writer = IO.pipe
      began = Process.clock_gettime(Process::CLOCK_MONOTONIC); abort_sent_at = nil; status = nil
      @pid = Process.spawn(Build::SAFE_ENV, *argv, unsetenv_others: true, pgroup: true, in: reader, out: output, err: errors)
      reader.close
      loop do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        abort!('DEADLINE') if now - began >= @seconds
        abort!('OUTPUT_BOUND') if output.stat.size > MAX_LOG || errors.stat.size > MAX_LOG
        if @abort_reason && !abort_sent_at
          # Single exact abort event; EOF is the fallback if the channel closed.
          begin writer.write("ABORT\n"); writer.flush; rescue Errno::EPIPE, IOError; end
          writer.close; abort_sent_at = now
        end
        if Build::OwnedDarwinChild.exited?(@pid)
          unless Build::OwnedDarwinChild.other_members(@pid, allowed_uids: [0, 501]).empty?
            abort!('DISPATCHER_DESCENDANTS')
            raise RecoveryPending, 'privileged dispatcher exited with live descendants; retain exact namespace for reconciliation'
          end
          waited = Process.waitpid2(@pid, Process::WNOHANG)
          raise Refused, 'owned dispatcher final reap unavailable' unless waited
          status = waited[1]; break
        end
        if abort_sent_at && now - abort_sent_at >= @recovery_seconds
          # No broad signal or retry. The durable root controller lock and active
          # namespace must remain available for exact journal reconciliation.
          raise RecoveryPending, 'owned privileged transaction did not return; retain namespace and inspect its exact controller before any new dispatch'
        end
        sleep 0.02
      end
      output.flush; errors.flush; output.fsync; errors.fsync
      record = { 'pid' => @pid, 'argv' => argv, 'exitStatus' => status.exitstatus, 'termSignal' => status.termsig,
                 'abortReason' => @abort_reason, 'stdout' => output_path, 'stderr' => errors_path }
      @records << record
      require_private_log!(output_path); require_private_log!(errors_path)
      # A zero sudo status alone is not success; callers validate the native
      # namespace-bound terminal and then inspect independent durable readback.
      [File.binread(output_path), File.binread(errors_path), status]
    ensure
      reader&.close unless reader&.closed?
      writer&.close unless writer&.closed?
      output&.close; errors&.close
      @pid = nil if status
    end

    def require_private_log!(path)
      stat = File.lstat(path)
      raise Refused, 'owned dispatcher log alias/metadata/extent refused' unless File.realpath(path) == path && stat.file? && stat.uid == 501 &&
        stat.nlink == 1 && stat.mode & 07777 == 0600 && stat.size <= MAX_LOG
    end
  end

  def self.with_signal_abort(session)
    old = %w[INT TERM HUP].to_h { |signal| [signal, Signal.trap(signal) { session.abort!(signal) }] }
    yield
  ensure
    old&.each { |signal, handler| Signal.trap(signal, handler) }
  end

  def self.manifest_bindings!(native, coordinator, manifest)
    require!(%w[productCommit productTree guardToolingCommit guardToolingTree].zip(%w[product_commit product_tree guard_tooling_commit guard_tooling_tree]).all? { |manifest_key, key| manifest[manifest_key] == native[key] }, 'native/build source provenance differs')
    Contract::TOOL_ROLES.zip(Contract::TOOL_DIGEST_KEYS).each do |role, key|
      require!(manifest.fetch('tools').fetch(role).fetch('sha256') == native.fetch(key) &&
               manifest.fetch('tools').fetch(role).fetch('path') == coordinator.fetch('tools').fetch(role).fetch('path'), 'native/build role differs')
    end
    true
  end

  def self.manifest_identity_fence!(manifest)
    records = manifest.fetch('sources').values + manifest.fetch('tools').values + manifest.fetch('sealedInputs').values +
      %w[swiftCompiler rustCompiler sdkSettings].map { |key| manifest.fetch(key) }
    records.each do |record|
      path = record.fetch('path'); expected = record.fetch('identity')
      require!(File.realpath(path) == path && Build.identity(File.lstat(path)) == expected, 'prepared build input identity changed')
      File.open(path, File::RDONLY | File::NOFOLLOW) { |file| require!(Build.identity(file.stat) == expected, 'prepared build input changed at reopen') }
      require!(Build.identity(File.lstat(path)) == expected, 'prepared build input path changed')
    end
  end

  def self.local_source_generation!(manifest, commands)
    [[Build::PRODUCT, 'productCommit', 'productTree'], [Build::ROOT, 'guardToolingCommit', 'guardToolingTree']].each do |root, commit, tree|
      git = ['/usr/bin/git', '--no-optional-locks', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null',
             '-c', 'core.untrackedCache=false', '-c', 'core.ignoreStat=false', '-C', root]
      require!(commands.run(*git, 'rev-parse', 'HEAD', 'HEAD^{tree}') == manifest.fetch(commit) + "\n" + manifest.fetch(tree) + "\n" &&
               commands.run(*git, 'status', '--porcelain=v1', '--untracked-files=all').empty?, 'prepared local source generation changed')
      flags = commands.run(*git, 'ls-files', '-v', '-z').split("\0")
      require!(!flags.empty? && flags.all? { |entry| entry.start_with?('H ') }, 'prepared source index flags changed')
      next unless root == Build::ROOT
      require!(commands.run(*git, 'symbolic-ref', '--short', 'HEAD') == Build::BRANCH + "\n" &&
               commands.run(*git, 'rev-parse', '@{u}') == manifest.fetch(commit) + "\n" &&
               commands.run(*git, 'remote', 'get-url', '--all', 'origin') == Build::REMOTE + "\n" &&
               commands.run(*git, 'remote', 'get-url', '--push', '--all', 'origin') == Build::REMOTE + "\n", 'prepared local tooling provenance changed')
    end
  end

  def self.fresh_gate_fence!(coordinator, verification)
    bytes, identity = Contract.read_file!(coordinator.fetch('gateObservation'), mode: 0600, maximum: Contract::MAX_JSON)
    require!(identity == verification.fetch('gateObservation'), 'final gate file changed')
    Contract.validate_gate!(coordinator.fetch('nativeRequest'), Contract.parse_json(bytes), now_ms: (Time.now.to_r * 1000).to_i)
  end

  def self.persist_dispatch_inputs!(evidence, descriptor, manifest_path, manifest_sha, native)
    native_path = File.join(evidence, 'native-request.txt'); native_bytes = Contract.native_text(native)
    request_sha = Digest::SHA256.hexdigest(native_bytes)
    File.open(native_path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(native_bytes); file.flush; file.fsync }
    require!(Build.file_record(native_path, digest: request_sha)['sha256'] == request_sha, 'derived native request differs')
    preparation = { 'schema' => 'opensteamer.microphone-v9-dispatch-inputs.v1',
      'coordinator' => descriptor, 'buildManifest' => { 'path' => manifest_path, 'sha256' => manifest_sha },
      'nativeRequest' => { 'path' => native_path, 'sha256' => request_sha } }
    File.open(File.join(evidence, 'dispatch-inputs.json'), File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(JSON.generate(preparation) + "\n"); file.flush; file.fsync }
    File.open(evidence, File::RDONLY | File::NOFOLLOW) { |directory| directory.fsync }
    [native_path, request_sha]
  end

  def self.seal!(coordinator_path, coordinator_sha, manifest_path, manifest_sha, collect_fresh: nil)
    original_uid!
    descriptor = { 'path' => coordinator_path, 'sha256' => coordinator_sha }
    bytes, identity = Contract.read_file!(descriptor, mode: 0600, maximum: Contract::MAX_JSON)
    coordinator = Contract.parse_json(bytes)
    Contract.validate_request!(coordinator)
    evidence = Dir.mktmpdir('beluga-microphone-v9-supervisor.', '/Volumes/t7'); File.chmod(0700, evidence)
    command_directory = File.join(evidence, 'audit-commands'); Dir.mkdir(command_directory, 0700)
    commands = Build::Commands.new(command_directory)
    manifest_record = Build.file_record(manifest_path, digest: manifest_sha)
    manifest = Build.audit_build!(manifest_path, manifest_sha, commands)
    require!(Build.file_record(manifest_path, digest: manifest_sha) == manifest_record, 'build manifest changed during audit')
    manifest_bindings!(coordinator.fetch('nativeRequest'), coordinator, manifest)
    native_path = request_sha = nil
    if collect_fresh
      require!(collect_fresh.respond_to?(:call), 'fresh collector is not callable')
      original_descriptor, original_identity = descriptor, identity
      verification = Contract.verify_with_fresh_collection(coordinator) do |prepared|
        fresh_descriptor = collect_fresh.call(prepared)
        Contract.descriptor!(fresh_descriptor)
        require!(fresh_descriptor.fetch('path') != original_descriptor.fetch('path'), 'fresh collection reused the prior coordinator file')
        fresh_bytes, fresh_identity = Contract.read_file!(fresh_descriptor, mode: 0600, maximum: Contract::MAX_JSON)
        descriptor, identity = fresh_descriptor, fresh_identity
        coordinator = Contract.parse_json(fresh_bytes)
        Contract.validate_request!(coordinator)
        require!(coordinator.reject { |key, _| key == 'gateObservation' } == prepared.reject { |key, _| key == 'gateObservation' }, 'fresh collection changed prepared inputs')
        require!(Contract.read_file!(original_descriptor, mode: 0600, maximum: Contract::MAX_JSON)[1] == original_identity, 'initial coordinator changed during collection')
        manifest_identity_fence!(manifest)
        local_source_generation!(manifest, commands)
        require!(Build.file_record(manifest_path, digest: manifest_sha) == manifest_record, 'prepared build manifest changed')
        native_path, request_sha = persist_dispatch_inputs!(evidence, descriptor, manifest_path, manifest_sha, coordinator.fetch('nativeRequest'))
        # Contract's prepared artifact/receipt/tool fences and actual five-second
        # gate check run after this continuation, including all private fsyncs.
        coordinator
      end
    else
      verification = Contract.verify(coordinator)
      native_path, request_sha = persist_dispatch_inputs!(evidence, descriptor, manifest_path, manifest_sha, coordinator.fetch('nativeRequest'))
    end
    require!(Contract.read_file!(descriptor, mode: 0600, maximum: Contract::MAX_JSON)[1] == identity, 'coordinator changed before dispatch')
    native = coordinator.fetch('nativeRequest')
    require!(request_sha == verification.fetch('nativeRequestSha256') && File.binread(native_path) == verification.fetch('nativeRequest'), 'prepared native projection differs')
    script = bootstrap_script(native, native_path, request_sha, manifest_path, manifest_sha, manifest.fetch('tools').fetch('worker').fetch('path'))
    session = OwnedSession.new(evidence, seconds: 45, recovery_seconds: 45)
    manifest_identity_fence!(manifest) if collect_fresh
    require!(Build.file_record(manifest_path, digest: manifest_sha) == manifest_record, 'build manifest changed before dispatch')
    fresh_gate_fence!(coordinator, verification)
    stdout, stderr, status = with_signal_abort(session) { session.run(['/usr/bin/sudo', '-n', '--', '/bin/sh', '-c', script]) }
    fields = flat(stdout, SEAL_KEYS)
    require!(status.success? && stderr.empty? && session.abort_reason.nil? && fields['schema'] == SEAL_SCHEMA &&
             fields['namespace'] == native['namespace'] && fields['nonce'] == native['nonce'] && fields['request_sha256'] == request_sha &&
             fields['build_manifest_sha256'] == manifest_sha && fields['worker_sha256'] == native['worker_sha256'] &&
             fields['terminal'] == 'SEALED_INPUTS_NOT_INSTALLED' && fields['authority_sha256'].match?(/\A[0-9a-f]{64}\z/), 'root seal did not prove a complete exact namespace; retain attempt')
    { 'evidence' => evidence, 'request' => native_path, 'requestSHA256' => request_sha, 'result' => fields,
      'deploymentAuthority' => false, 'liveInstalled' => false }
  end

  def self.fresh_execute_inputs!(request_path, request_sha, native, commands)
    preparation_path = File.join(File.dirname(request_path), 'dispatch-inputs.json')
    record = Build.file_record(preparation_path)
    bytes, = Contract.read_file!({ 'path' => preparation_path, 'sha256' => record['sha256'] }, mode: 0600, maximum: 65_536)
    preparation = Contract.parse_json(bytes)
    Contract.keys!(preparation, %w[schema coordinator buildManifest nativeRequest], 'original UID dispatch preparation')
    require!(preparation['schema'] == 'opensteamer.microphone-v9-dispatch-inputs.v1' &&
             preparation['nativeRequest'] == { 'path' => request_path, 'sha256' => request_sha }, 'original native dispatch crosslink differs')
    %w[coordinator buildManifest nativeRequest].each { |key| Contract.descriptor!(preparation[key]) }
    manifest = Build.audit_build!(preparation['buildManifest']['path'], preparation['buildManifest']['sha256'], commands)
    require!(%w[productCommit productTree guardToolingCommit guardToolingTree].zip(%w[product_commit product_tree guard_tooling_commit guard_tooling_tree]).all? { |manifest_key, key| manifest[manifest_key] == native[key] }, 'current dispatch source provenance differs')
    coordinator_bytes, identity = Contract.read_file!(preparation['coordinator'], mode: 0600, maximum: Contract::MAX_JSON)
    coordinator = Contract.parse_json(coordinator_bytes); Contract.validate_request!(coordinator)
    require!(coordinator.fetch('nativeRequest') == native, 'fresh coordinator native binding differs')
    manifest_bindings!(native, coordinator, manifest)
    fresh_bytes, fresh_identity = Contract.read_file!(coordinator.fetch('receiptRequest'), mode: 0600, maximum: Contract::MAX_JSON)
    binding_bytes, binding_identity = Contract.read_file!(coordinator.fetch('freshBinding'), mode: 0600, maximum: Contract::MAX_JSON)
    fresh = Contract.parse_json(fresh_bytes); binding = Contract.parse_json(binding_bytes)
    producer_bytes, = Contract.read_file!({ 'path' => Contract::ARTIFACT_ROOT + '/binding-request.json', 'sha256' => Contract::ARTIFACT_FILES.fetch('binding-request.json') }, mode: 0400, maximum: Contract::MAX_JSON)
    Contract.validate_fresh_receipt_request!(native, fresh, Contract.parse_json(producer_bytes))
    OpensteamerMicrophoneReceiptBinding.revalidate(binding, fresh)
    require!(Build.file_record(preparation_path) == record && Contract.read_file!(preparation['coordinator'], mode: 0600, maximum: Contract::MAX_JSON)[1] == identity &&
             Contract.read_file!(coordinator.fetch('receiptRequest'), mode: 0600, maximum: Contract::MAX_JSON)[1] == fresh_identity &&
             Contract.read_file!(coordinator.fetch('freshBinding'), mode: 0600, maximum: Contract::MAX_JSON)[1] == binding_identity,
             'fresh original-UID receipt/source inputs changed')
    true
  end

  def self.execute!(mode, original_request_path, request_sha, expected_worker_sha)
    original_uid!
    require!(%w[--execute-authorized --resume-authorized].include?(mode), 'native dispatch mode refused')
    bytes, = Contract.read_file!({ 'path' => original_request_path, 'sha256' => request_sha }, mode: 0600, maximum: 65_536)
    native = Contract.parse_native(bytes); Contract.sha!(expected_worker_sha)
    require!(native['worker_sha256'] == expected_worker_sha, 'independent worker pin differs')
    evidence = Dir.mktmpdir('beluga-microphone-v9-supervisor.', '/Volumes/t7'); File.chmod(0700, evidence)
    command_directory = File.join(evidence, 'audit-commands'); Dir.mkdir(command_directory, 0700)
    fresh_execute_inputs!(original_request_path, request_sha, native, Build::Commands.new(command_directory)) if mode == '--execute-authorized'
    executable = EXECUTABLES + '/' + native.fetch('namespace') + '/worker'
    # Exact root role; native code holds/revalidates root ownership, ancestry,
    # inode, bytes, original authority, controller lock and fresh live gate.
    stat = File.lstat(executable)
    require!(File.realpath(executable) == executable && stat.file? && stat.uid.zero? && stat.gid.zero? && stat.nlink == 1 &&
             stat.mode & 07777 == 0555 && Digest::SHA256.file(executable).hexdigest == expected_worker_sha &&
             Build.identity(File.lstat(executable)) == Build.identity(stat), 'sealed worker role changed')
    session = OwnedSession.new(evidence, seconds: native.fetch('timeout_seconds').to_i + 10)
    script = sealed_execution_script(native, mode, request_sha, expected_worker_sha)
    stdout, stderr, status = with_signal_abort(session) { session.run(['/usr/bin/sudo', '-n', '--', '/bin/sh', '-c', script]) }
    fields = validate_outcome!(stdout, native, request_sha)
    require!(stderr.empty? && status.exited?, 'native dispatcher did not return a typed terminal')
    require!(fields['terminal'] != 'COMMITTED_V9' || (status.success? && session.abort_reason.nil?), 'commit reported by an aborted/failed dispatcher; independent recovery readback required')
    # Reporting is not independent deployment proof. The caller must read the
    # exact durable journal, loaded HAL, current host and route teardown before
    # claiming success; nonzero/refused/aborted outcomes can never be green.
    { 'evidence' => evidence, 'result' => fields, 'exitStatus' => status.exitstatus,
      'abortReason' => session.abort_reason, 'deploymentVerified' => false }
  end

  def self.main(arguments)
    case [arguments[0], arguments.size]
    when ['--seal-authorized-v9', 5]
      puts JSON.generate(seal!(*arguments[1..-1]))
    when ['--execute-authorized-v9', 4]
      puts JSON.generate(execute!('--execute-authorized', *arguments[1..-1]))
    when ['--resume-authorized-v9', 4]
      puts JSON.generate(execute!('--resume-authorized', *arguments[1..-1]))
    else
      raise Refused, 'exact seal/execute/resume supervisor arguments required'
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    BelugaMicrophoneV9Supervisor.main(ARGV)
  rescue BelugaMicrophoneV9Supervisor::Refused, BelugaMicrophoneV9GuardBuild::Refused, OpensteamerMicrophoneV9TransactionContract::Refusal => error
    warn 'microphone-v9-supervisor: ' + error.message
    exit 78
  end
end
