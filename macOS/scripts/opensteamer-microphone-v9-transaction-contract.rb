# frozen_string_literal: true
# Read-only UID-501 preparation. This file cannot install, signal, or elevate.
require 'digest'
require 'json'
require_relative 'opensteamer-microphone-receipt-binding'

module OpensteamerMicrophoneV9TransactionContract
  class Refusal < StandardError; end
  class UniqueObject < Hash
    def []=(key, value)
      raise Refusal, 'duplicate member' if key?(key)
      super
    end
  end

  SCHEMA = 'opensteamer.microphone-v9-coordinator-request.v1'
  NATIVE_SCHEMA = 'opensteamer.microphone-v9-transaction-request.v1'
  RECORD_SCHEMA = 'opensteamer.microphone-v9-coordinator-verification.v1'
  PRODUCT_COMMIT = '168036d74e08e7b49aad37907cf9b84b5dcc8456'
  PRODUCT_TREE = '044cce09563a0384597e8529565ddff290bd4a6f'
  PRODUCER_COMMIT = 'bc9c9d9a08d8786baf408ed44b35bf3aa3b656e0'
  PRODUCER_TREE = '8cdd075e7e5d6bc0702bfad19ed9ec27cf69fdc6'
  ARTIFACT_ROOT = '/Volumes/t7/beluga-microphone-v9-clean-environment.DgmLSM/production-driver-v9'
  HOST_PROFILE = '/Volumes/t7/beluga-microphone-matching-host.GVm1ZJ/release-profile.json'
  HOST_RUNTIME_ROOT = '/Users/ahmed/Library/Application Support/opensteamer'
  HOST_UPDATE_ROOT = HOST_RUNTIME_ROOT + '/paired-host-updates-host-microphone-v9-001'
  HOST_ACTIVE_POINTER = HOST_RUNTIME_ROOT + '/active-paired-host-update-host-microphone-v9-001'
  ARTIFACT_FILES = {
    'candidate-manifest.txt' => '5080e24749071cdff797bf3eabcf39e6f3537591072d8104c663f5d899729bce',
    'microphone-binding.json' => '4a24017dd968c0c0ca09484475e6c53fd24a4e76fe02ba7cdefd3b61a802ec4e',
    'candidate-entry-inputs.json' => 'bc150676896f9099512c6ac152c86295f2850d6176fe9063e80fb32f6076d9bb',
    'candidate-inputs.json' => 'e7cda45a34741ce93df979274f8d557ce2fcf65412ba00c509ff83a8b8997b63',
    'binding-request.json' => '413f081de312d55063bf8ec0807ff9c901609de67625f6b659bb59a5e847984e',
    'build-invocation.json' => 'def0d216ca58ce52b17778ec2311da3b975faf2f54875953d54f22af88f75794',
    'build-stdout.txt' => '868353d94128d084de43e7d9deb31bb0607ee0cee7c0498d55dbecea9d16cf37',
    'build-stderr.txt' => '7ea6cca8eb1eaf71615ade1c91ddbca711fbe784438eef462c6cc94ff46d4c02',
    'notary-result.json' => 'b257223d6e423c141f760651abff810dab447c4b1bfa5f2dbbf88b58ec5cb58b',
    'verification.txt' => '7f61bdeab8b3df5734e78346efc55891c3cce8d9900530da8e0d558fffd42c49',
    'OpensteamerVirtualMicrophone-v9.pkg' => 'dc5344c6b259d9739a07e2f7d61e2edd976ffe79e2a8d3eda8db234a2788841e'
  }.freeze
  FIXED = {
    'schema' => NATIVE_SCHEMA, 'caller_uid' => '501',
    'producer_commit' => PRODUCER_COMMIT, 'producer_tree' => PRODUCER_TREE,
    'product_commit' => PRODUCT_COMMIT, 'product_tree' => PRODUCT_TREE,
    'artifact_root' => ARTIFACT_ROOT,
    'artifact_manifest_sha256' => ARTIFACT_FILES.fetch('candidate-manifest.txt'),
    'artifact_binding_sha256' => ARTIFACT_FILES.fetch('microphone-binding.json'),
    'artifact_entry_sha256' => ARTIFACT_FILES.fetch('candidate-entry-inputs.json'),
    'artifact_closure_sha256' => ARTIFACT_FILES.fetch('candidate-inputs.json'),
    'producer_request_sha256' => ARTIFACT_FILES.fetch('binding-request.json'),
    'driver_tree_sha256' => '82e2f5c6e71f182020cdf6c002843d1bf68710a7ae9e94481ef4c5ec23f99dcb',
    'driver_executable_sha256' => '6e18a5309200082c5fac9d6bf4130880e09aee25984a6a934a8adcd70dd1fd54',
    'package_sha256' => ARTIFACT_FILES.fetch('OpensteamerVirtualMicrophone-v9.pkg'),
    'host_profile_path' => HOST_PROFILE,
    'host_profile_sha256' => '3402737c0a228dd5a9485da469620384ccd00a9cef14650577a36f0bcf15d1a7',
    'host_handoff_sha256' => '3cc0ef8ea8bdc51375cc2caa901b47dc87b5d75f294259cea1645207aaeefe0d',
    'host_payload_sha256' => 'dd5d41037fb1c750d5915d932b6fbf1875774fa8e35d4d785bb55310508b6972',
    'host_executable_sha256' => 'b427aa2fee0807339bf7cd59d3629c8f4110d0170481d0f35a77a7f0c45e4a70',
    'host_framework_sha256' => 'a326b18d2c6730e87dbd8134ab99283f6a0bd4cb3c0e7ab4d22c330134a4e59b',
    'host_info_plist_sha256' => '9c6568c97ef11321edc1cc53a5fc070c491ea713a872fb6b119f777ce34e8b55',
    'host_launch_plist_sha256' => 'e8242cfa600bb5e62695cd954bcf59ce76a3884c5d4394accef4215ec642ee7a',
    'predecessor_driver_executable_sha256' => '25cd7a39366f0bfcd491cc1509f3f0c79ebe716899342d8feaa8ff9feb57ac4a',
    'input_uid' => 'BlackHole2ch_UID', 'output_uid' => 'BuiltInSpeakerDevice',
    'system_output_uid' => 'BuiltInSpeakerDevice',
    'normal_restart_budget' => '1', 'rollback_restart_budget' => '1'
  }.freeze
  NATIVE_KEYS = %w[schema namespace nonce caller_uid producer_commit producer_tree product_commit product_tree artifact_root artifact_manifest_sha256 artifact_binding_sha256 artifact_entry_sha256 artifact_closure_sha256 producer_request_sha256 driver_tree_sha256 driver_executable_sha256 package_sha256 guard_tooling_root guard_tooling_commit guard_tooling_tree worker_sha256 idle_helper_sha256 both_order_probe_sha256 route_guardian_sha256 fresh_binding_sha256 host_profile_path host_profile_sha256 host_handoff_sha256 host_payload_sha256 host_executable_sha256 host_framework_sha256 host_info_plist_sha256 host_pid host_start_identity_sha256 host_nonce host_lock_device host_lock_inode host_launch_plist_sha256 predecessor_driver_tree_sha256 predecessor_driver_executable_sha256 predecessor_driver_instance predecessor_driver_device predecessor_driver_inode input_uid output_uid system_output_uid normal_restart_budget rollback_restart_budget timeout_seconds committed_host_pointer_path committed_host_pointer_sha256 committed_host_result_path committed_host_result_sha256 committed_host_readiness_path committed_host_readiness_sha256 committed_host_journal_path committed_host_journal_sha256 host_launchd_runs host_display_identity_sha256].freeze
  TOOL_ROLES = %w[worker idleHelper bothOrderProbe routeGuardian].freeze
  TOOL_DIGEST_KEYS = %w[worker_sha256 idle_helper_sha256 both_order_probe_sha256 route_guardian_sha256].freeze
  BUNDLE_NODES = [
    ['Directory', 0755, '.'], ['Directory', 0755, 'Contents'],
    ['Regular File', 0644, 'Contents/Info.plist'], ['Directory', 0755, 'Contents/MacOS'],
    ['Regular File', 0755, 'Contents/MacOS/OpensteamerVirtualMicrophone'],
    ['Directory', 0755, 'Contents/Resources'], ['Regular File', 0644, 'Contents/Resources/APPLE_SAMPLE_LICENSE.txt'],
    ['Directory', 0755, 'Contents/Resources/en.lproj'], ['Regular File', 0644, 'Contents/Resources/en.lproj/Localizable.strings'],
    ['Directory', 0755, 'Contents/_CodeSignature'], ['Regular File', 0644, 'Contents/_CodeSignature/CodeResources']
  ].freeze
  GATE_KEYS = %w[schema observedAtUnixMs namespace nonce hostPid hostStartIdentitySha256 hostNonce hostLockDevice hostLockInode hostLaunchdRuns hostDisplayIdentitySha256 hostExecutableSha256 predecessorDriverInstance predecessorDriverDevice predecessorDriverInode predecessorDriverExecutableSha256 peerConnected authenticatedPeer iceConnected controlOpen screenCaptureActive sessionBoundaryProven inputUid outputUid systemOutputUid routeNotifications routeMonitorTeardownClean hostTerminal namespaceAbsent].freeze
  MAX_JSON = 8 * 1024 * 1024
  MAX_FILE = 64 * 1024 * 1024
  MAX_BUNDLE_FILE = 16 * 1024 * 1024
  PREPARATION_SECONDS = 210

  def self.require!(condition, message)
    raise Refusal, message, cause: nil unless condition
  end

  def self.keys!(object, keys, label)
    require!(object.is_a?(Hash) && object.keys.sort == keys.sort, "#{label} field set differs")
  end

  def self.parse_json(text)
    require!(text.is_a?(String) && text.bytesize.between?(1, MAX_JSON), 'JSON size differs')
    text = text.dup.force_encoding(Encoding::UTF_8)
    require!(text.valid_encoding?, 'JSON encoding differs')
    JSON.parse(text, object_class: UniqueObject, max_nesting: 24, create_additions: false, allow_nan: false)
  rescue JSON::ParserError, JSON::NestingError, TypeError
    raise Refusal, 'malformed JSON (contents redacted)', cause: nil
  end

  def self.freeze_tree(value)
    value.each { |key, item| key.freeze; freeze_tree(item) } if value.is_a?(Hash)
    value.each { |item| freeze_tree(item) } if value.is_a?(Array)
    value.freeze
  end

  def self.sha!(value, width = 64)
    require!(value.is_a?(String) && value.match?(/\A[0-9a-f]{#{width}}\z/), 'digest differs')
  end

  def self.text!(value)
    require!(value.is_a?(String) && value.bytesize.between?(1, 4096) && value.ascii_only? && value.dup.force_encoding(Encoding::UTF_8).valid_encoding? &&
             !value.match?(/[\x00-\x1f\x7f=]/), 'native value contains unsupported bytes')
  end

  def self.absolute!(path)
    text!(path)
    require!(path.start_with?('/') && !path.end_with?('/') && path.split('/').none? { |part| %w[. ..].include?(part) } &&
             !path.include?('//'), 'path is not absolute canonical syntax')
  end

  def self.positive!(value)
    require!(value.is_a?(String) && value.match?(/\A[1-9][0-9]{0,19}\z/) &&
             value.to_i <= 18_446_744_073_709_551_615, 'positive numeric identity differs')
  end

  def self.descriptor!(object)
    keys!(object, %w[path sha256], 'file descriptor')
    absolute!(object['path']); sha!(object['sha256'])
  end

  def self.validate_native!(native)
    keys!(native, NATIVE_KEYS, 'native request')
    native.values.each { |value| text!(value) }
    FIXED.each { |key, value| require!(native[key] == value, "approved #{key} differs") }
    require!(native['namespace'].match?(/\Adriver-microphone-v9-[a-z0-9]+(?:-[a-z0-9]+)*\z/) &&
             native['namespace'].bytesize <= 64, 'one-shot namespace differs')
    native.each do |key, value|
      sha!(value) if key.end_with?('_sha256') || %w[nonce host_nonce].include?(key)
      sha!(value, 40) if key.end_with?('_commit', '_tree')
      absolute!(value) if key.end_with?('_path', '_root')
    end
    %w[host_pid host_lock_device host_lock_inode predecessor_driver_instance predecessor_driver_device predecessor_driver_inode host_launchd_runs].each { |key| positive!(native[key]) }
    require!(native['host_pid'].to_i <= 2_147_483_647, 'host PID exceeds native range')
    require!(native['timeout_seconds'].match?(/\A[1-9][0-9]{0,2}\z/) && native['timeout_seconds'].to_i <= 180, 'deadline exceeds bound')
    require!(native['guard_tooling_root'] == File.realpath(__dir__ + '/../..'), 'current guard root differs')
    require!(native['guard_tooling_commit'] != native['producer_commit'], 'later guard provenance conflates producer provenance')
    require!(native['nonce'] != native['host_nonce'], 'transaction nonce reuses host generation nonce')
    require!(native['committed_host_pointer_path'] == HOST_ACTIVE_POINTER, 'matching host committed pointer differs')
    %w[result readiness journal].each do |role|
      require!(native['committed_host_' + role + '_path'].start_with?(HOST_UPDATE_ROOT + '/'),
               'matching host evidence is outside its committed namespace')
    end
    native
  end

  def self.native_text(native)
    validate_native!(native)
    NATIVE_KEYS.map { |key| "#{key}=#{native.fetch(key)}\n" }.join
  end

  def self.parse_native(text)
    require!(text.is_a?(String) && text.bytesize <= 65_536 && text.end_with?("\n") &&
             text.dup.force_encoding(Encoding::UTF_8).valid_encoding?, 'native request is incomplete')
    result = {}
    text.lines.each do |line|
      match = /\A([a-z][a-z0-9_]*)=([^\r\n]+)\n\z/.match(line)
      require!(match && !result.key?(match[1]), 'native request is malformed or duplicated')
      result[match[1]] = match[2]
    end
    validate_native!(result)
  end

  def self.validate_request!(request)
    keys!(request, %w[schema nativeRequest receiptRequest freshBinding tools gateObservation], 'coordinator request')
    require!(request['schema'] == SCHEMA, 'coordinator schema differs')
    native = validate_native!(request['nativeRequest'])
    %w[receiptRequest freshBinding gateObservation].each { |key| descriptor!(request[key]) }
    require!(request['freshBinding']['sha256'] == native['fresh_binding_sha256'], 'fresh receipt crosslink differs')
    keys!(request['tools'], TOOL_ROLES, 'sealed native tools')
    TOOL_ROLES.zip(TOOL_DIGEST_KEYS).each do |role, key|
      descriptor!(request['tools'][role])
      require!(request['tools'][role]['sha256'] == native[key], 'native tool crosslink differs')
    end
    request
  end

  # This only validates supplied observations. The worker must collect and prove
  # the same gate again immediately before any privileged boundary.
  def self.validate_gate!(native, gate, now_ms:)
    validate_native!(native); keys!(gate, GATE_KEYS, 'quiescent observation')
    require!(gate['schema'] == 'opensteamer.microphone-v9-quiescent-observation.v1' &&
             gate['observedAtUnixMs'].is_a?(Integer) && now_ms.is_a?(Integer) &&
             (now_ms - gate['observedAtUnixMs']).between?(0, 5000), 'quiescent observation is not fresh')
    mappings = {
      'namespace' => 'namespace', 'nonce' => 'nonce', 'hostPid' => 'host_pid',
      'hostStartIdentitySha256' => 'host_start_identity_sha256', 'hostNonce' => 'host_nonce',
      'hostLockDevice' => 'host_lock_device', 'hostLockInode' => 'host_lock_inode',
      'hostLaunchdRuns' => 'host_launchd_runs', 'hostDisplayIdentitySha256' => 'host_display_identity_sha256',
      'hostExecutableSha256' => 'host_executable_sha256',
      'predecessorDriverInstance' => 'predecessor_driver_instance',
      'predecessorDriverDevice' => 'predecessor_driver_device', 'predecessorDriverInode' => 'predecessor_driver_inode',
      'predecessorDriverExecutableSha256' => 'predecessor_driver_executable_sha256',
      'inputUid' => 'input_uid', 'outputUid' => 'output_uid', 'systemOutputUid' => 'system_output_uid'
    }
    mappings.each { |observed, pinned| require!(gate[observed] == native[pinned], "observed #{observed} differs") }
    %w[peerConnected authenticatedPeer iceConnected controlOpen screenCaptureActive].each do |key|
      require!(gate[key] == false, 'live peer or capture forbids transaction')
    end
    %w[sessionBoundaryProven routeMonitorTeardownClean namespaceAbsent].each do |key|
      require!(gate[key] == true, 'quiescent boundary, teardown or namespace is unproved')
    end
    require!(gate['routeNotifications'] == 0 && gate['hostTerminal'] == 'COMMITTED_CANDIDATE', 'host commit or routes are unproved')
    true
  end

  def self.stat_identity(stat)
    [stat.dev, stat.ino, stat.uid, stat.gid, stat.mode, stat.nlink, stat.size,
     stat.mtime.to_i * 1_000_000_000 + stat.mtime.nsec,
     stat.ctime.to_i * 1_000_000_000 + stat.ctime.nsec]
  end

  def self.check_deadline!(deadline)
    require!(Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline, 'read-only preparation deadline exceeded')
  end

  # The owning launcher still needs a child deadline/reap: a synchronous kernel
  # filesystem or CoreAudio call has no public in-process cancellation guarantee.
  def self.read_file!(descriptor, owner: 501, mode: nil, maximum: MAX_FILE, deadline: nil)
    deadline ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) + PREPARATION_SECONDS
    check_deadline!(deadline)
    descriptor!(descriptor); path = descriptor.fetch('path')
    require!(File.realpath(path) == path, 'file is not canonical')
    before = File.lstat(path)
    require!(before.file? && !before.symlink? && before.uid == owner && before.nlink == 1 &&
             (before.mode & 0022) == 0 && (!mode || before.mode & 0777 == mode) &&
             before.size.between?(1, maximum), 'file owner, mode, links or bound differs')
    bytes = ''.b
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      require!(stat_identity(file.stat) == stat_identity(before), 'file changed while opening')
      while (chunk = file.read(65_536))
        check_deadline!(deadline)
        bytes << chunk; require!(bytes.bytesize <= maximum, 'file exceeds bound')
      end
      require!(stat_identity(file.stat) == stat_identity(before), 'file changed while reading')
    end
    require!(File.realpath(path) == path && stat_identity(File.lstat(path)) == stat_identity(before) &&
             Digest::SHA256.hexdigest(bytes) == descriptor['sha256'], 'file identity or digest differs')
    check_deadline!(deadline)
    [bytes, { 'path' => path, 'sha256' => descriptor['sha256'], 'identity' => stat_identity(before) }]
  rescue SystemCallError, IOError
    raise Refusal, 'file missing or unreadable (contents redacted)', cause: nil
  end

  def self.verify_artifacts!(deadline: nil)
    deadline ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) + PREPARATION_SECONDS
    check_deadline!(deadline)
    root = File.lstat(ARTIFACT_ROOT)
    require!(File.realpath(ARTIFACT_ROOT) == ARTIFACT_ROOT && root.directory? && root.uid == 501 &&
             root.mode & 0777 == 0500, 'saved candidate root differs')
    require!(Dir.children(ARTIFACT_ROOT).sort == (ARTIFACT_FILES.keys + ['OpensteamerVirtualMicrophone.driver']).sort,
             'saved candidate layout differs')
    retained = {}
    records = ARTIFACT_FILES.map do |leaf, digest|
      maximum = leaf.end_with?('.pkg') ? MAX_FILE : MAX_JSON
      bytes, record = read_file!({ 'path' => ARTIFACT_ROOT + '/' + leaf, 'sha256' => digest }, maximum: maximum, deadline: deadline)
      retained[leaf] = bytes unless leaf.end_with?('.pkg')
      [leaf, record]
    end.to_h
    records['root'] = { 'path' => ARTIFACT_ROOT, 'identity' => stat_identity(root) }
    records['bundle'] = verify_bundle_bytes!(ARTIFACT_ROOT + '/OpensteamerVirtualMicrophone.driver', deadline: deadline)
    producer = parse_json(retained.fetch('binding-request.json'))
    historical = parse_json(retained.fetch('microphone-binding.json'))
    require!(producer['productCommit'] == PRODUCT_COMMIT && producer['productTree'] == PRODUCT_TREE &&
             producer['toolingCommit'] == PRODUCER_COMMIT && producer['toolingTree'] == PRODUCER_TREE &&
             historical['request'] == producer && historical['deploymentAuthority'] == false && historical['callerUid'] == 501,
             'saved producer provenance differs')
    require!(stat_identity(File.lstat(ARTIFACT_ROOT)) == stat_identity(root), 'saved candidate root changed')
    [records, producer]
  end

  def self.validate_fresh_receipt_request!(native, fresh, producer)
    expected = producer.merge('toolingRoot' => native['guard_tooling_root'],
                              'toolingCommit' => native['guard_tooling_commit'], 'toolingTree' => native['guard_tooling_tree'])
    require!(fresh == expected, 'fresh verifier request changes original source/receipt/tool pins')
    true
  end

  def self.verify_bundle_bytes!(root, deadline: nil)
    deadline ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) + PREPARATION_SECONDS
    check_deadline!(deadline)
    require!(File.realpath(root) == root, 'bundle root is not canonical')
    entries = []; walk = lambda do |relative|
      entries << relative
      check_deadline!(deadline)
      require!(entries.length <= BUNDLE_NODES.length, 'bundle node count exceeds exact layout')
      absolute = relative == '.' ? root : root + '/' + relative
      stat = File.lstat(absolute)
      Dir.children(absolute).sort.each { |leaf| walk.call(relative == '.' ? leaf : relative + '/' + leaf) } if stat.directory?
    end
    walk.call('.')
    require!(entries == BUNDLE_NODES.map { |_, _, path| path }, 'bundle node layout differs')
    records = {}; digest = Digest::SHA256.new
    BUNDLE_NODES.each do |type, mode, relative|
      check_deadline!(deadline)
      absolute = relative == '.' ? root : root + '/' + relative
      stat = File.lstat(absolute)
      require!(File.realpath(absolute) == absolute && !stat.symlink? && stat.uid == 501 &&
               stat.mode & 0777 == mode && (type == 'Directory' ? stat.directory? : stat.file? && stat.nlink == 1),
               'bundle node type, mode, links or owner differs')
      require!(type == 'Directory' || stat.size.between?(1, MAX_BUNDLE_FILE), 'bundle file exceeds exact bound')
      digest.update("#{type}|#{mode.to_s(8)}|#{relative}\0")
      records[relative] = { 'path' => absolute, 'identity' => stat_identity(stat) }
    end
    BUNDLE_NODES.select { |type, _, _| type == 'Regular File' }.each do |_, mode, relative|
      absolute = root + '/' + relative
      expected = Digest::SHA256.file(absolute).hexdigest
      _, record = read_file!({ 'path' => absolute, 'sha256' => expected }, mode: mode, maximum: MAX_BUNDLE_FILE, deadline: deadline)
      require!(record['identity'] == records[relative]['identity'], 'bundle node changed')
      records[relative] = record
      digest.update(relative + "\0" + record.fetch('sha256') + "\0")
    end
    require!(digest.hexdigest == FIXED.fetch('driver_tree_sha256') &&
             records.fetch('Contents/MacOS/OpensteamerVirtualMicrophone').fetch('sha256') == FIXED.fetch('driver_executable_sha256'),
             'reviewed bundle bytes or executable differs')
    records
  rescue SystemCallError, IOError
    raise Refusal, 'bundle unavailable (contents redacted)', cause: nil
  end

  def self.unelevated!
    require!(Process.uid == 501 && Process.euid == 501, 'coordinator requires original UID/EUID 501')
    require!(ENV.keys.none? { |key| key.match?(/\A(?:RUBY|GEM_|BUNDLE_|GIT_|DYLD_|LD_PRELOAD\z|LD_LIBRARY_PATH\z)/) },
             'inherited interpreter, loader or Git overrides are forbidden')
  end

  def self.verify(request)
    unelevated!
    request = freeze_tree(parse_json(JSON.generate(request)))
    validate_request!(request)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PREPARATION_SECONDS
    native = request.fetch('nativeRequest')
    before, producer = verify_artifacts!(deadline: deadline)
    request_bytes, request_identity = read_file!(request.fetch('receiptRequest'), mode: 0600, maximum: MAX_JSON, deadline: deadline)
    fresh_request = parse_json(request_bytes)
    validate_fresh_receipt_request!(native, fresh_request, producer)
    binding_bytes, binding_identity = read_file!(request.fetch('freshBinding'), mode: 0600, maximum: MAX_JSON, deadline: deadline)
    binding = parse_json(binding_bytes)
    # Original product CLI decides expiry/source/tools. No fixture or cached
    # producer marker can substitute for this unelevated fresh invocation.
    OpensteamerMicrophoneReceiptBinding.revalidate(binding, fresh_request)
    check_deadline!(deadline)
    tools = TOOL_ROLES.map do |role|
      _, identity = read_file!(request['tools'].fetch(role), deadline: deadline)
      require!((identity['identity'][4] & 0111) != 0, 'native sealed tool is not executable')
      [role, identity]
    end.to_h
    gate_bytes, gate_identity = read_file!(request.fetch('gateObservation'), mode: 0600, maximum: MAX_JSON, deadline: deadline)
    require!(verify_artifacts!(deadline: deadline) == [before, producer] &&
             read_file!(request.fetch('receiptRequest'), mode: 0600, maximum: MAX_JSON, deadline: deadline)[1] == request_identity &&
             read_file!(request.fetch('freshBinding'), mode: 0600, maximum: MAX_JSON, deadline: deadline)[1] == binding_identity &&
             read_file!(request.fetch('gateObservation'), mode: 0600, maximum: MAX_JSON, deadline: deadline)[1] == gate_identity,
             'coordinator input changed during verification')
    TOOL_ROLES.each do |role|
      require!(read_file!(request['tools'].fetch(role), deadline: deadline)[1] == tools.fetch(role), 'native tool changed during verification')
    end
    validate_gate!(native, parse_json(gate_bytes), now_ms: (Time.now.to_f * 1000).to_i)
    { 'schema' => RECORD_SCHEMA, 'deploymentAuthority' => false,
      'scope' => 'read-only-original-uid-preparation-native-worker-must-reprove-runtime',
      'nativeRequestSha256' => Digest::SHA256.hexdigest(native_text(native)),
      'nativeRequest' => native_text(native),
      'producerArtifacts' => before, 'freshReceiptRequest' => request_identity,
      'freshBinding' => binding_identity, 'tools' => tools, 'gateObservation' => gate_identity }
  rescue OpensteamerMicrophoneReceiptBinding::Refusal, SystemCallError, IOError
    raise Refusal, 'coordinator input or fresh original receipt refused (contents redacted)', cause: nil
  end

  def self.main(arguments)
    unelevated!
    require!(arguments.length == 4 && arguments[0] == '--request' && arguments[2] == '--request-sha256',
             'usage: --request CANONICAL_JSON --request-sha256 INDEPENDENT_SHA256')
    descriptor = { 'path' => arguments[1], 'sha256' => arguments[3] }
    bytes, identity = read_file!(descriptor, mode: 0600, maximum: MAX_JSON)
    result = verify(parse_json(bytes))
    require!(read_file!(descriptor, mode: 0600, maximum: MAX_JSON)[1] == identity, 'coordinator request changed')
    puts JSON.generate(result)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    OpensteamerMicrophoneV9TransactionContract.main(ARGV)
  rescue OpensteamerMicrophoneV9TransactionContract::Refusal
    warn 'microphone v9 coordinator refused (contents redacted; no installation authority)'
    exit 65
  end
end
