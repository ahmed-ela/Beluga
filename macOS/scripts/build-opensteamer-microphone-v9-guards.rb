#!/usr/bin/env ruby
# Original-UID build only. No audio query, installer, privilege or live service call.
require 'digest'
require 'fileutils'
require 'fiddle'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'opensteamer-microphone-v9-host-gate'
require_relative 'opensteamer-microphone-v9-input-staging'

module BelugaMicrophoneV9GuardBuild
  class Refused < StandardError; end
  class UniqueObject < Hash
    def []=(key, value)
      raise Refused, 'build proof duplicate JSON field' if key?(key)
      super
    end
  end
  ROOT = '/Users/ahmed/Documents/Codex/opensteamer-diagnostic-v3'.freeze
  PRODUCT = '/Volumes/t7/beluga-quality-step.idpzQO/source'.freeze
  PRODUCT_COMMIT = '168036d74e08e7b49aad37907cf9b84b5dcc8456'.freeze
  PRODUCT_TREE = '044cce09563a0384597e8529565ddff290bd4a6f'.freeze
  REMOTE = 'https://github.com/ahmedelami/opensteamer.git'.freeze
  BRANCH = 'fix/diagnostic-driver-v17-airplay-stabilization'.freeze
  DEVELOPER = '/Volumes/t7/opensteamer-space-recovery-20260804/nonrepo/Xcode-26.6.0.app/Contents/Developer'.freeze
  SWIFTC = DEVELOPER + '/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
  SWIFT_SHA = '2ed38571e92c0283091838c1649e27650ad9c99950288e883c7b2dc6c4ce89fb'.freeze
  RUSTC = '/opt/homebrew/Cellar/rust/1.97.1/bin/rustc'.freeze
  RUST_SHA = 'd69d40bfd2e11825feb3538512b6ffcd63de91c35ec36bb876849f0f9f8fe6bd'.freeze
  SDK = DEVELOPER + '/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk'
  SDK_SHA = 'f8d005f09381389167f9e0aeaa169bc9e7dff162ef22ca2fd8e98df7ff1acafe'.freeze
  DECODER = PRODUCT + '/macOS/Sources/CaptureServer/WorldwideVirtualMicrophoneDriverIdle.swift'
  DECODER_SHA = 'fd108f745f4d8b78208d63f639c612c721e376df1d1fff12a85613e3e82792f8'.freeze
  MONITOR = PRODUCT + '/macOS/scripts/opensteamer-v91-coreaudio-route-monitor.swift'
  MONITOR_SHA = 'b7ffc3c939ff2b19d1f85305335b3363555a967a76b38b034db377209f88bf86'.freeze
  OBSERVERS = '/Users/ahmed/Library/Application Support/opensteamer/paired-host-updates-v90/paired-v90-update-1790273646-83304-497866f7-25e2-4701-b155-442ca77d541c/pinned-v86-observer-tools'.freeze
  REUSE_PROOF = '/private/tmp/beluga-microphone-v9-guards.20261001-32089-syciju/build-proof.json'.freeze
  REUSE_SHA = 'a4181ebc4124a0445b58be029207d44b9c01b5209d9c9f091dbb94721e280a00'.freeze
  REUSE_COMMIT = '3132f604ed68de66e788e2860212fe4474b5235f'.freeze
  REUSE_TREE = '5491060293b9cf13b929c5d3ae8129fdc31b1d37'.freeze
  REUSED_ROLES = { 'idleHelper' => 'idle-helper', 'bothOrderProbe' => 'public-proof', 'routeGuardian' => 'route-guardian' }.freeze
  Staging = BelugaMicrophoneV9InputStaging
  MAX_COMMAND_SECONDS = 120
  MAX_LOG_BYTES = 16 * 1024 * 1024
  SAFE_ENV = { 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME' => '/var/empty',
               'DEVELOPER_DIR' => DEVELOPER, 'LC_ALL' => 'en_US.UTF-8' }.freeze

  # Darwin SDK sys/wait.h + sys/proc_info.h, checked against the pinned SDK.
  # WNOWAIT retains the owned leader's PID until no running group member remains.
  # Darwin proc_listpids excludes dead, reparented zombies; launchd reaps those.
  module OwnedDarwinChild
    WAITID = Fiddle::Function.new(Fiddle::Handle::DEFAULT['waitid'],
                                 [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    LISTPIDS = Fiddle::Function.new(Fiddle::Handle::DEFAULT['proc_listpids'],
                                   [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    PIDINFO = Fiddle::Function.new(Fiddle::Handle::DEFAULT['proc_pidinfo'],
                                  [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    def self.exited?(pid)
      info = Fiddle::Pointer.malloc(128, Fiddle::RUBY_FREE); info[0, 128] = "\0" * 128
      raise Refused, 'owned waitid observation failed' unless WAITID.call(1, pid, info, 0x4 | 0x1 | 0x20).zero?
      observed = info[12, 4].unpack1('i!')
      raise Refused, 'owned waitid identity differs' unless observed.zero? || observed == pid
      observed == pid
    end
    def self.inventory(pid)
      buffer = Fiddle::Pointer.malloc(16_384, Fiddle::RUBY_FREE); buffer[0, 16_384] = "\0" * 16_384
      length = LISTPIDS.call(2, pid, buffer, 16_384)
      raise Refused, 'owned process-group inventory unavailable or full' unless length >= 0 && length < 16_384 && (length % 4).zero?
      buffer[0, length].unpack('i!*').select { |value| value > 0 && value != pid }.uniq
    end
    def self.member_identity(pid)
      info = Fiddle::Pointer.malloc(64, Fiddle::RUBY_FREE); info[0, 64] = "\0" * 64
      return nil unless PIDINFO.call(pid, 13, 0, info, 64) == 64
      info[0, 64].unpack('I!*')
    end
    def self.other_members(pid, allowed_uids: [501])
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.25
      loop do
        members = inventory(pid); unstable = false
        members.each do |member|
          values = member_identity(member)
          unless values
            # A disappearing process may be discarded only after a fresh group
            # inventory proves it absent, never merely on failed pidinfo.
            raise Refused, 'owned group member generation unavailable' if inventory(pid).include?(member)
            unstable = true; break
          end
          raise Refused, 'owned group member identity or UID differs' unless values[0] == member && values[2] == pid &&
            allowed_uids.include?(values[9]) && allowed_uids.include?(values[11])
        end
        return members unless unstable
        raise Refused, 'owned process-group churn exceeded bound' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      end
    end
  end

  def self.require!(value, message)
    raise Refused, message unless value
  end

  def self.identity(stat)
    [stat.dev, stat.ino, stat.uid, stat.gid, stat.mode, stat.nlink, stat.size,
     stat.mtime.to_i, stat.mtime.nsec, stat.ctime.to_i, stat.ctime.nsec]
  end

  def self.file_record(path, digest: nil)
    internal = path.is_a?(String) && path.match?(%r{\A/private/tmp/beluga-microphone-v9-guards\.[a-zA-Z0-9_-]+/})
    record = Staging.record!(path, internal: internal)
    require!(!digest || record['sha256'] == digest, 'build input digest differs')
    record
  rescue Staging::Refused, SystemCallError
    raise Refused, 'build input unavailable'
  end

  class Commands
    attr_reader :records, :active_pid
    def initialize(directory)
      @directory = directory; @records = []
    end

    # The launcher owns and reaps only its compiler/Git process group. Kernel
    # calls may block; they are never treated as a successful build on timeout.
    def run(*argv)
      raise Refused, 'owned build command is already active' if @active_pid
      index = @records.size + 1
      stdout_path = File.join(@directory, format('%03d.stdout', index))
      stderr_path = File.join(@directory, format('%03d.stderr', index))
      output = File.open(stdout_path, File::WRONLY | File::CREAT | File::EXCL, 0600)
      errors = File.open(stderr_path, File::WRONLY | File::CREAT | File::EXCL, 0600)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pid = Process.spawn(SAFE_ENV, *argv, unsetenv_others: true, pgroup: true, in: File::NULL, out: output, err: errors)
      @active_pid = pid
      status = nil; timed_out = false
      loop do
        if OwnedDarwinChild.exited?(pid)
          if OwnedDarwinChild.other_members(pid).empty?
            waited = Process.waitpid2(pid, Process::WNOHANG)
            raise Refused, 'owned exited compiler was not waitable' unless waited
            status = waited[1]; break
          else
            timed_out = true; status = terminate_owned!(pid); break
          end
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        if elapsed >= MAX_COMMAND_SECONDS || output.stat.size > MAX_LOG_BYTES || errors.stat.size > MAX_LOG_BYTES
          timed_out = true; status = terminate_owned!(pid)
          break
        end
        sleep 0.02
      end
      timed_out ||= output.stat.size > MAX_LOG_BYTES || errors.stat.size > MAX_LOG_BYTES
      output.flush; errors.flush; output.fsync; errors.fsync
      @records << { 'argv' => argv, 'pid' => pid, 'exitStatus' => status.exitstatus, 'termSignal' => status.termsig,
                    'timedOutOrLogBound' => timed_out, 'stdout' => log_record(stdout_path),
                    'stderr' => log_record(stderr_path) }
      raise Refused, 'owned build command failed or exceeded bound' if timed_out || !status.success?
      File.binread(stdout_path)
    ensure
      # A compiler's isolated process group does not receive the launcher's
      # terminal Ctrl-C. Retain the unreaped leader PID until group termination
      # so a new process cannot reuse it during TERM/KILL cleanup.
      begin
        status = terminate_owned!(pid) if pid && !status
      ensure
        # Keep unresolved ownership explicit if containment itself fails.
        @active_pid = nil if status
        output&.close; errors&.close
      end
    end

    def terminate_owned!(pid)
      # Darwin getpgid on a retained, exited leader may return ESRCH while its
      # still-live descendants remain in the owned group. WNOWAIT reserves the
      # leader identity; never reap it as a substitute for group cleanup.
      unless OwnedDarwinChild.exited?(pid)
        begin
          raise Refused, 'owned compiler group identity changed' unless Process.getpgid(pid) == pid
        rescue Errno::ESRCH
          raise Refused, 'owned compiler identity disappeared without an exited leader' unless OwnedDarwinChild.exited?(pid)
        end
      end
      OwnedDarwinChild.other_members(pid)
      begin Process.kill('TERM', -pid); rescue Errno::ESRCH; end
      # Do not reap the leader before the final group signal: descendants may
      # survive an early leader exit, and the retained PID prevents reuse.
      sleep 0.1
      unless OwnedDarwinChild.exited?(pid) && OwnedDarwinChild.other_members(pid).empty?
        begin Process.kill('KILL', -pid); rescue Errno::ESRCH; end
      end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      loop do
        if OwnedDarwinChild.exited?(pid) && OwnedDarwinChild.other_members(pid).empty?
          waited = Process.waitpid2(pid, Process::WNOHANG)
          return waited[1] if waited
        end
        raise Refused, 'owned compiler reap was not confirmed' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.02
      end
    rescue Errno::ECHILD
      raise Refused, 'owned compiler was unexpectedly reaped elsewhere'
    rescue Errno::ESRCH
      raise Refused, 'owned compiler identity unavailable before confirmed group cleanup'
    end

    def log_record(path)
      stat = File.lstat(path)
      { 'path' => path, 'sha256' => Digest::SHA256.file(path).hexdigest, 'identity' => BelugaMicrophoneV9GuardBuild.identity(stat) }
    end
  end

  def self.git!(commands, root, *arguments)
    commands.run('/usr/bin/git', '-C', root, *arguments).strip
  end

  def self.sealed_inputs!
    gate = BelugaMicrophoneV9HostGate
    records = { 'tools/opensteamer-microphone-v9-host-gate.rb' => file_record(ROOT + '/macOS/scripts/opensteamer-microphone-v9-host-gate.rb') }
    gate::PRODUCT_PINS.each { |name, sha| records['tools/product/' + name] = file_record(PRODUCT + '/macOS/scripts/' + name, digest: sha) }
    gate::OBSERVER_PINS.each { |name, sha| records['tools/observers/' + name] = file_record(OBSERVERS + '/' + name, digest: sha) }
    records
  end

  def self.legacy_source_paths
    helper = ROOT + '/macOS/scripts/microphone-v9-idle-proof'
    [ROOT + '/iOS/opensteamer/scripts/physical-blackhole-microphone-probe.swift', DECODER, MONITOR,
     helper + '/BelugaMicrophoneIdleProof.swift', helper + '/BelugaMicrophoneEndpointContract.swift', helper + '/main.swift',
     ROOT + '/macOS/scripts/build-opensteamer-microphone-v9-guards.rb',
     ROOT + '/macOS/scripts/run-opensteamer-microphone-v9-transaction.rb',
     ROOT + '/macOS/scripts/opensteamer-microphone-v9-host-gate.rb',
     ROOT + '/macOS/scripts/opensteamer-microphone-v9-transaction-contract.rb',
     ROOT + '/macOS/scripts/opensteamer-microphone-receipt-binding.rb'] +
      %w[transaction os backend proof seal].map { |name| ROOT + '/macOS/scripts/opensteamer-microphone-v9-' + name + '.rs' }
  end

  def self.source_paths
    legacy_source_paths + [ROOT + '/macOS/scripts/opensteamer-microphone-v9-input-staging.rb']
  end

  def self.compile_recipes(root)
    [[RUSTC, '--edition=2021', '-O', '-D', 'warnings', ROOT + '/macOS/scripts/opensteamer-microphone-v9-transaction.rs', '-o', root + '/transaction']]
  end

  # Historical recipes are checked, not executed. Their output/source paths
  # retain the original build namespace and original producer provenance.
  def self.legacy_compile_recipes(root)
    helper = ROOT + '/macOS/scripts/microphone-v9-idle-proof'
    compile_recipes(root) + [
      [SWIFTC, '-sdk', SDK, '-swift-version', '6', '-warnings-as-errors', '-O', DECODER,
       helper + '/BelugaMicrophoneIdleProof.swift', helper + '/BelugaMicrophoneEndpointContract.swift', helper + '/main.swift',
       '-framework', 'CoreAudio', '-framework', 'CryptoKit', '-o', root + '/idle-helper'],
      [SWIFTC, '-sdk', SDK, '-swift-version', '5', '-O', '-D', 'BELUGA_MICROPHONE_V9_ORACLE', root + '/public/main.swift', DECODER,
       '-framework', 'CoreAudio', '-framework', 'AudioToolbox', '-framework', 'CryptoKit', '-o', root + '/public-proof'],
      [SWIFTC, '-sdk', SDK, '-swift-version', '6', '-warnings-as-errors', '-O', MONITOR,
       '-framework', 'CoreAudio', '-o', root + '/route-guardian']
    ]
  end

  def self.audit_recipes!(proof, root, legacy: false)
    paths = legacy ? legacy_source_paths : source_paths
    require!(proof['sources'].is_a?(Hash) && proof['sources'].keys.sort == (paths + [root + '/public/main.swift']).sort,
             'build exact source closure differs')
    recipes = legacy ? legacy_compile_recipes(root) : compile_recipes(root)
    commands = proof['commands']
    require!(commands.is_a?(Array) && commands.size.between?(recipes.size, 40), 'build command evidence extent differs')
    compiler_commands = commands.select { |command| command.is_a?(Hash) && command['argv'].is_a?(Array) && [RUSTC, SWIFTC].include?(command['argv'][0]) }
    require!(compiler_commands.map { |command| command['argv'] } == recipes, 'build exact ordered compiler recipes differ')
    require!(commands.all? { |command| command.is_a?(Hash) && command['argv'].is_a?(Array) &&
             (recipes.include?(command['argv']) || (command['argv'][0] == '/usr/bin/git' && command['argv'][1] == '-C' &&
             [ROOT, PRODUCT].include?(command['argv'][2]))) }, 'build non-recipe command refused')
    true
  end

  def self.audit_command_records!(records, root)
    require!(records.is_a?(Array) && records.size.between?(1, 40), 'build command evidence extent differs')
    records.each_with_index do |command, index|
      require!(command.is_a?(Hash) && command.keys.sort == %w[argv exitStatus pid stderr stdout termSignal timedOutOrLogBound] &&
               command['timedOutOrLogBound'] == false && command['exitStatus'] == 0 && command['termSignal'].nil? &&
               command['pid'].is_a?(Integer) && command['pid'].positive? && command['argv'].is_a?(Array) &&
               !command['argv'].empty? && command['argv'].all? { |item| item.is_a?(String) && item.bytesize.between?(1, 8192) && item.ascii_only? }, 'build command result differs')
      %w[stdout stderr].each do |channel|
        input = command.fetch(channel)
        require!(input.is_a?(Hash) && input.keys.sort == %w[identity path sha256] &&
          input['path'] == File.join(root, 'commands', format('%03d.%s', index + 1, channel)), 'build command log path differs')
        require!(input['identity'][4] & 07777 == 0600 && input['identity'][6] <= MAX_LOG_BYTES &&
          Staging.record!(input.fetch('path'), expected: input, empty: true, internal: true) == input, 'build command log changed')
      end
    end
  end

  def self.reused_tools!
    record = Staging.record!(REUSE_PROOF, internal: true)
    require!(record['sha256'] == REUSE_SHA && record['identity'][4] & 07777 == 0600 && record['identity'][6] <= 1_048_576,
      'original reusable proof pin/mode/extent differs')
    proof = JSON.parse(proof_bytes!(record), object_class: UniqueObject, create_additions: false, max_nesting: 16, allow_nan: false)
    keys = %w[productCommit productTree guardToolingCommit guardToolingTree schema deploymentAuthority liveQueriesPerformed sources swiftCompiler rustCompiler sdkSettings commands sealedInputs tools]
    require!(proof.is_a?(Hash) && proof.keys.sort == keys.sort && proof['schema'] == 'opensteamer.microphone-v9.native-guard-build.v1' &&
      proof['deploymentAuthority'] == false && proof['liveQueriesPerformed'] == false &&
      proof.values_at('productCommit', 'productTree', 'guardToolingCommit', 'guardToolingTree') == [PRODUCT_COMMIT, PRODUCT_TREE, REUSE_COMMIT, REUSE_TREE],
      'original reusable build provenance differs')
    root = File.dirname(REUSE_PROOF)
    audit_recipes!(proof, root, legacy: true); audit_command_records!(proof.fetch('commands'), root)
    require!(proof['tools'].is_a?(Hash) && proof['tools'].keys.sort == %w[bothOrderProbe idleHelper routeGuardian worker], 'original reusable tool roles differ')
    helper = ROOT + '/macOS/scripts/microphone-v9-idle-proof'
    closure = [DECODER, MONITOR, ROOT + '/iOS/opensteamer/scripts/physical-blackhole-microphone-probe.swift',
      helper + '/BelugaMicrophoneIdleProof.swift', helper + '/BelugaMicrophoneEndpointContract.swift', helper + '/main.swift', root + '/public/main.swift']
    closure.each do |path|
      input = proof.fetch('sources').fetch(path)
      require!(input['path'] == path && Staging.record!(path, expected: input) == input, 'reused Swift source closure changed')
    end
    require!(proof['sources'].fetch(DECODER)['sha256'] == DECODER_SHA && proof['sources'].fetch(MONITOR)['sha256'] == MONITOR_SHA &&
      proof['sources'].fetch(root + '/public/main.swift')['sha256'] == proof['sources'].fetch(closure[2])['sha256'], 'reused Swift source byte pins differ')
    { 'swiftCompiler' => file_record(File.realpath(SWIFTC), digest: SWIFT_SHA),
      'rustCompiler' => file_record(RUSTC, digest: RUST_SHA),
      'sdkSettings' => file_record(File.join(File.realpath(SDK), 'SDKSettings.json'), digest: SDK_SHA) }.each do |key, input|
      require!(proof[key] == input, 'original reusable toolchain differs')
    end
    tools = REUSED_ROLES.to_h do |role, name|
      input = proof.fetch('tools').fetch(role)
      require!(input['path'] == root + '/' + name && input['identity'][4] & 0111 != 0 &&
        Staging.record!(input.fetch('path'), expected: input, internal: true) == input, 'original reusable Swift binary changed')
      [role, input]
    end
    # Changed historical Ruby/Rust source records remain evidence in the pinned
    # original proof. They are not relabeled as this build's current sources.
    require!(Staging.record!(REUSE_PROOF, expected: record, internal: true) == record, 'original reusable proof changed')
    { 'buildProof' => record, 'guardToolingCommit' => REUSE_COMMIT, 'guardToolingTree' => REUSE_TREE, 'tools' => tools }
  rescue JSON::ParserError, JSON::NestingError, KeyError, TypeError, NoMethodError, Staging::Refused, SystemCallError, IOError
    raise Refused, 'original reusable build audit refused'
  end

  def self.proof_bytes!(record)
    require!(record.fetch('identity')[6].between?(1, 1_048_576), 'build proof read extent differs')
    bytes = File.open(record.fetch('path'), File::RDONLY | File::NOFOLLOW) do |file|
      require!(identity(file.stat) == record.fetch('identity'), 'build proof FD differs')
      value = file.read(record.fetch('identity')[6] + 1)
      require!(identity(file.stat) == record.fetch('identity'), 'build proof changed at read')
      value
    end
    require!(bytes && bytes.bytesize == record.fetch('identity')[6] && Digest::SHA256.hexdigest(bytes) == record.fetch('sha256') &&
      bytes.dup.force_encoding('UTF-8').valid_encoding? && identity(File.lstat(record.fetch('path'))) == record.fetch('identity'), 'build proof changed during bounded read')
    bytes
  end

  def self.source_proof!(commands)
    require!(Process.uid == 501 && Process.euid == 501, 'native guard build is original UID501 only')
    require!(File.realpath(ROOT) == ROOT && File.realpath(PRODUCT) == PRODUCT, 'source root alias refused')
    require!(git!(commands, PRODUCT, 'rev-parse', 'HEAD') == PRODUCT_COMMIT &&
             git!(commands, PRODUCT, 'rev-parse', 'HEAD^{tree}') == PRODUCT_TREE &&
             git!(commands, PRODUCT, 'status', '--porcelain=v1', '--untracked-files=all').empty?, 'frozen product source differs')
    head = git!(commands, ROOT, 'rev-parse', 'HEAD'); tree = git!(commands, ROOT, 'rev-parse', 'HEAD^{tree}')
    require!([head, tree].all? { |value| value.match?(/\A[0-9a-f]{40}\z/) } &&
             git!(commands, ROOT, 'symbolic-ref', '--short', 'HEAD') == BRANCH &&
             git!(commands, ROOT, 'rev-parse', '@{u}') == head &&
             git!(commands, ROOT, 'remote', 'get-url', '--all', 'origin') == REMOTE &&
             git!(commands, ROOT, 'remote', 'get-url', '--push', '--all', 'origin') == REMOTE &&
             git!(commands, ROOT, 'status', '--porcelain=v1', '--untracked-files=all').empty?, 'guard tooling is not clean/pushed')
    remote = git!(commands, ROOT, 'ls-remote', '--exit-code', '--refs', '--heads', 'origin', 'refs/heads/' + BRANCH)
    require!(remote == head + "\trefs/heads/" + BRANCH, 'fresh remote guard source differs')
    { 'productCommit' => PRODUCT_COMMIT, 'productTree' => PRODUCT_TREE, 'guardToolingCommit' => head, 'guardToolingTree' => tree }
  end

  # Revalidate actual build evidence unelevated immediately before the trusted
  # OS staging dispatch. Nothing in this manifest grants installation authority.
  def self.audit_build!(path, expected_sha, commands)
    require!(Process.uid == 501 && Process.euid == 501 && expected_sha.match?(/\A[0-9a-f]{64}\z/), 'build audit UID/digest refused')
    record = file_record(path, digest: expected_sha)
    require!(record.fetch('identity')[6] <= 1_048_576 && record.fetch('identity')[4] & 07777 == 0600, 'build proof mode/extent refused')
    bytes = proof_bytes!(record)
    require!(file_record(path, digest: expected_sha) == record && bytes.dup.force_encoding('UTF-8').valid_encoding?, 'build proof changed during read')
    proof = JSON.parse(bytes, object_class: UniqueObject, create_additions: false, max_nesting: 16, allow_nan: false)
    expected_keys = %w[productCommit productTree guardToolingCommit guardToolingTree schema deploymentAuthority liveQueriesPerformed sources swiftCompiler rustCompiler sdkSettings commands originalInputs sealedInputs releaseInputs reusedTools tools]
    require!(proof.is_a?(Hash) && proof.keys.sort == expected_keys.sort && proof['schema'] == 'opensteamer.microphone-v9.native-guard-build.v2' &&
             proof['deploymentAuthority'] == false && proof['liveQueriesPerformed'] == false, 'build proof schema/authority refused')
    provenance = source_proof!(commands)
    require!(provenance.all? { |key, value| proof[key] == value }, 'build source provenance differs')
    build_root = File.dirname(path)
    require!(build_root.match?(%r{\A/private/tmp/beluga-microphone-v9-guards\.[a-zA-Z0-9_-]+\z}) && File.basename(path) == 'build-proof.json', 'build output namespace refused')
    audit_recipes!(proof, build_root)
    require!(proof['tools'].is_a?(Hash) && proof['tools'].keys.sort == %w[bothOrderProbe idleHelper routeGuardian worker], 'build role set differs')
    { 'worker' => 'transaction', 'idleHelper' => 'idle-helper', 'bothOrderProbe' => 'public-proof', 'routeGuardian' => 'route-guardian' }.each do |role, name|
      input = proof['tools'].fetch(role)
      require!(input['path'] == File.join(build_root, name) && input['identity'].is_a?(Array) &&
               input['identity'][4].is_a?(Integer) && input['identity'][4] & 0111 != 0, 'compiled build role path/mode differs')
    end
    inputs = sealed_inputs!
    Staging.audit!(build_root, inputs, proof.fetch('originalInputs'), proof.fetch('sealedInputs'), proof.fetch('releaseInputs'))
    require!(proof.fetch('reusedTools') == reused_tools!, 'build original reusable proof differs')
    REUSED_ROLES.each_key do |role|
      original = proof.fetch('reusedTools').fetch('tools').fetch(role); copied = proof.fetch('tools').fetch(role)
      require!(copied['sha256'] == original['sha256'] && copied['identity'][4] & 07777 == original['identity'][4] & 07777 &&
        copied['identity'][0, 2] != original['identity'][0, 2], 'build reused tool copy crosslink differs')
    end
    require!(proof['sources'].is_a?(Hash) && proof['sources'].size.between?(8, 32) && proof['sources'].all? { |source, input|
      input.is_a?(Hash) && input['path'] == source &&
        (source == DECODER || source == MONITOR || source == File.join(build_root, 'public/main.swift') ||
         source.start_with?(ROOT + '/macOS/scripts/', ROOT + '/iOS/opensteamer/scripts/'))
    }, 'build source paths refused')
    public_source = ROOT + '/iOS/opensteamer/scripts/physical-blackhole-microphone-probe.swift'
    require!(proof['sources'].fetch(DECODER).fetch('sha256') == DECODER_SHA && proof['sources'].fetch(MONITOR).fetch('sha256') == MONITOR_SHA &&
             proof['sources'].fetch(File.join(build_root, 'public/main.swift')).fetch('sha256') == proof['sources'].fetch(public_source).fetch('sha256'),
             'build frozen or derived compiler source differs')
    records = proof['sources'].values + proof['tools'].values + proof['originalInputs'].values + proof['sealedInputs'].values + proof['releaseInputs'].values +
      %w[swiftCompiler rustCompiler sdkSettings].map { |key| proof.fetch(key) }
    records.each do |input|
      require!(input.is_a?(Hash) && input.keys.sort == %w[identity path sha256] && file_record(input.fetch('path'), digest: input.fetch('sha256')) == input,
               'build input or role bytes changed')
    end
    proof['tools'].each_value { |input| Staging.record!(input.fetch('path'), expected: input, internal: true) }
    require!(proof['swiftCompiler'] == file_record(File.realpath(SWIFTC), digest: SWIFT_SHA) &&
             proof['rustCompiler'] == file_record(RUSTC, digest: RUST_SHA) &&
             proof['sdkSettings'] == file_record(File.join(File.realpath(SDK), 'SDKSettings.json'), digest: SDK_SHA), 'build toolchain differs')
    audit_command_records!(proof.fetch('commands'), build_root)
    require!(source_proof!(commands) == provenance && file_record(path, digest: expected_sha) == record, 'build audit source or manifest changed')
    proof
  rescue JSON::ParserError, JSON::NestingError, KeyError, TypeError, NoMethodError, Staging::Refused, SystemCallError
    raise Refused, 'build evidence audit refused (no installation authority)'
  end

  def self.build!
    # Refuse injected loaders before invoking any subprocess. This is a build,
    # not a bypass for privileged or live invocation.
    require!(ENV.keys.none? { |key| key.match?(/\A(?:RUBY|GEM|BUNDLE|DYLD_|LD_|GIT_CONFIG|RUSTC_WRAPPER|RUSTFLAGS|SWIFT_)/) }, 'inherited build loader refused')
    root = Dir.mktmpdir('beluga-microphone-v9-guards.', '/private/tmp'); File.chmod(0700, root)
    command_directory = File.join(root, 'commands'); Dir.mkdir(command_directory, 0700)
    commands = Commands.new(command_directory)
    provenance = source_proof!(commands)
    swift = file_record(File.realpath(SWIFTC), digest: SWIFT_SHA)
    rust = file_record(RUSTC, digest: RUST_SHA)
    sdk = file_record(File.join(File.realpath(SDK), 'SDKSettings.json'), digest: SDK_SHA)
    public_source = ROOT + '/iOS/opensteamer/scripts/physical-blackhole-microphone-probe.swift'
    sources = source_paths.uniq.sort.to_h { |path| [path, file_record(path)] }
    dependencies = sealed_inputs!
    original_inputs, sealed_inputs, release_inputs = Staging.stage!(root, dependencies)
    reused_tools = reused_tools!
    # The root sealer receives this exact byte record, not instructions or
    # command paths. The UID501 gate independently fixes dependency byte pins.
    gate_keys = {
      'host_gate_sha256' => 'tools/opensteamer-microphone-v9-host-gate.rb',
      'controller_sha256' => 'tools/product/opensteamer-host-v91-cutover-controller.rb',
      'inputs_sha256' => 'tools/product/opensteamer-host-successor-inputs.rb',
      'contract_sha256' => 'tools/product/opensteamer-host-successor-contract.rb',
      'readiness_sha256' => 'tools/product/verify-v91-secondary-viewer-readiness.sh',
      'switch_audio_sha256' => 'tools/observers/SwitchAudioSource',
      'lock_sha256' => 'tools/observers/probe-worldwide-lock-v23',
      'topology_sha256' => 'tools/observers/verify-live-display-topology-v23'
    }
    gate_inputs_path = File.join(root, 'gate_inputs.txt')
    gate_text = "schema=opensteamer.microphone-v9-gate-inputs.v1\n" + gate_keys.map { |key, path| "#{key}=#{sealed_inputs.fetch(path).fetch('sha256')}\n" }.join
    File.open(gate_inputs_path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(gate_text); file.flush; file.fsync }
    sealed_inputs['tools/gate_inputs.txt'] = file_record(gate_inputs_path)
    require!(sources.fetch(DECODER)['sha256'] == DECODER_SHA && sources.fetch(MONITOR)['sha256'] == MONITOR_SHA, 'frozen native sources differ')
    binaries = { 'worker' => File.join(root, 'transaction'), 'idleHelper' => File.join(root, 'idle-helper'),
                 'bothOrderProbe' => File.join(root, 'public-proof'), 'routeGuardian' => File.join(root, 'route-guardian') }
    # The public source copy remains in the current source closure, even though
    # the three unchanged Swift binaries retain the pinned historical recipe.
    capsule = Staging::Capsule.new(root)
    public_directory = capsule.directory!('public')
    public_main = File.join(public_directory, 'main.swift')
    sources[public_main] = capsule.copy!(sources.fetch(public_source), 'public/main.swift')
    REUSED_ROLES.each do |role, name|
      capsule.copy!(reused_tools.fetch('tools').fetch(role), name)
    end
    capsule.fence!; capsule.close; capsule = nil
    commands.run(*compile_recipes(root).fetch(0))
    require!(source_proof!(commands) == provenance && sources.all? { |path, record| file_record(path) == record }, 'source changed during native build')
    Staging.audit!(root, sealed_inputs!, original_inputs, sealed_inputs, release_inputs)
    require!(reused_tools! == reused_tools, 'reused build changed during native build')
    require!(file_record(File.realpath(SWIFTC)) == swift && file_record(RUSTC) == rust &&
             file_record(File.join(File.realpath(SDK), 'SDKSettings.json')) == sdk, 'toolchain changed during native build')
    proof = provenance.merge('schema' => 'opensteamer.microphone-v9.native-guard-build.v2', 'deploymentAuthority' => false,
                             'liveQueriesPerformed' => false, 'sources' => sources, 'swiftCompiler' => swift,
                             'rustCompiler' => rust, 'sdkSettings' => sdk, 'commands' => commands.records,
                             'originalInputs' => original_inputs, 'sealedInputs' => sealed_inputs, 'releaseInputs' => release_inputs,
                             'reusedTools' => reused_tools, 'tools' => binaries.to_h { |role, path| [role, file_record(path)] })
    path = File.join(root, 'build-proof.json')
    File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(JSON.pretty_generate(proof) + "\n"); file.flush; file.fsync }
    puts JSON.generate({ 'buildProof' => path, 'buildProofSHA256' => Digest::SHA256.file(path).hexdigest,
                         'deploymentAuthority' => false, 'liveQueriesPerformed' => false })
    path
  rescue Staging::Refused
    raise Refused, 'internal build input staging refused'
  ensure
    capsule&.close
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise BelugaMicrophoneV9GuardBuild::Refused, 'usage: build-opensteamer-microphone-v9-guards.rb --build-native-guards' unless ARGV == ['--build-native-guards']
    BelugaMicrophoneV9GuardBuild.build!
  rescue BelugaMicrophoneV9GuardBuild::Refused => error
    warn 'microphone-v9-native-build: ' + error.message
    exit 1
  end
end
