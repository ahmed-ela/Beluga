#!/usr/bin/env ruby
# Original-UID build only. No audio query, installer, privilege or live service call.
require 'digest'
require 'fileutils'
require 'fiddle'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'opensteamer-microphone-v9-host-gate'

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
    require!(path.start_with?('/') && File.realpath(path) == path, 'build input alias refused')
    before = File.lstat(path)
    require!(before.file? && before.uid == 501 && before.nlink == 1 &&
             (before.mode & 07022).zero? && before.size.between?(1, 256 * 1024 * 1024), 'build input metadata refused')
    sha = Digest::SHA256.file(path).hexdigest
    require!(identity(File.lstat(path)) == identity(before) && (!digest || sha == digest), 'build input changed or digest differs')
    { 'path' => path, 'sha256' => sha, 'identity' => identity(before) }
  rescue SystemCallError
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

  def self.source_paths
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

  def self.compile_recipes(root)
    helper = ROOT + '/macOS/scripts/microphone-v9-idle-proof'
    [
      [RUSTC, '--edition=2021', '-O', '-D', 'warnings', ROOT + '/macOS/scripts/opensteamer-microphone-v9-transaction.rs', '-o', root + '/transaction'],
      [SWIFTC, '-sdk', SDK, '-swift-version', '6', '-warnings-as-errors', '-O', DECODER,
       helper + '/BelugaMicrophoneIdleProof.swift', helper + '/BelugaMicrophoneEndpointContract.swift', helper + '/main.swift',
       '-framework', 'CoreAudio', '-framework', 'CryptoKit', '-o', root + '/idle-helper'],
      [SWIFTC, '-sdk', SDK, '-swift-version', '5', '-O', '-D', 'BELUGA_MICROPHONE_V9_ORACLE', root + '/public/main.swift', DECODER,
       '-framework', 'CoreAudio', '-framework', 'AudioToolbox', '-framework', 'CryptoKit', '-o', root + '/public-proof'],
      [SWIFTC, '-sdk', SDK, '-swift-version', '6', '-warnings-as-errors', '-O', MONITOR,
       '-framework', 'CoreAudio', '-o', root + '/route-guardian']
    ]
  end

  def self.audit_recipes!(proof, root)
    require!(proof['sources'].is_a?(Hash) && proof['sources'].keys.sort == (source_paths + [root + '/public/main.swift']).sort,
             'build exact source closure differs')
    recipes = compile_recipes(root)
    commands = proof['commands']
    require!(commands.is_a?(Array) && commands.size.between?(4, 40), 'build command evidence extent differs')
    compiler_commands = commands.select { |command| command.is_a?(Hash) && command['argv'].is_a?(Array) && [RUSTC, SWIFTC].include?(command['argv'][0]) }
    require!(compiler_commands.map { |command| command['argv'] } == recipes, 'build exact ordered compiler recipes differ')
    require!(commands.all? { |command| command.is_a?(Hash) && command['argv'].is_a?(Array) &&
             (recipes.include?(command['argv']) || (command['argv'][0] == '/usr/bin/git' && command['argv'][1] == '-C' &&
             [ROOT, PRODUCT].include?(command['argv'][2]))) }, 'build non-recipe command refused')
    true
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
    bytes = File.binread(path)
    require!(file_record(path, digest: expected_sha) == record && bytes.dup.force_encoding('UTF-8').valid_encoding?, 'build proof changed during read')
    proof = JSON.parse(bytes, object_class: UniqueObject, create_additions: false, max_nesting: 16, allow_nan: false)
    expected_keys = %w[productCommit productTree guardToolingCommit guardToolingTree schema deploymentAuthority liveQueriesPerformed sources swiftCompiler rustCompiler sdkSettings commands sealedInputs tools]
    require!(proof.is_a?(Hash) && proof.keys.sort == expected_keys.sort && proof['schema'] == 'opensteamer.microphone-v9.native-guard-build.v1' &&
             proof['deploymentAuthority'] == false && proof['liveQueriesPerformed'] == false, 'build proof schema/authority refused')
    provenance = source_proof!(commands)
    require!(provenance.all? { |key, value| proof[key] == value }, 'build source provenance differs')
    build_root = File.dirname(path)
    require!(build_root.start_with?('/private/tmp/beluga-microphone-v9-guards.') && File.basename(path) == 'build-proof.json', 'build output namespace refused')
    audit_recipes!(proof, build_root)
    require!(proof['tools'].is_a?(Hash) && proof['tools'].keys.sort == %w[bothOrderProbe idleHelper routeGuardian worker], 'build role set differs')
    { 'worker' => 'transaction', 'idleHelper' => 'idle-helper', 'bothOrderProbe' => 'public-proof', 'routeGuardian' => 'route-guardian' }.each do |role, name|
      input = proof['tools'].fetch(role)
      require!(input['path'] == File.join(build_root, name) && input['identity'].is_a?(Array) &&
               input['identity'][4].is_a?(Integer) && input['identity'][4] & 0111 != 0, 'compiled build role path/mode differs')
    end
    inputs = sealed_inputs!
    require!(proof['sealedInputs'].is_a?(Hash) && proof['sealedInputs'].keys.sort == (inputs.keys + ['tools/gate_inputs.txt']).sort &&
             inputs.all? { |relative, input| proof['sealedInputs'][relative] == input }, 'build sealed dependency records differ')
    require!(proof['sources'].is_a?(Hash) && proof['sources'].size.between?(8, 32) && proof['sources'].all? { |source, input|
      input.is_a?(Hash) && input['path'] == source &&
        (source == DECODER || source == MONITOR || source == File.join(build_root, 'public/main.swift') ||
         source.start_with?(ROOT + '/macOS/scripts/', ROOT + '/iOS/opensteamer/scripts/'))
    }, 'build source paths refused')
    public_source = ROOT + '/iOS/opensteamer/scripts/physical-blackhole-microphone-probe.swift'
    require!(proof['sources'].fetch(DECODER).fetch('sha256') == DECODER_SHA && proof['sources'].fetch(MONITOR).fetch('sha256') == MONITOR_SHA &&
             proof['sources'].fetch(File.join(build_root, 'public/main.swift')).fetch('sha256') == proof['sources'].fetch(public_source).fetch('sha256'),
             'build frozen or derived compiler source differs')
    records = proof['sources'].values + proof['tools'].values + proof['sealedInputs'].values +
      %w[swiftCompiler rustCompiler sdkSettings].map { |key| proof.fetch(key) }
    records.each do |input|
      require!(input.is_a?(Hash) && input.keys.sort == %w[identity path sha256] && file_record(input.fetch('path'), digest: input.fetch('sha256')) == input,
               'build input or role bytes changed')
    end
    require!(proof['swiftCompiler'] == file_record(File.realpath(SWIFTC), digest: SWIFT_SHA) &&
             proof['rustCompiler'] == file_record(RUSTC, digest: RUST_SHA) &&
             proof['sdkSettings'] == file_record(File.join(File.realpath(SDK), 'SDKSettings.json'), digest: SDK_SHA), 'build toolchain differs')
    require!(proof['commands'].is_a?(Array) && proof['commands'].size.between?(4, 40), 'build command evidence extent differs')
    proof['commands'].each_with_index do |command, index|
      require!(command.is_a?(Hash) && command.keys.sort == %w[argv exitStatus pid stderr stdout termSignal timedOutOrLogBound] &&
               command['timedOutOrLogBound'] == false && command['exitStatus'] == 0 && command['termSignal'].nil? &&
               command['pid'].is_a?(Integer) && command['pid'].positive? && command['argv'].is_a?(Array) &&
               !command['argv'].empty? && command['argv'].all? { |item| item.is_a?(String) && item.bytesize.between?(1, 8192) && item.ascii_only? }, 'build command result differs')
      %w[stdout stderr].each do |channel|
        input = command.fetch(channel); before = File.lstat(input.fetch('path'))
        require!(input.keys.sort == %w[identity path sha256] && input['path'] == File.join(build_root, 'commands', format('%03d.%s', index + 1, channel)) &&
                 File.realpath(input['path']) == input['path'] && before.file? && before.uid == 501 &&
                 before.nlink == 1 && before.mode & 07777 == 0600 && before.size <= MAX_LOG_BYTES &&
                 identity(before) == input['identity'] && Digest::SHA256.file(input['path']).hexdigest == input['sha256'] &&
                 identity(File.lstat(input['path'])) == identity(before), 'build command log changed')
      end
    end
    require!(source_proof!(commands) == provenance && file_record(path, digest: expected_sha) == record, 'build audit source or manifest changed')
    proof
  rescue JSON::ParserError, JSON::NestingError, KeyError, TypeError, NoMethodError, SystemCallError
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
    sealed_inputs = sealed_inputs!
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
    recipes = compile_recipes(root)
    commands.run(*recipes[0])
    commands.run(*recipes[1])
    # The existing large standalone probe has top-level code. Preserve exact
    # byte identity while giving swiftc the required main.swift filename.
    public_directory = File.join(root, 'public'); Dir.mkdir(public_directory, 0700)
    public_main = File.join(public_directory, 'main.swift'); FileUtils.cp(public_source, public_main)
    require!(Digest::SHA256.file(public_main).hexdigest == sources[public_source]['sha256'], 'standalone main copy differs')
    sources[public_main] = file_record(public_main, digest: sources.fetch(public_source).fetch('sha256'))
    commands.run(*recipes[2])
    commands.run(*recipes[3])
    require!(source_proof!(commands) == provenance && sources.all? { |path, record| file_record(path) == record }, 'source changed during native build')
    require!(sealed_inputs.all? { |_relative, record| file_record(record.fetch('path')) == record }, 'sealed observer dependencies changed during native build')
    require!(file_record(File.realpath(SWIFTC)) == swift && file_record(RUSTC) == rust &&
             file_record(File.join(File.realpath(SDK), 'SDKSettings.json')) == sdk, 'toolchain changed during native build')
    proof = provenance.merge('schema' => 'opensteamer.microphone-v9.native-guard-build.v1', 'deploymentAuthority' => false,
                             'liveQueriesPerformed' => false, 'sources' => sources, 'swiftCompiler' => swift,
                             'rustCompiler' => rust, 'sdkSettings' => sdk, 'commands' => commands.records,
                             'sealedInputs' => sealed_inputs,
                             'tools' => binaries.to_h { |role, path| [role, file_record(path)] })
    path = File.join(root, 'build-proof.json')
    File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(JSON.pretty_generate(proof) + "\n"); file.flush; file.fsync }
    puts JSON.generate({ 'buildProof' => path, 'buildProofSHA256' => Digest::SHA256.file(path).hexdigest,
                         'deploymentAuthority' => false, 'liveQueriesPerformed' => false })
    path
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
