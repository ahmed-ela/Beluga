# frozen_string_literal: true
# UID501 observer only. The native parent owns admission, sealed bytes, deadlines,
# process groups and journal authority. Requiring this file performs no live query.
require 'digest'
require 'fcntl'
require 'json'
require 'open3'

module BelugaMicrophoneV9HostGate
  class Refused < StandardError; end
  SCHEMA = 'opensteamer.microphone-v9-host-gate.v1'
  PREFIX = '/Library/Application Support/opensteamer/microphone-v9-executables'
  NAMESPACE = /\Adriver-microphone-v9-[a-z0-9]+(?:-[a-z0-9]+)*\z/
  PRODUCT_PINS = {
    'opensteamer-host-v91-cutover-controller.rb' => 'd390402ae8a7f824ec9e98c46dc09458dc860818e39d773c3cc16aba1c914a74',
    'opensteamer-host-successor-inputs.rb' => '22dd757c4465118b2129275134ac136b4a0e8869190d5f90892e4dfe81cc39e0',
    'opensteamer-host-successor-contract.rb' => 'a5ee8c492257f4869bbc48ad8f30d06f13ac2c59faaf7e982a33eaaaa8a76bfb',
    'verify-v91-secondary-viewer-readiness.sh' => 'b1de7e579df9087ce1d8ed761539e4c74522f3f23c02d95e6f0385fb66c2e14d'
  }.freeze
  OBSERVER_PINS = {
    'SwitchAudioSource' => '9a29148a58b91c6ac13281b3cc1915922bdadd00ab09b3267271e5925d52fb64',
    'probe-worldwide-lock-v23' => '602c4578dcaec75629126d799056591dd0cea80c2f1ccaae5d91b0c341867e4f',
    'verify-live-display-topology-v23' => '1502e07358f2316f4dee1fb12ce380cc5e9588cd6393ea3f34656ab80e9db292'
  }.freeze
  HOST_ARTIFACT = '/Volumes/t7/beluga-microphone-matching-host.GVm1ZJ'
  PROFILE = HOST_ARTIFACT + '/release-profile.json'
  PROFILE_SHA = '3402737c0a228dd5a9485da469620384ccd00a9cef14650577a36f0bcf15d1a7'
  HOST_NAMESPACE = 'host-microphone-v9-001'
  RUNTIME = '/Users/ahmed/Library/Application Support/opensteamer'
  POINTER = RUNTIME + '/active-paired-host-update-' + HOST_NAMESPACE
  HISTORY = RUNTIME + '/paired-host-updates-' + HOST_NAMESPACE
  LIVE_APP = '/Applications/opensteamer Host.app'
  LIVE_EXE = LIVE_APP + '/Contents/MacOS/CaptureServer'
  LIVE_FRAMEWORK = LIVE_APP + '/Contents/Frameworks/LiveKitWebRTC.framework/Versions/A/LiveKitWebRTC'
  LIVE_INFO = LIVE_APP + '/Contents/Info.plist'
  PLIST = '/Users/ahmed/Library/LaunchAgents/org.example.opensteamer.worldwide.plist'
  LOCK_DIR = '/Users/ahmed/Library/Application Support/com.elamin.AudioStreamer.CaptureServer.runtime'
  LOCK = LOCK_DIR + '/worldwide-host.lock'
  LOG = '/var/tmp/opensteamer-worldwide-host.log'
  LABEL = 'gui/501/org.example.opensteamer.worldwide'
  BYTE_PINS = {
    'host_executable_sha256' => 'b427aa2fee0807339bf7cd59d3629c8f4110d0170481d0f35a77a7f0c45e4a70',
    'host_framework_sha256' => 'a326b18d2c6730e87dbd8134ab99283f6a0bd4cb3c0e7ab4d22c330134a4e59b',
    'host_info_plist_sha256' => '9c6568c97ef11321edc1cc53a5fc070c491ea713a872fb6b119f777ce34e8b55',
    'host_launch_plist_sha256' => 'e8242cfa600bb5e62695cd954bcf59ce76a3884c5d4394accef4215ec642ee7a'
  }.freeze
  REQUEST_KEYS = %w[schema namespace nonce caller_uid producer_commit producer_tree product_commit product_tree artifact_root artifact_manifest_sha256 artifact_binding_sha256 artifact_entry_sha256 artifact_closure_sha256 producer_request_sha256 driver_tree_sha256 driver_executable_sha256 package_sha256 guard_tooling_root guard_tooling_commit guard_tooling_tree worker_sha256 idle_helper_sha256 both_order_probe_sha256 route_guardian_sha256 fresh_binding_sha256 host_profile_path host_profile_sha256 host_handoff_sha256 host_payload_sha256 host_executable_sha256 host_framework_sha256 host_info_plist_sha256 host_pid host_start_identity_sha256 host_nonce host_lock_device host_lock_inode host_launch_plist_sha256 predecessor_driver_tree_sha256 predecessor_driver_executable_sha256 predecessor_driver_instance predecessor_driver_device predecessor_driver_inode input_uid output_uid system_output_uid normal_restart_budget rollback_restart_budget timeout_seconds committed_host_pointer_path committed_host_pointer_sha256 committed_host_result_path committed_host_result_sha256 committed_host_readiness_path committed_host_readiness_sha256 committed_host_journal_path committed_host_journal_sha256 host_launchd_runs host_display_identity_sha256].freeze
  OUTPUT_KEYS = %w[schema mode namespace nonce observed_at_unix_ms host_present host_pid host_launchd_runs host_start_identity_sha256 host_nonce host_lock_device host_lock_inode host_display_identity_sha256 display_headless readiness manager_generation host_executable_sha256 host_framework_sha256 host_info_plist_sha256 host_launch_plist_sha256 input_uid output_uid system_output_uid routes_identity_sha256 session_quiescent session_log_device session_log_inode session_log_size session_log_reset_offset session_log_sha256 session_log_tail_sha256 committed_host_terminal].freeze
  MODES = %w[candidate-present host-absent host-ready].freeze
  ROUTES = { 'input' => 'BlackHole2ch_UID', 'output' => 'BuiltInSpeakerDevice', 'system' => 'BuiltInSpeakerDevice' }.freeze
  MAX_BYTES = 65_536
  MAX_TAIL_BYTES = 32 * 1024 * 1024
  TAIL_READ_BYTES = 1024 * 1024
  # Pinned macOS SDK sys/stat.h: SF_NOUNLINK (rename/delete protection).
  # Only the canonical /Library ancestor carries this exact system flag.
  LIBRARY_FLAGS = "1048576\n".freeze
  ROOT_METADATA_SCHEMA = 'opensteamer.microphone-v9-root-gate-metadata.v1'
  ROOT_METADATA_KEYS = %w[schema namespace nonce request_sha256 worker_sha256 host_gate_sha256 mode observed_at_unix_ms sequence acl_absent xattrs_empty prefix_identity namespace_identity tools_identity product_identity observers_identity].freeze
  ROOT_METADATA_IDENTITY_KEYS = %w[prefix_identity namespace_identity tools_identity product_identity observers_identity].freeze
  CLI_STAGES = %w[caller request root_metadata sealed_sources product_contract baseline observe source_recheck output unknown].freeze
  MAX_DIAGNOSTIC_BYTES = 2 * 1024 * 1024
  SAFE_ENV = { 'HOME' => '/Users/ahmed', 'USER' => 'ahmed', 'LOGNAME' => 'ahmed',
               'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL' => 'C', 'TMPDIR' => '/private/tmp' }.freeze

  def self.assert!(condition, message)
    raise Refused, message, cause: nil unless condition
  end

  def self.refusal_diagnostic(stage, error)
    stage = 'unknown' unless CLI_STAGES.include?(stage)
    kind = case error
           when Refused then 'Refused'
           when SystemCallError then 'SystemCallError'
           when IOError then 'IOError'
           when ArgumentError then 'ArgumentError'
           when TypeError then 'TypeError'
           when EncodingError then 'EncodingError'
           else 'StandardError'
           end
    message = error.message
    bounded = message.is_a?(String) && message.bytesize <= MAX_DIAGNOSTIC_BYTES
    diagnostic = bounded ? 'hashed' : 'extent_refused'
    digest = Digest::SHA256.hexdigest(bounded ? message.b : 'diagnostic message extent refused')
    "microphone-v9-host-gate: REFUSED stage=#{stage} class=#{kind} diagnostic=#{diagnostic} reason_sha256=#{digest} (no runtime admission; diagnostic contents redacted)"
  end

  def self.sha!(value)
    assert!(value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/), 'digest refused')
  end

  def self.number!(value, zero: false)
    assert!(value.is_a?(String) && value.match?(zero ? /\A(?:0|[1-9][0-9]{0,19})\z/ : /\A[1-9][0-9]{0,19}\z/) &&
            value.to_i <= 18_446_744_073_709_551_615, 'numeric identity refused')
  end

  def self.path!(value)
    assert!(value.is_a?(String) && value.ascii_only? && value.start_with?('/') &&
            !value.end_with?('/') && !value.include?('//') && !value.match?(/[\x00-\x1f\x7f=]/) &&
            value.split('/').none? { |part| %w[. ..].include?(part) }, 'path refused')
  end

  def self.parse_flat(bytes, keys)
    assert!(bytes.is_a?(String) && bytes.bytesize.between?(1, MAX_BYTES) && bytes.ascii_only? && bytes.end_with?("\n"), 'flat record extent refused')
    record = {}
    bytes.lines.each do |line|
      match = /\A([a-z][a-z0-9_]*)=([^\x00-\x1f\x7f=]+)\n\z/.match(line)
      assert!(match && !record.key?(match[1]), 'flat record duplicate or bytes refused')
      record[match[1]] = match[2]
    end
    assert!(record.keys.sort == keys.sort, 'flat record field set refused')
    record
  end

  def self.request!(bytes, expected)
    sha!(expected); assert!(Digest::SHA256.hexdigest(bytes) == expected, 'request bytes differ')
    value = parse_flat(bytes, REQUEST_KEYS)
    assert!(value['schema'] == 'opensteamer.microphone-v9-transaction-request.v1' && value['caller_uid'] == '501', 'request schema/UID refused')
    assert!(NAMESPACE.match?(value['namespace']) && value['namespace'].bytesize <= 64, 'namespace refused')
    value.each do |key, item|
      sha!(item) if key.end_with?('_sha256') || %w[nonce host_nonce].include?(key)
      path!(item) if key.end_with?('_path', '_root')
    end
    %w[host_pid host_lock_device host_lock_inode host_launchd_runs].each { |key| number!(value[key]) }
    assert!(value['host_pid'].to_i <= 2_147_483_647 && value['nonce'] != value['host_nonce'], 'host generation refused')
    BYTE_PINS.each { |key, item| assert!(value[key] == item, 'matching host bytes differ') }
    assert!(value['host_profile_path'] == PROFILE && value['host_profile_sha256'] == PROFILE_SHA && value['committed_host_pointer_path'] == POINTER, 'matching host profile/pointer differs')
    ROUTES.each { |type, uid| assert!(value[type == 'system' ? 'system_output_uid' : type + '_uid'] == uid, 'route UID differs') }
    value.freeze
  end

  def self.identity(stat)
    [stat.dev, stat.ino, stat.uid, stat.gid, stat.mode, stat.nlink, stat.size, stat.mtime.to_i, stat.mtime.nsec, stat.ctime.to_i, stat.ctime.nsec]
  end

  def self.read_fd!(fd)
    io = IO.for_fd(fd, autoclose: false)
    before = io.stat
    assert!(before.file? && before.uid == 0 && before.gid == 0 && (before.mode & 07777) == 0400 && before.nlink == 1 && before.size.between?(1, MAX_BYTES), 'root-held input channel refused')
    assert!((io.fcntl(Fcntl::F_GETFL) & Fcntl::O_ACCMODE) == Fcntl::O_RDONLY, 'input descriptor is not read-only')
    bytes = io.pread(before.size, 0)
    assert!(bytes.bytesize == before.size && identity(before) == identity(io.stat), 'root-held input changed')
    bytes
  rescue SystemCallError, IOError
    raise Refused, 'root-held input unavailable', cause: nil
  end

  def self.root_metadata_paths(namespace)
    assert!(namespace.is_a?(String) && NAMESPACE.match?(namespace) && namespace.bytesize <= 64, 'root metadata namespace refused')
    directory = PREFIX + '/' + namespace
    ROOT_METADATA_IDENTITY_KEYS.zip([PREFIX, directory, directory + '/tools', directory + '/tools/product', directory + '/tools/observers']).to_h.freeze
  end

  def self.root_metadata_identity!(value)
    assert!(value.is_a?(String), 'root metadata identity refused')
    fields = value.split(',', -1)
    assert!(fields.length == 11, 'root metadata identity extent refused')
    fields.each { |field| number!(field, zero: true) }
    tuple = fields.map(&:to_i)
    assert!(tuple[0] > 0 && tuple[1] > 0 && tuple[2] == 0 && tuple[3] == 0 && tuple[4] == 040711 && tuple[5] > 0 &&
      tuple[7] <= 9_223_372_036_854_775_807 && tuple[9] <= 9_223_372_036_854_775_807 &&
      tuple[8] < 1_000_000_000 && tuple[10] < 1_000_000_000, 'root metadata identity policy refused')
    tuple.freeze
  end

  def self.root_metadata!(bytes, expected, request, request_sha:, mode:)
    sha!(expected); sha!(request_sha)
    assert!(Digest::SHA256.hexdigest(bytes) == expected, 'root metadata bytes differ')
    value = parse_flat(bytes, ROOT_METADATA_KEYS)
    assert!(value['schema'] == ROOT_METADATA_SCHEMA && MODES.include?(mode) && value['mode'] == mode &&
      value['namespace'] == request['namespace'] && value['nonce'] == request['nonce'] &&
      value['request_sha256'] == request_sha && value['worker_sha256'] == request['worker_sha256'] &&
      value['acl_absent'] == 'true' && value['xattrs_empty'] == 'true', 'root metadata binding refused')
    %w[nonce request_sha256 worker_sha256 host_gate_sha256].each { |key| sha!(value[key]) }
    number!(value['observed_at_unix_ms']); number!(value['sequence'])
    assert!(value['sequence'].to_i <= 64, 'root metadata sequence refused')
    age = (Time.now.to_r * 1000).to_i - value['observed_at_unix_ms'].to_i
    assert!(age.between?(0, 5000), 'root metadata freshness refused')
    # The native owner pins this exact sealed script independently. The proof
    # cannot bind a different Ruby generation merely by supplying its digest.
    read_file!(__FILE__, value['host_gate_sha256'], owner: 0, modes: [0444])
    root_metadata_paths(request['namespace']).to_h do |key, path|
      [path, root_metadata_identity!(value.fetch(key))]
    end.freeze
  end

  def self.read_root_metadata_fd!(expected, request, request_sha:, mode:)
    root_metadata!(read_fd!(6), expected, request, request_sha: request_sha, mode: mode)
  ensure
    # This authority channel is never inherited by observer grandchildren.
    begin
      IO.for_fd(6, autoclose: false).close
    rescue SystemCallError, IOError
      nil
    end
  end

  def self.read_file!(path, sha, owner:, modes:)
    path!(path); sha!(sha); assert!(File.realpath(path) == path, 'file alias refused')
    before = File.lstat(path)
    assert!(before.file? && before.uid == owner && (owner != 0 || before.gid == 0) && before.nlink == 1 && modes.include?(before.mode & 07777) && before.size.between?(1, 2 * 1024 * 1024), 'file metadata refused')
    bytes = File.open(path, File::RDONLY | File::NOFOLLOW) do |io|
      assert!(identity(io.stat) == identity(before), 'file changed before read')
      data = io.read(before.size + 1)
      assert!(identity(io.stat) == identity(before), 'file changed during read')
      data
    end
    assert!(identity(File.lstat(path)) == identity(before) && Digest::SHA256.hexdigest(bytes) == sha, 'file bytes changed')
    [bytes, identity(before)]
  rescue SystemCallError
    raise Refused, 'pinned file unavailable', cause: nil
  end

  # AudioDeviceIDs are generation-local. Require the exact UID/type and a real
  # current device identity; compare the whole records again within this call.
  class Unique < Hash
    def []=(key, value)
      BelugaMicrophoneV9HostGate.assert!(!key?(key), 'route duplicate refused')
      super
    end
  end
  def self.route!(bytes, type)
    assert!(bytes.bytesize <= 4096 && bytes.dup.force_encoding('UTF-8').valid_encoding?, 'route record extent refused')
    value = JSON.parse(bytes, object_class: Unique, create_additions: false)
    assert!(value.is_a?(Hash) && value.keys.sort == %w[id name type uid] && value.values.all? { |item| item.is_a?(String) }, 'route fields refused')
    assert!(value['type'] == type && value['uid'] == ROUTES.fetch(type) && !value['name'].empty? && !value['name'].match?(/[\x00-\x1f\x7f]/), 'route type/UID refused')
    number!(value['id']); assert!(value['id'].to_i <= 4_294_967_295, 'route device ID refused')
    value.freeze
  rescue JSON::ParserError, EncodingError
    raise Refused, 'route JSON refused', cause: nil
  end

  def self.routes_fingerprint(routes)
    # Exact MirrorLoopbackPCM.defaultFingerprint representation, including NULs.
    Digest::SHA256.hexdigest(%w[input output system].map { |type| routes.fetch(type).fetch('uid') }.join("\0"))
  end

  def self.output!(value, request)
    assert!(value.keys.sort == OUTPUT_KEYS.sort && value['schema'] == SCHEMA && MODES.include?(value['mode']) &&
            value['namespace'] == request['namespace'] && value['nonce'] == request['nonce'], 'observed record binding refused')
    number!(value['observed_at_unix_ms'])
    BYTE_PINS.each { |key, item| assert!(value[key] == item, 'observed byte pin refused') }
    ROUTES.each { |type, uid| assert!(value[type == 'system' ? 'system_output_uid' : type + '_uid'] == uid, 'observed route UID refused') }
    sha!(value['routes_identity_sha256'])
    assert!(value['routes_identity_sha256'] == Digest::SHA256.hexdigest(ROUTES.values.join("\0")) &&
            value['session_quiescent'] == 'true' && value['committed_host_terminal'] == 'COMMITTED_CANDIDATE', 'observed quiescence refused')
    %w[session_log_device session_log_inode session_log_size].each { |key| number!(value[key]) }
    number!(value['session_log_reset_offset'], zero: true)
    %w[session_log_sha256 session_log_tail_sha256].each { |key| sha!(value[key]) }
    assert!(value['session_log_reset_offset'].to_i < value['session_log_size'].to_i, 'session boundary extent refused')
    if value['mode'] == 'host-absent'
      expected = { 'host_present' => 'false', 'readiness' => 'false', 'display_headless' => 'true', 'host_pid' => '0', 'host_launchd_runs' => '0',
                   'host_start_identity_sha256' => 'none', 'host_nonce' => 'none', 'host_lock_device' => '0', 'host_lock_inode' => '0',
                   'host_display_identity_sha256' => 'none', 'manager_generation' => 'none' }
      assert!(expected.all? { |key, item| value[key] == item }, 'absent generation sentinel refused')
    else
      assert!(value['host_present'] == 'true' && value['readiness'] == 'true' && value['display_headless'] == 'false', 'present generation proof refused')
      %w[host_pid host_launchd_runs host_lock_device host_lock_inode].each { |key| number!(value[key]) }
      assert!(value['host_pid'].to_i <= 2_147_483_647, 'observed PID refused')
      %w[host_start_identity_sha256 host_nonce host_display_identity_sha256].each { |key| sha!(value[key]) }
      number!(value['manager_generation'], zero: true)
    end
    value
  end

  class Commands
    attr_reader :deadline
    def initialize(tools, root_metadata: nil)
      @tools = tools; @root_metadata = root_metadata; @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
      namespace = File.basename(File.dirname(tools))
      @root_metadata_paths = tools == PREFIX + '/' + namespace + '/tools' ?
        BelugaMicrophoneV9HostGate.root_metadata_paths(namespace).values.freeze : [].freeze
    end

    def root_metadata_identity!(path)
      gate = BelugaMicrophoneV9HostGate
      gate.assert!(@root_metadata.is_a?(Hash) && @root_metadata.frozen? &&
        @root_metadata.keys.sort == @root_metadata_paths.sort && @root_metadata.key?(path), 'root metadata proof missing')
      stat = File.lstat(path)
      gate.assert!(File.realpath(path) == path && stat.directory? && stat.uid == 0 && stat.gid == 0 &&
        (stat.mode & 07777) == 0711 && gate.identity(stat) == @root_metadata.fetch(path), 'root metadata directory identity changed')
      @root_metadata.fetch(path)
    end

    def sealed_root_metadata!
      BelugaMicrophoneV9HostGate.assert!(@root_metadata_paths.length == 5, 'root metadata tools role refused')
      @root_metadata_paths.each { |path| root_metadata_identity!(path) }
    end

    def allowed!(argv)
      gate = BelugaMicrophoneV9HostGate
      command, *args = argv
      allowed = case command
      when '/bin/launchctl' then args == ['print', LABEL]
      when '/usr/bin/pgrep' then args == ['-x', 'CaptureServer']
      when '/bin/ps' then args.length.between?(4, 5) && args[0] == '-p' && args[1].match?(/\A[1-9][0-9]*\z/) &&
                            [ ['-o', 'lstart='], ['-ww', '-o', 'command='] ].include?(args.drop(2))
      when '/usr/bin/codesign' then args.last.to_s.match?(/\A\+[1-9][0-9]*\z/) &&
                                     [%w[--verify], %w[--display --verbose=4]].include?(args[0...-1])
      when '/usr/sbin/lsof' then args[0, 2] == ['-a', '-p'] && args[2].to_s.match?(/\A[1-9][0-9]*\z/) &&
                                 [%w[-Fn], %w[-d txt -Fn]].include?(args.drop(3))
      when '/bin/ls' then args.length == 2 && args[0] == '-lde' && metadata_path?(args[1])
      when '/usr/bin/stat' then args.length == 3 && args[0, 2] == ['-f', '%f'] && metadata_path?(args[2])
      when '/usr/bin/xattr' then args.length == 1 && metadata_path?(args[0])
      when @tools + '/product/verify-v91-secondary-viewer-readiness.sh' then args == [LIVE_EXE, BYTE_PINS.fetch('host_executable_sha256')]
      when @tools + '/observers/SwitchAudioSource' then ROUTES.keys.any? { |type| args == ['-c', '-t', type, '-f', 'json'] }
      when @tools + '/observers/probe-worldwide-lock-v23' then args == ['--unowned']
      when @tools + '/observers/verify-live-display-topology-v23' then [%w[--headless], %w[--opensteamer-any]].include?(args)
      else false
      end
      gate.assert!(allowed, 'non-observer command refused')
      command.end_with?('/verify-v91-secondary-viewer-readiness.sh') ? ['/bin/zsh', '-f', command, *args] : argv
    end

    def metadata_path?(path)
      BelugaMicrophoneV9HostGate.path!(path)
      ancestors = []; current = @tools
      until current == '/'
        ancestors << current; current = File.dirname(current)
      end
      [LIVE_APP, LIVE_EXE, LIVE_FRAMEWORK, LIVE_INFO, PLIST, LOCK_DIR, LOCK, LOG, POINTER, *ancestors].include?(path) ||
        path.start_with?(HOST_ARTIFACT + '/', HISTORY + '/', @tools + '/')
    end

    def clean_metadata!(path)
      library = nil
      protected_identity = root_metadata_identity!(path) if @root_metadata_paths.include?(path)
      expected_flags = "0\n"
      if path == '/Library'
        library = File.lstat(path)
        BelugaMicrophoneV9HostGate.assert!(File.realpath(path) == path && library.directory? &&
          library.uid == 0 && library.gid == 0 && (library.mode & 07777) == 0755, 'sealed Library ancestor refused')
        expected_flags = LIBRARY_FLAGS
      end
      out, _err, status = run('/bin/ls', '-lde', path)
      BelugaMicrophoneV9HostGate.assert!(status.success? && !out.lines.first.to_s.split.first.to_s.include?('+'), 'sealed node ACL refused')
      unless protected_identity
        out, err, status = run('/usr/bin/xattr', path)
        BelugaMicrophoneV9HostGate.assert!(status.success? && out.empty? && err.empty?, 'sealed node xattrs refused')
      end
      out, _err, status = run('/usr/bin/stat', '-f', '%f', path)
      BelugaMicrophoneV9HostGate.assert!(status.success? && out == expected_flags, 'sealed node flags refused')
      if library
        BelugaMicrophoneV9HostGate.assert!(File.realpath(path) == path &&
          BelugaMicrophoneV9HostGate.identity(File.lstat(path)) == BelugaMicrophoneV9HostGate.identity(library), 'sealed Library identity changed')
      end
      root_metadata_identity!(path) if protected_identity
    end

    def run(*argv, stdin_data: nil, **options)
      BelugaMicrophoneV9HostGate.assert!(options.empty? && (stdin_data.nil? || stdin_data == ''), 'command options refused')
      argv = allowed!(argv)
      input, output = IO.pipe; errors_in, errors_out = IO.pipe
      stdout = ''.b; stderr = ''.b; status = nil; pid = nil
      # Descendants stay in the native owner's process group. On any adapter
      # failure the native owner must terminate that group, even after this PID exits.
      pid = Process.spawn(SAFE_ENV, *argv, unsetenv_others: true, in: File::NULL, out: output, err: errors_out, close_others: true)
      output.close; errors_out.close
      streams = { input => stdout, errors_in => stderr }
      until status && streams.empty?
        BelugaMicrophoneV9HostGate.assert!(Process.clock_gettime(Process::CLOCK_MONOTONIC) < @deadline, 'host observer deadline exceeded')
        IO.select(streams.keys, nil, nil, 0.02)&.first&.each do |stream|
          chunk = stream.read_nonblock(4096, exception: false)
          if chunk.nil? then streams.delete(stream)
          elsif chunk != :wait_readable
            streams.fetch(stream) << chunk
            BelugaMicrophoneV9HostGate.assert!(streams.fetch(stream).bytesize <= 2 * 1024 * 1024, 'observer output bound exceeded')
          end
        end
        status ||= Process.waitpid2(pid, Process::WNOHANG)&.last
      end
      [stdout, stderr, status]
    ensure
      if pid && !status
        begin
          Process.kill('TERM', pid)
          limit = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.25
          status = Process.waitpid2(pid, Process::WNOHANG)&.last
          until status || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= limit
            sleep 0.01; status = Process.waitpid2(pid, Process::WNOHANG)&.last
          end
          unless status then Process.kill('KILL', pid); Process.waitpid(pid) end
        rescue Errno::ESRCH, Errno::ECHILD
          # The native parent still owns/reaps the complete descendant group.
        end
      end
      [input, output, errors_in, errors_out].compact.each { |io| io.close unless io.closed? }
    end
  end

  def self.sealed_sources!(tools, namespace, commands:)
    assert!(tools == PREFIX + '/' + namespace + '/tools' && File.realpath(__FILE__) == tools + '/opensteamer-microphone-v9-host-gate.rb', 'unsealed adapter location refused')
    commands.sealed_root_metadata!
    paths = []; current = tools
    until current == '/'
      paths << current; current = File.dirname(current)
    end
    paths.concat([tools + '/product', tools + '/observers'])
    records = paths.uniq.to_h do |path|
      stat = File.lstat(path)
      allowed_group = path == '/Library/Application Support' ? 80 : 0
      assert!(File.realpath(path) == path && stat.directory? && stat.uid == 0 && stat.gid == allowed_group &&
              [0711, 0755].include?(stat.mode & 07777), 'sealed source ancestor refused')
      commands.clean_metadata!(path)
      [path, identity(stat)]
    end
    own = File.lstat(__FILE__)
    assert!(own.file? && own.uid == 0 && own.gid == 0 && own.nlink == 1 && (own.mode & 07777) == 0444, 'adapter source is not sealed')
    commands.clean_metadata!(__FILE__); records[__FILE__] = identity(own)
    (PRODUCT_PINS.map { |name, sha| [tools + '/product/' + name, sha, [0444]] } +
     OBSERVER_PINS.map { |name, sha| [tools + '/observers/' + name, sha, [0555]] }).each do |path, sha, modes|
      _, record = read_file!(path, sha, owner: 0, modes: modes); records[path] = record
      commands.clean_metadata!(path)
    end
    records.freeze
  end

  def self.committed!(request, observer)
    pointer, pointer_identity = read_file!(POINTER, request.fetch('committed_host_pointer_sha256'), owner: 501, modes: [0600])
    directory = pointer.delete_suffix("\n")
    path!(directory)
    assert!(pointer == directory + "\n" && directory.start_with?(HISTORY + '/') && !directory.delete_prefix(HISTORY + '/').include?('/'), 'committed pointer refused')
    role_names = { 'result' => 'result.txt', 'readiness' => 'commit-safety-proof.txt', 'journal' => 'journal.log' }
    directory_stat = OpenSteamerV91Cutover::Util.directory!(directory, 'committed host evidence', mode: 0700, owner: 501)
    records = { POINTER => pointer_identity, directory => identity(directory_stat) }; text = {}
    role_names.each do |role, name|
      path = directory + '/' + name
      assert!(request.fetch('committed_host_' + role + '_path') == path, 'committed evidence crosslink refused')
      text[role], records[path] = read_file!(path, request.fetch('committed_host_' + role + '_sha256'), owner: 501, modes: [0600])
    end
    states = observer.send(:parse_journal_bytes!, text.fetch('journal'))
    assert!(states.last == 'COMMITTED_V91', 'matching host journal is not committed')
    expected = { 'pid' => request.fetch('host_pid'), 'nonce' => request.fetch('host_nonce'), 'target' => 'candidate',
                 'selected' => '1080x1920@1080x1920 60.00Hz', 'candidate_executable_sha256' => BYTE_PINS.fetch('host_executable_sha256'),
                 'payload_manifest_sha256' => request.fetch('host_payload_sha256'), 'handoff_sha256' => request.fetch('host_handoff_sha256') }
    %w[result readiness].each do |role|
      extra = role == 'result' ? { 'result' => 'pending-terminal', 'terminal_required' => 'CANDIDATE_COMMIT_IRREVERSIBLE,COMMITTED_CANDIDATE' } :
        { 'result' => 'success-pending-terminal', 'terminal_required' => 'COMMITTED_CANDIDATE', 'point_of_no_return' => 'CANDIDATE_COMMIT_IRREVERSIBLE',
          'route_monitor' => 'RESULT notifications=0 teardown=clean input=BlackHole2ch_UID output=BuiltInSpeakerDevice system=BuiltInSpeakerDevice' }
      proof = text.fetch(role).lines.to_h do |line|
        match = /\A([a-z][a-z0-9_]*)=(.+)\n\z/.match(line)
        assert!(match, 'committed proof bytes refused'); [match[1], match[2]]
      end
      assert!(text.fetch(role).lines.size == proof.size && proof == expected.merge(extra), 'committed proof fields refused')
    end
    [pointer, records]
  end

  def self.baseline!(bytes, request)
    value = output!(parse_flat(bytes, OUTPUT_KEYS), request)
    assert!(value['schema'] == SCHEMA && value['mode'] == 'candidate-present' && value['namespace'] == request['namespace'] &&
            value['nonce'] == request['nonce'] && value['host_present'] == 'true' && value['readiness'] == 'true' &&
            value['session_quiescent'] == 'true' && value['committed_host_terminal'] == 'COMMITTED_CANDIDATE', 'initial host fence refused')
    %w[pid launchd_runs start_identity_sha256 nonce lock_device lock_inode display_identity_sha256].each do |key|
      assert!(value['host_' + key] == request['host_' + key], 'initial host fence generation differs')
    end
    value
  end

  def self.ready_baseline!(bytes, request, original)
    value = output!(parse_flat(bytes, OUTPUT_KEYS), request)
    assert!(value['mode'] == 'host-ready' && value['host_pid'] != request['host_pid'] && value['host_nonce'] != request['host_nonce'] &&
            value['host_launchd_runs'] == '1' && value['host_display_identity_sha256'] == request['host_display_identity_sha256'], 'retained ready generation refused')
    assert!(value['session_log_device'] == original['session_log_device'] && value['session_log_inode'] == original['session_log_inode'] &&
            value['session_log_size'].to_i >= original['session_log_size'].to_i &&
            value['session_log_reset_offset'].to_i >= original['session_log_size'].to_i, 'retained ready log generation refused')
    value
  end

  def self.optional_fd!(fd)
    begin
      IO.for_fd(fd, autoclose: false).fcntl(Fcntl::F_GETFD)
    rescue Errno::EBADF
      return nil
    end
    read_fd!(fd)
  end

  # The byte-pinned frozen V91 SessionFence remains the differential reference,
  # not a claimed invocation of this adapter. All admission/stat/hash/prefix/
  # marker/refusal semantics below mirror it. The sole search optimization uses
  # String#index to retain the exact last literal occurrence (including overlaps)
  # rather than repeatedly reverse-scanning every one-MiB window. No global
  # String/File patch, cache, prefix shortcut, or product-source change is used.
  module SessionFenceAdapter
    def self.last_match(window, marker)
      found = nil; cursor = 0
      while (position = window.index(marker, cursor))
        found = position; cursor = position + 1
      end
      found
    end

    def self.observe!(path, pid, nonce, prior: nil, fresh_generation: false,
                      deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20)
      legacy = OpenSteamerV91Cutover
      reference = legacy::SessionFence
      check = lambda do
        legacy::Util.fail!('host session scan monotonic deadline exceeded') unless
          Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      end
      check.call
      legacy::Util.fail!('fresh-generation session fence requires a prior snapshot') if fresh_generation && !prior
      stat = legacy::Util.regular_file!(path, 'host stdout log', owner: Process.euid, links: 1)
      if prior
        legacy::Util.fail!('host stdout log was replaced') unless [stat.dev, stat.ino] == [prior.device, prior.inode]
        legacy::Util.fail!('host stdout log was truncated') if stat.size < prior.size
      end
      online = "Worldwide paired-device availability is online pid=#{pid} nonce=#{nonce}"
      markers = [online, *reference::RESET_MARKERS, *reference::UNSAFE_MARKERS, reference::STOP_MARKER].map(&:b)
      overlap_bytes = markers.map(&:bytesize).max - 1
      offsets = {}; digest = Digest::SHA256.new
      prefix_digest = Digest::SHA256.new if prior
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        opened = file.stat
        legacy::Util.fail!('host stdout log changed while opening') unless
          opened.file? && [opened.dev, opened.ino, opened.nlink] == [stat.dev, stat.ino, 1]
        observed_size = opened.size
        legacy::Util.fail!('host stdout log was truncated') if prior && observed_size < prior.size
        position = 0; overlap = ''.b
        while position < observed_size
          check.call
          count = [reference::READ_CHUNK_BYTES, observed_size - position].min
          chunk = file.pread(count, position)
          legacy::Util.fail!('host stdout log short read') unless chunk.bytesize == count
          digest.update(chunk)
          if prior && position < prior.size
            prefix_digest.update(chunk.byteslice(0, [count, prior.size - position].min))
          end
          window = (overlap + chunk).b
          window_offset = position - overlap.bytesize
          markers.each do |marker|
            found = last_match(window, marker)
            offsets[marker] = window_offset + found if found
          end
          overlap = window.byteslice([window.bytesize - overlap_bytes, 0].max, overlap_bytes)
          position += count
        end
        after = File.lstat(path)
        legacy::Util.fail!('host stdout log changed while reading') unless
          after.file? && [after.dev, after.ino, after.nlink] == [opened.dev, opened.ino, 1] && after.size >= observed_size
        stat = opened
      end
      check.call
      if prior
        legacy::Util.fail!('host stdout log historical bytes changed') unless prefix_digest.hexdigest == prior.digest
      end
      online_offset = offsets[online]
      legacy::Util.fail!('host log lacks pinned generation availability marker') unless online_offset
      reset = reference::RESET_MARKERS.map { |marker| offsets[marker] }.compact.max
      legacy::Util.fail!('host log has no quiescent-session boundary') unless reset
      if prior
        if fresh_generation
          legacy::Util.fail!('host lacks a fresh candidate quiescent-session boundary') unless reset >= prior.size
          legacy::Util.fail!('candidate availability marker precedes its fresh quiescent boundary') unless online_offset > reset
        else
          legacy::Util.fail!('host quiescent-session boundary changed') unless reset == prior.last_reset_offset
        end
      end
      legacy::Util.fail!('host has an authenticated/active peer after quiescent boundary') if
        reference::UNSAFE_MARKERS.any? { |marker| offsets[marker] && offsets[marker] >= reset }
      start_offset = offsets['Starting screen video capture']; stop_offset = offsets[reference::STOP_MARKER]
      legacy::Util.fail!('host screen remains active') if start_offset && start_offset >= reset && (!stop_offset || start_offset > stop_offset)
      reference::Snapshot.new(device: stat.dev, inode: stat.ino, size: stat.size, last_reset_offset: reset, digest: digest.hexdigest)
    rescue Errno::ELOOP, Errno::ENOENT, EOFError => error
      OpenSteamerV91Cutover::Util.fail!("host stdout log cannot be safely opened: #{error.message}")
    end
  end

  # Preserve V91 whole-history hash/prefix/session semantics through the adapter.
  # This is an additional, independently reproducible generation-local digest
  # for the native parent; it never materializes or copies the historical log.
  # Appends beyond the captured extent are allowed, replacement/truncation and
  # short reads are not. The native caller still owns the whole-child deadline.
  def self.session_tail_sha256!(path, snapshot, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20)
    start = snapshot.last_reset_offset; extent = snapshot.size
    assert!(start.is_a?(Integer) && extent.is_a?(Integer) && start >= 0 && start < extent &&
            extent - start <= MAX_TAIL_BYTES, 'session tail extent refused')
    before = File.lstat(path)
    stable = lambda { |stat| [stat.dev, stat.ino, stat.uid, stat.gid, stat.mode, stat.nlink] }
    assert!(before.file? && before.uid == 501 && before.nlink == 1 && (before.mode & 07022).zero? &&
            [before.dev, before.ino] == [snapshot.device, snapshot.inode] && before.size >= extent, 'session tail file identity refused')
    digest = Digest::SHA256.new
    File.open(path, File::RDONLY | File::NOFOLLOW) do |io|
      assert!(stable.call(io.stat) == stable.call(before) && io.stat.size >= extent, 'session tail changed at open')
      position = start
      while position < extent
        assert!(Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline, 'session tail monotonic deadline exceeded')
        count = [TAIL_READ_BYTES, extent - position].min
        bytes = io.pread(count, position)
        assert!(bytes.bytesize == count, 'session tail short read')
        digest.update(bytes); position += count
      end
      after = File.lstat(path); held = io.stat
      assert!(after.file? && after.size >= extent && held.size >= extent &&
              stable.call(after) == stable.call(before) && stable.call(held) == stable.call(before), 'session tail changed during read')
    end
    digest.hexdigest
  rescue SystemCallError, IOError
    raise Refused, 'session tail unavailable', cause: nil
  end

  def self.observe!(mode, request, tools, baseline_bytes, ready_bytes = nil,
                    deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20)
    legacy = OpenSteamerV91Cutover
    observer = legacy::RealHost.new
    observer.define_singleton_method(:helper_path) do |name|
      BelugaMicrophoneV9HostGate.assert!(OBSERVER_PINS.key?(name), 'unsealed helper refused')
      tools + '/observers/' + name
    end
    observer.instance_variable_set(:@candidate_executable_sha, BYTE_PINS.fetch('host_executable_sha256'))
    observer.instance_variable_set(:@post_stop_readiness, tools + '/product/verify-v91-secondary-viewer-readiness.sh')
    committed_before = committed!(request, observer)
    baseline = baseline_bytes && baseline!(baseline_bytes, request)
    assert!(baseline || mode == 'candidate-present', 'initial log fence is required')
    assert!(!ready_bytes || baseline && mode != 'candidate-present', 'retained ready channel is not allowed here')
    ready = ready_bytes && ready_baseline!(ready_bytes, request, baseline)
    pin = ready || baseline
    prior = pin && legacy::SessionFence::Snapshot.new(device: pin['session_log_device'].to_i, inode: pin['session_log_inode'].to_i,
      size: pin['session_log_size'].to_i, last_reset_offset: pin['session_log_reset_offset'].to_i, digest: pin['session_log_sha256'])
    session_pid = ready ? ready['host_pid'].to_i : request['host_pid'].to_i
    session_nonce = ready ? ready['host_nonce'] : request['host_nonce']
    routes = ROUTES.keys.to_h { |type| [type, route!(legacy::Util.capture!(tools + '/observers/SwitchAudioSource', '-c', '-t', type, '-f', 'json'), type)] }
    [[LIVE_EXE, 'host_executable_sha256', 0755], [LIVE_FRAMEWORK, 'host_framework_sha256', 0755],
     [LIVE_INFO, 'host_info_plist_sha256', 0644], [PLIST, 'host_launch_plist_sha256', 0600]].each do |path, key, mode_bits|
      legacy::Util.exact_file!(path, request.fetch(key), 'matching installed host', mode: mode_bits, owner: 501)
    end
    legacy::LaunchContract.verify!(PLIST)
    absent = mode == 'host-absent'
    if absent
      assert!(observer.send(:runtime_absent?), 'host is not absent/headless')
      runtime = nil; manager = 'none'; display = 'none'
      session = SessionFenceAdapter.observe!(LOG, session_pid, session_nonce, prior: prior, deadline: deadline)
    else
      runtime = observer.send(:capture_predecessor_runtime_snapshot!)
      assert!(runtime.pid <= 2_147_483_647, 'current host PID refused')
      start_sha = Digest::SHA256.hexdigest(runtime.start)
      if mode == 'candidate-present'
        actual = [runtime.pid.to_s, runtime.runs.to_s, start_sha, runtime.nonce, *runtime.lock_file[0, 2].map(&:to_s)]
        expected = request.values_at('host_pid', 'host_launchd_runs', 'host_start_identity_sha256', 'host_nonce', 'host_lock_device', 'host_lock_inode')
        assert!(actual == expected, 'committed host generation changed')
      else
        assert!(runtime.pid.to_s != request['host_pid'] && runtime.nonce != request['host_nonce'] && runtime.runs == 1, 'replacement host generation is not fresh')
        if ready
          same = runtime.pid.to_s == ready['host_pid'] && runtime.nonce == ready['host_nonce']
          if same
            actual = [Digest::SHA256.hexdigest(runtime.start), *runtime.lock_file[0, 2].map(&:to_s)]
            assert!(actual == ready.values_at('host_start_identity_sha256', 'host_lock_device', 'host_lock_inode'), 'retained ready process or lock changed')
          else
            assert!(runtime.pid.to_s != ready['host_pid'] && runtime.nonce != ready['host_nonce'], 'next host generation only partly changed')
          end
        end
      end
      observer.send(:verify_dynamic_process!, runtime.pid, expected_start: runtime.start, expected_cdhash: 'a8b4287bbf0299946c21a01f445787f85d82197e')
      display = observer.send(:current_display_mode)
      assert!(display == '1080x1920@1080x1920 60.00Hz', 'display mode changed')
      # Digest the same exact normalized topology bytes in both generations.
      topology = legacy::Util.capture!(tools + '/observers/verify-live-display-topology-v23', '--opensteamer-any')
      display = Digest::SHA256.hexdigest(topology)
      assert!(display == request['host_display_identity_sha256'], 'display identity changed')
      fresh = mode == 'host-ready' && (!ready || runtime.pid.to_s != ready['host_pid'])
      session = SessionFenceAdapter.observe!(LOG, runtime.pid, runtime.nonce, prior: prior, fresh_generation: fresh, deadline: deadline)
      observer.instance_variable_set(:@new_pid, runtime.pid)
      manager = observer.send(:readiness_generation!).to_s
      observer.send(:verify_dynamic_process!, runtime.pid, expected_start: runtime.start, expected_cdhash: 'a8b4287bbf0299946c21a01f445787f85d82197e')
      runtime.assert_same!(observer.send(:capture_predecessor_runtime_snapshot!))
      assert!(Digest::SHA256.hexdigest(legacy::Util.capture!(tools + '/observers/verify-live-display-topology-v23', '--opensteamer-any')) == display, 'display identity changed during observer')
    end
    session = SessionFenceAdapter.observe!(LOG, absent ? session_pid : runtime.pid, absent ? session_nonce : runtime.nonce, prior: session, deadline: deadline)
    tail_sha = session_tail_sha256!(LOG, session, deadline: deadline)
    assert!(observer.send(:runtime_absent?), 'absent host changed during observer') if absent
    final_routes = ROUTES.keys.to_h { |type| [type, route!(legacy::Util.capture!(tools + '/observers/SwitchAudioSource', '-c', '-t', type, '-f', 'json'), type)] }
    assert!(routes == final_routes && committed!(request, observer) == committed_before, 'routes or committed evidence changed')
    value = { 'schema' => SCHEMA, 'mode' => mode, 'namespace' => request['namespace'], 'nonce' => request['nonce'],
      'observed_at_unix_ms' => (Time.now.to_r * 1000).to_i.to_s, 'host_present' => (!absent).to_s,
      'host_pid' => runtime ? runtime.pid.to_s : '0', 'host_launchd_runs' => runtime ? runtime.runs.to_s : '0',
      'host_start_identity_sha256' => runtime ? Digest::SHA256.hexdigest(runtime.start) : 'none', 'host_nonce' => runtime ? runtime.nonce : 'none',
      'host_lock_device' => runtime ? runtime.lock_file[0].to_s : '0', 'host_lock_inode' => runtime ? runtime.lock_file[1].to_s : '0',
      'host_display_identity_sha256' => display, 'display_headless' => absent.to_s, 'readiness' => (!absent).to_s,
      'manager_generation' => manager, 'input_uid' => ROUTES['input'], 'output_uid' => ROUTES['output'], 'system_output_uid' => ROUTES['system'],
      'routes_identity_sha256' => routes_fingerprint(routes), 'session_quiescent' => 'true',
      'session_log_device' => session.device.to_s, 'session_log_inode' => session.inode.to_s, 'session_log_size' => session.size.to_s,
      'session_log_reset_offset' => session.last_reset_offset.to_s, 'session_log_sha256' => session.digest,
      'session_log_tail_sha256' => tail_sha,
      'committed_host_terminal' => 'COMMITTED_CANDIDATE' }.merge(BYTE_PINS)
    output!(value, request)
    OUTPUT_KEYS.map { |key| "#{key}=#{value.fetch(key)}\n" }.join
  end

  def self.cli!(argv)
    stage = 'caller'
    assert!(Process.uid == 501 && Process.euid == 501, 'host gate requires original UID501')
    assert!(ENV.keys.none? { |key| key.match?(/\A(?:RUBY|GEM|BUNDLE|DYLD_|LD_)/) }, 'interpreter loader refused')
    assert!(argv.size == 4 && MODES.any? { |mode| argv[0] == '--' + mode } && argv[1] == '/dev/fd/3', 'usage: sealed host gate --candidate-present|--host-absent|--host-ready /dev/fd/3 SHA ROOT_METADATA_SHA')
    stage = 'request'
    request = request!(read_fd!(3), argv[2]); mode = argv[0].delete_prefix('--')
    stage = 'root_metadata'
    root_metadata = read_root_metadata_fd!(argv[3], request, request_sha: argv[2], mode: mode)
    tools = PREFIX + '/' + request['namespace'] + '/tools'
    commands = Commands.new(tools, root_metadata: root_metadata)
    stage = 'sealed_sources'
    sources = sealed_sources!(tools, request['namespace'], commands: commands)
    stage = 'product_contract'
    Open3.singleton_class.prepend(Module.new { define_method(:capture3) { |*args, **options| commands.run(*args, **options) } })
    require tools + '/product/opensteamer-host-v91-cutover-controller'
    require tools + '/product/opensteamer-host-successor-contract'
    contract = OpenSteamerHostSuccessor::ReleaseContract.new(PROFILE, PROFILE_SHA)
    assert!(contract.namespace == HOST_NAMESPACE, 'successor profile namespace changed')
    OpenSteamerV91Cutover::Pins.bind_contract!(contract)
    stage = 'baseline'
    baseline = mode == 'candidate-present' ? nil : read_fd!(4)
    ready = mode == 'candidate-present' ? nil : optional_fd!(5)
    stage = 'observe'
    result = observe!(mode, request, tools, baseline, ready, deadline: commands.deadline)
    stage = 'source_recheck'
    sources.each { |path, record| assert!(identity(File.lstat(path)) == record, 'sealed dependency identity changed') }
    stage = 'output'
    puts result
    0
  rescue Refused, StandardError => error
    warn refusal_diagnostic(stage, error)
    78
  end
end

exit(BelugaMicrophoneV9HostGate.cli!(ARGV)) if $PROGRAM_NAME == __FILE__
