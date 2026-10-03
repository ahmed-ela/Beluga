# frozen_string_literal: true
# Shared, versioned distribution policy. These tools never install or launch the host,
# install an audio driver, change routes, or publish a release. The historical host
# builder/verifier deliberately retain their separate LiveKit-only contracts.
require 'base64'
require 'digest'
require 'etc'
require 'fileutils'
require 'find'
require 'json'
require 'open3'
require 'time'
require 'uri'

module BelugaMacClient
  ROOT = File.realpath(File.join(__dir__, '../..')).freeze
  CONFIG_PATH = File.join(ROOT, 'macOS/BelugaHost/Release.json').freeze
  CONFIG_KEYS = %w[schema version build minimumSystemVersion bundleIdentifier teamIdentifier sparkleVersion repository feedURL publicEDKey].sort.freeze
  BUNDLE_ID = 'com.elamin.AudioStreamer.CaptureServer'
  BROKER_ID = 'com.elamin.beluga.Updater'
  TEAM = 'MSMG8CJLB3'
  SPARKLE_VERSION = '2.10.0'
  STABLE_FEED_RELEASE_TAG = 'mac-update-stable'
  PRE_UPDATER_SOURCE = '168036d74e08e7b49aad37907cf9b84b5dcc8456'
  STABLE_FEED_URL = "https://github.com/ahmed-ela/Beluga/releases/download/#{STABLE_FEED_RELEASE_TAG}/appcast.xml".freeze
  CANDIDATE_XML_NAMESPACE = 'https://github.com/ahmed-ela/Beluga/ns/update'
  # v2 promises host phone-catalog schema1 support. Do not relabel an old artifact:
  # source composition and the actual sealed main-app marker must both pass.
  CANDIDATE_IDENTITY_SCHEMA = 'beluga.update-candidate.v2'
  PAIRED_PHONE_CATALOG_VERSION = 1
  BUNDLE_TREE_ALGORITHM = 'beluga.bundle-tree-json-v1'
  CANDIDATE_IDENTITY_KEYS = %w[schema version build executableSHA256 bundleTreeSHA256 bundleTreeAlgorithm].sort.freeze
  HOST_RPATH = '@executable_path/../Frameworks'
  LIVEKIT_INSTALL = '@rpath/LiveKitWebRTC.framework/LiveKitWebRTC'
  SPARKLE_INSTALL = '@rpath/Sparkle.framework/Versions/B/Sparkle'
  # Public executable digests from the exact SwiftPM 2.10.0 distribution, whose
  # binaryTarget ZIP checksum is 17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959.
  SPARKLE_TOOLS = {
    'sign_update' => '43c249771bafc3aa581228abae00731a012d324691b8292860896635050be76b',
    'generate_keys' => 'c37679f98d9121981cf7b2d18592fdc8b44931bffa604acf10c9e11791b6222e'
  }.freeze
  ICON_SHA = 'b2b23a101dc2de171d4a64eec31afc87858d8c31515048f958d82ed2e779f936'
  LIVEKIT = 'Contents/Frameworks/LiveKitWebRTC.framework'
  SPARKLE = 'Contents/Frameworks/Sparkle.framework'
  SPARKLE_B = "#{SPARKLE}/Versions/B"
  BROKER = 'Contents/Helpers/BelugaUpdater.app'
  BROKER_EXECUTABLE = "#{BROKER}/Contents/MacOS/BelugaUpdater"
  BROKER_SPARKLE = "#{BROKER}/Contents/Frameworks/Sparkle.framework"
  SPARKLE_COPIES = [SPARKLE, BROKER_SPARKLE].freeze
  SPARKLE_CODE = SPARKLE_COPIES.flat_map do |framework|
    spine = "#{framework}/Versions/B"
    {
      "#{spine}/Sparkle" => 'org.sparkle-project.Sparkle',
      "#{spine}/Autoupdate" => 'org.sparkle-project.Sparkle.Autoupdate',
      "#{spine}/Updater.app/Contents/MacOS/Updater" => 'org.sparkle-project.Sparkle.Updater',
      "#{spine}/XPCServices/Installer.xpc/Contents/MacOS/Installer" => 'org.sparkle-project.InstallerLauncher',
      "#{spine}/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" => 'org.sparkle-project.DownloaderService'
    }.to_a
  end.to_h.freeze
  CODE = {
    'Contents/MacOS/CaptureServer' => BUNDLE_ID,
    'Contents/MacOS/OpensteamerMediaBridge' => 'org.example.opensteamer.MediaBridge',
    "#{LIVEKIT}/Versions/A/LiveKitWebRTC" => 'io.livekit.LiveKitWebRTC',
    BROKER_EXECUTABLE => BROKER_ID
  }.merge(SPARKLE_CODE).freeze
  SPARKLE_ALIASES = SPARKLE_COPIES.flat_map do |framework|
    [["#{framework}/Versions/Current", 'B']] +
      %w[Autoupdate Headers Modules PrivateHeaders Resources Sparkle Updater.app XPCServices].map { |name| ["#{framework}/#{name}", "Versions/Current/#{name}"] }
  end.to_h.freeze
  ALIASES = { "#{LIVEKIT}/Versions/Current" => 'A' }
    .merge(%w[Headers LiveKitWebRTC Modules Resources].to_h { |name| ["#{LIVEKIT}/#{name}", "Versions/Current/#{name}"] })
    .merge(SPARKLE_ALIASES).freeze

  class Refusal < StandardError; end
  class UniqueObject < Hash
    def []=(key, value)
      raise Refusal, 'duplicate JSON configuration field' if key?(key)
      super
    end
  end
  def self.require!(condition, message)
    raise Refusal, message unless condition
  end

  def self.utf8_text(bytes, label)
    require!(bytes.is_a?(String), label + ' is not text')
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    require!(text.valid_encoding?, label + ' is not valid UTF-8')
    text
  end

  def self.public_key!(value)
    require!(value.is_a?(String), 'publicEDKey is unconfigured; generate an updater key in Keychain first')
    decoded = Base64.strict_decode64(value)
    require!(decoded.bytesize == 32 && decoded.bytes.any? { |byte| byte != 0 } && Base64.strict_encode64(decoded) == value, 'invalid Ed25519 public key')
    value
  rescue ArgumentError
    raise Refusal, 'invalid canonical Ed25519 public key'
  end

  def self.config!(path = CONFIG_PATH)
    regular!(path)
    value = JSON.parse(File.read(path), object_class: UniqueObject)
    require!(value.is_a?(Hash) && value.keys.sort == CONFIG_KEYS, 'release configuration schema keys differ')
    require!(value['schema'] == 'beluga.mac-client-release.v1', 'unknown release configuration schema')
    require!(value['version'].is_a?(String) && /\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/.match?(value['version']), 'version must be canonical major.minor.patch')
    require!(value['version'].split('.').all? { |part| part.to_i <= 2**32 - 1 }, 'semantic version component exceeds runtime bounds')
    require!(value['build'].is_a?(Integer) && value['build'] >= 100 && value['build'] <= 2**63 - 1, 'broker-only distribution builds begin at 100')
    require!(value['bundleIdentifier'] == BUNDLE_ID && value['teamIdentifier'] == TEAM, 'preserved product signing identity differs')
    require!(value['minimumSystemVersion'] == '14.0' && value['sparkleVersion'] == SPARKLE_VERSION, 'unreviewed platform/Sparkle version')
    require!(value['repository'] == 'ahmed-ela/Beluga' && value['feedURL'] == STABLE_FEED_URL, 'unreviewed repository/stable Mac feed')
    public_key!(value['publicEDKey'])
    value.freeze
  rescue JSON::ParserError
    raise Refusal, 'invalid release configuration JSON'
  end

  def self.canonical!(path)
    require!(path.is_a?(String) && path.start_with?('/') && File.realpath(path) == path, 'path must be absolute, canonical, and free of symlink ancestors')
    path
  rescue Errno::ENOENT
    raise Refusal, 'required path does not exist'
  end

  def self.regular!(path)
    canonical!(path)
    info = File.lstat(path)
    require!(info.file? && !info.symlink? && info.nlink == 1 && (info.mode & 0o022).zero?, "unsafe regular file: #{path}")
    info
  end

  def self.empty_owned_directory!(path)
    canonical!(path)
    info = File.lstat(path)
    require!(info.directory? && info.uid == Process.uid && (info.mode & 0o777) == 0o700 && Dir.children(path).empty?, 'output/scratch must be an existing empty owned 0700 directory')
    path
  end

  # No shell interpolation; only this invocation's process group is cancelled.
  def self.run(*argv, timeout: 600, env: {}, capture_stderr: false, unsetenv_others: false)
    output = error = nil
    Open3.popen3(env, *argv, pgroup: true, unsetenv_others: unsetenv_others) do |input, stdout, stderr, wait|
      input.close
      readers = [stdout, stderr].map do |stream|
        Thread.new do
          bytes = +''
          while (chunk = stream.read(65_536))
            bytes << chunk
            raise Refusal, 'command output exceeds bounded capture' if bytes.bytesize > 16 * 1024 * 1024
          end
          bytes
        end
      end
      begin
        unless wait.join(timeout)
          raise Refusal, "command exceeded #{timeout}s: #{File.basename(argv.first)}"
        end
        output, error = readers.map(&:value)
        require!(wait.value.success?, "#{File.basename(argv.first)} failed: #{error.to_s[-4000, 4000] || error}")
      ensure
        if wait.alive?
          Process.kill('TERM', -wait.pid) rescue Errno::ESRCH
          unless wait.join(3)
            Process.kill('KILL', -wait.pid) rescue Errno::ESRCH
            wait.join
          end
        end
        readers.each { |reader| reader.kill if reader.alive? }
      end
    end
    capture_stderr ? output + error : output
  end

  def self.snapshot(path)
    info = regular!(path)
    [info.dev, info.ino, info.uid, info.gid, info.mode, info.size, Digest::SHA256.file(path).hexdigest]
  end

  # This consumes existing invocation/tools fields only AFTER the production
  # microphone validator admitted the unchanged receipt. It does not renew or
  # fabricate test evidence. Compiler selection and its environment are bound
  # before signing identity lookup and rechecked around every release compile.
  class TestedToolchain
    OVERRIDE_NAMES = %w[TOOLCHAINS TOOLCHAIN_DIR SWIFT_EXEC SDKROOT SDK_DIR
                        CC CXX LD AR AS CFLAGS CXXFLAGS CPPFLAGS LDFLAGS ARCHFLAGS
                        CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH
                        LIBRARY_PATH MACOSX_DEPLOYMENT_TARGET ARCHS VALID_ARCHS
                        EXCLUDED_ARCHS ONLY_ACTIVE_ARCH BUILD_DIR BUILT_PRODUCTS_DIR
                        OBJROOT SYMROOT DSTROOT INSTALL_ROOT INSTALL_DIR
                        XCODE_XCCONFIG_FILE GCC_EXEC_PREFIX COMPILER_PATH].freeze
    OVERRIDE_PREFIX = /\A(?:DYLD_|OTHER_|SWIFT_|SWIFTPM_|SPM_|CLANG_|LLVM_|GCC_|XCODE_|__XCODE_)/

    attr_reader :developer_directory, :swift

    def initialize(record, ambient: ENV.to_h)
      BelugaMacClient.require!(record.is_a?(Hash), 'verified receipt toolchain fields are missing or malformed')
      invocation = record.fetch('invocation')
      tools = record.fetch('tools')
      BelugaMacClient.require!(invocation.is_a?(Hash) && tools.is_a?(Hash), 'verified receipt toolchain fields are missing')
      @developer_directory = invocation.fetch('developer_directory')
      BelugaMacClient.canonical!(@developer_directory)
      BelugaMacClient.require!(File.directory?(@developer_directory), 'tested developer directory is not a directory')
      @swift = File.join(@developer_directory, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swift')
      @tool_paths = [@swift,
                     File.join(@developer_directory, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/clang'),
                     File.join(@developer_directory, 'usr/bin/xcodebuild')]
      @expected = @tool_paths.to_h do |path|
        sha = tools[path]
        BelugaMacClient.require!(sha.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(sha), 'receipt lacks the exact tested default Xcode tool')
        [path, sha]
      end.freeze
      self.class.admit_environment!(@developer_directory, ambient)
      @snapshots = @tool_paths.to_h { |path| [path, tool_snapshot(path)] }.freeze
    rescue KeyError, TypeError
      raise Refusal, 'verified receipt toolchain fields are missing or malformed'
    end

    def self.admit_environment!(developer_directory, ambient)
      BelugaMacClient.require!(ambient.is_a?(Hash) && ambient.keys.all? { |name| name.is_a?(String) }, 'build environment is malformed')
      selected = ambient['DEVELOPER_DIR']
      BelugaMacClient.require!(selected.nil? || selected == developer_directory, 'DEVELOPER_DIR differs from the tested receipt')
      forbidden = ambient.keys.find { |name| OVERRIDE_NAMES.include?(name) || OVERRIDE_PREFIX.match?(name) }
      BelugaMacClient.require!(forbidden.nil?, "unreviewed release build environment variable: #{forbidden}")
    end

    def verify!(ambient: ENV.to_h)
      self.class.admit_environment!(@developer_directory, ambient)
      BelugaMacClient.require!(@tool_paths.to_h { |path| [path, tool_snapshot(path)] } == @snapshots, 'tested release tool identity changed')
      true
    end

    def build_environment(temporary_directory:, ambient: ENV.to_h)
      verify!(ambient: ambient)
      BelugaMacClient.canonical!(temporary_directory)
      info = File.lstat(temporary_directory)
      BelugaMacClient.require!(info.directory? && info.uid == Process.uid && (info.mode & 0o777) == 0o700, 'build TMPDIR must be owned private scratch')
      # Derive HOME from the current account, not an inherited caller override.
      # unsetenv_others:true is mandatory at every Swift child: unsupported keys
      # are also inert, even when they are not in the explicit rejection set.
      {
        'PATH' => File.dirname(@swift) + ':/usr/bin:/bin:/usr/sbin:/sbin',
        'HOME' => Etc.getpwuid(Process.uid).dir,
        'DEVELOPER_DIR' => @developer_directory,
        'TMPDIR' => temporary_directory, 'LC_ALL' => 'C',
        'MACOSX_DEPLOYMENT_TARGET' => '14.0',
        'SWIFT_TREAT_WARNINGS_AS_ERRORS' => 'YES'
      }.freeze
    end

    def binding
      { 'developer_directory' => @developer_directory, 'tools' => @expected }
    end

    private

    def tool_snapshot(path)
      BelugaMacClient.canonical!(File.dirname(path))
      declared = File.lstat(path)
      resolved = File.realpath(path)
      BelugaMacClient.require!(resolved.start_with?(@developer_directory + '/'), 'tested compiler resolves outside its developer directory')
      actual = BelugaMacClient.snapshot(resolved)
      BelugaMacClient.require!(File.executable?(resolved) && actual.last == @expected.fetch(path), 'release compiler bytes differ from tested receipt')
      [declared.dev, declared.ino, declared.mode, declared.ftype,
       declared.symlink? ? File.readlink(path) : nil, resolved, actual]
    rescue SystemCallError
      raise Refusal, 'tested release tool is unavailable or unsafe'
    end
  end

  class MicrophoneReceipt
    def initialize
      @receipt = ENV.fetch('BELUGA_MICROPHONE_REGRESSION_RECEIPT', '')
      @expected = ENV.fetch('BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256', '')
      @runner = File.join(ROOT, 'scripts/validate-microphone-regressions.sh')
      BelugaMacClient.require!(/\A[0-9a-f]{64}\z/.match?(@expected), 'current source-bound microphone receipt SHA is required')
      @initial = nil
    end

    def verify!
      receipt = BelugaMacClient.snapshot(@receipt)
      runner = BelugaMacClient.snapshot(@runner)
      BelugaMacClient.require!(File.executable?(@runner) && receipt.last == @expected, 'microphone receipt/runner admission failed')
      bound = [receipt, runner]
      BelugaMacClient.require!(@initial.nil? || @initial == bound, 'microphone receipt/runner changed across release stages')
      BelugaMacClient.run(@runner, '--verify-receipt', @receipt, '--receipt-sha256', @expected)
      BelugaMacClient.require!(bound == [BelugaMacClient.snapshot(@receipt), BelugaMacClient.snapshot(@runner)], 'microphone receipt/runner changed during verification')
      @initial = bound
    end

    def tested_toolchain(ambient: ENV.to_h)
      BelugaMacClient.require!(@initial && @initial.first == BelugaMacClient.snapshot(@receipt), 'receipt must be verified before selecting release tools')
      record = JSON.parse(File.read(@receipt), object_class: UniqueObject)
      toolchain = TestedToolchain.new(record, ambient: ambient)
      BelugaMacClient.require!(@initial.first == BelugaMacClient.snapshot(@receipt), 'receipt changed while selecting release tools')
      toolchain
    end

    def evidence_binding
      BelugaMacClient.require!(@initial && @initial.first == BelugaMacClient.snapshot(@receipt), 'receipt must be verified before binding its evidence')
      { 'path' => @receipt.dup.freeze, 'sha256' => @expected.dup.freeze }.freeze
    end
  end

  def self.source!
    require!(run('/usr/bin/git', '-C', ROOT, 'status', '--porcelain', '--untracked-files=normal').empty?, 'release source must be committed and clean')
    commit = run('/usr/bin/git', '-C', ROOT, 'rev-parse', 'HEAD').strip
    tree = run('/usr/bin/git', '-C', ROOT, 'rev-parse', 'HEAD^{tree}').strip
    require!(/\A[0-9a-f]{40}\z/.match?(commit) && /\A[0-9a-f]{40}\z/.match?(tree), 'source binding is invalid')
    run('/usr/bin/git', '-C', ROOT, 'merge-base', '--is-ancestor', PRE_UPDATER_SOURCE, commit)
    baseline = run('/usr/bin/git', '-C', ROOT, 'show', "#{PRE_UPDATER_SOURCE}:Package.swift")
    require!(!baseline.include?('Sparkle'), 'pre-updater lineage baseline differs')
    updater_source_contract!
    catalog_source_contract!
    { 'commit' => commit, 'tree' => tree }
  end

  # Signed ownership-protocol=1 is issued only by this broker-only producer.
  # This is a source regression guard, not a substitute for signed replacement tests.
  def self.updater_source_contract!(sources = nil)
    sources ||= Dir.glob(File.join(ROOT, 'macOS/Sources/CaptureServer/**/*.swift')).to_h do |path|
      [path.delete_prefix("#{ROOT}/"), File.binread(path)]
    end
    sources = sources.transform_values { |bytes| utf8_text(bytes, 'Mac updater source') }
    require!(!sources.empty?, 'menu sources missing')
    sources.each do |path, source|
      require!(!source.match?(/\b(?:import\s+Sparkle|SPUUpdater|SPUStandardUpdaterController)\b/), "in-process updater is forbidden: #{path}")
    end
    controller = sources['macOS/Sources/CaptureServer/BelugaUpdateController.swift']
    client = sources['macOS/Sources/CaptureServer/BelugaUpdateMenuClient.swift']
    require!(controller && client && controller.include?('BelugaUpdateMenuClient.begin') &&
      client.include?('BelugaUpdateBrokerArtifact.verifyStaged') && client.include?('BelugaUpdateIPCChannel'),
      'external updater composition missing')
    true
  end

  def self.plist(path)
    regular!(path)
    JSON.parse(run('/usr/bin/plutil', '-convert', 'json', '-o', '-', path))
  end

  # Source regression guard only; focused catalog/runtime tests remain required.
  # It prevents this producer stamping v2 onto the former single-viewer composition.
  def self.catalog_source_contract!(sources = nil)
    sources ||= Dir.glob(File.join(ROOT, 'macOS/Sources/CaptureServer/**/*.swift')).to_h do |path|
      [path.delete_prefix("#{ROOT}/"), File.binread(path)]
    end
    sources = sources.transform_values { |bytes| utf8_text(bytes, 'Mac catalog source') }
    coordinator = sources['macOS/Sources/CaptureServer/WorldwideHostCoordinator.swift']
    store = sources['macOS/Sources/CaptureServer/WorldwidePairingStore.swift']
    bootstrap = sources['macOS/Sources/CaptureServer/WorldwidePairingBootstrap.swift']
    checkpoint = sources['macOS/Sources/CaptureServer/WorldwidePairingCatalogCheckpoint.swift']
    migration = coordinator && coordinator.index('store.phoneCatalog.loadOrMigrate(for: identity)')
    availability = coordinator && coordinator.index('startAvailabilityLoop()')
    legacy_calls = /\b(?:loadPairedViewer|savePairedViewer|resetPairedViewer)\s*\(/
    require!(migration && availability && migration < availability &&
             coordinator.include?('snapshot.selectedRecord') &&
             coordinator.include?('publishPresentation(.unselected)') &&
             !coordinator.match?(legacy_calls), 'catalog-aware host composition missing')
    require!(store && store.include?('WorldwidePairedPhoneCatalogStore.catalogAccount') &&
             store.include?('throw WorldwidePairingStoreError.catalogIsAuthoritative') &&
             store.scan(/\btry requireLegacyNamespace\(\)/).length == 3,
             'single-viewer account is not fenced after catalog migration')
    require!(bootstrap && bootstrap.include?('try checkpoint.add(pending)') &&
             bootstrap.include?('try checkpoint.update(record)') && !bootstrap.match?(legacy_calls) &&
             checkpoint && checkpoint.include?('catalog.addPairedPhone(') &&
             checkpoint.include?('catalog.updatePairedPhone('), 'pairing checkpoints are not catalog-aware')
    true
  end

  def self.paired_phone_catalog_info!(info)
    require!(info.is_a?(Hash) && info['BelugaPairedPhoneCatalogVersion'].is_a?(Integer) &&
             info['BelugaPairedPhoneCatalogVersion'] == PAIRED_PHONE_CATALOG_VERSION,
             'signed app does not declare exact paired-phone catalog version1')
    true
  end

  def self.paired_phone_catalog_plist!(path)
    regular!(path)
    # JSON serialization can erase the difference between plist real1 and integer1.
    marker = run('/usr/bin/plutil', '-extract', 'BelugaPairedPhoneCatalogVersion',
                 'raw', '-expect', 'integer', '-n', path)
    require!(marker == PAIRED_PHONE_CATALOG_VERSION.to_s,
             'signed app does not declare exact paired-phone catalog version1')
    paired_phone_catalog_info!(plist(path))
  end

  def self.plist_set(path, key, value)
    type, representation = case value
                           when true, false then ['bool', value ? 'YES' : 'NO']
                           when Integer then ['integer', value.to_s]
                           else ['string', value.to_s]
                           end
    run('/usr/bin/plutil', '-replace', key, "-#{type}", representation, path)
  end

  def self.rendezvous!(value)
    require!(value.is_a?(String), 'distribution rendezvous is missing')
    url = URI.parse(value)
    host = url.host.to_s
    require!(url.scheme == 'wss' && url.userinfo.nil? && url.query.nil? && url.fragment.nil? &&
             [nil, 443].include?(url.port) && url.path.to_s.empty? && host.include?('.') &&
             !host.match?(/\A[0-9.]+\z/) && !host.end_with?('.invalid', '.example', '.local') &&
             host != 'localhost' && value == url.to_s, 'distribution rendezvous must be a canonical public WSS base URL')
    value
  rescue URI::InvalidURIError
    raise Refusal, 'distribution rendezvous URL is invalid'
  end

  def self.signature_fields!(metadata)
    fields = {}
    utf8_text(metadata, 'codesign metadata').each_line do |raw_line|
      line = raw_line.chomp
      if /\ACodeDirectory(?:[ =\t]|\z)/.match?(line)
        # Unlike the other records, native codesign emits "CodeDirectory v=...".
        # Do not normalize a fabricated key=value or tab-separated alias.
        require!(line.start_with?('CodeDirectory '), 'malformed codesign CodeDirectory record')
        key, value = 'CodeDirectory', line.delete_prefix('CodeDirectory ')
      else
        next unless /\A(?:Identifier|TeamIdentifier|Authority|Timestamp)=/.match?(line)
        key, value = line.split('=', 2)
      end
      if key == 'Authority'
        (fields[key] ||= []) << value
      else
        require!(!fields.key?(key), "duplicate codesign field: #{key}")
        fields[key] = value
      end
    end
    require!(fields['TeamIdentifier'] == TEAM && fields.fetch('Authority', []).first.to_s.match?(/\ADeveloper ID Application: .+ \(#{TEAM}\)\z/), 'not an exact-team Developer ID Application signature')
    directory = fields.fetch('CodeDirectory', '')
    flags = /\Av=[0-9]+ size=[0-9]+ flags=0x([0-9a-f]+)\(([a-z0-9,-]*)\)(?: [^\r\n]*)?\z/.match(directory)
    labels = flags ? flags[2].split(',') : []
    require!(flags && directory.scan(/\bflags=/).length == 1 &&
             (flags[1].to_i(16) & 0x10000) != 0 && (flags[1].to_i(16) & 0x2).zero? &&
             labels.include?('runtime') && !labels.include?('adhoc') &&
             !fields.fetch('Timestamp', '').match?(/\A[[:space:]]*(?:none)?[[:space:]]*\z/i),
             'hardened runtime/secure timestamp required')
    fields
  end

  def self.entitlements!(value, host: false)
    expected = host ? { 'com.apple.security.automation.apple-events' => true } : {}
    require!(value == expected, 'entitlements differ from reviewed exact contract (no debug/JIT/library-validation exceptions)')
  end

  def self.code_metadata(path)
    # codesign -d writes metadata on stderr even on success.
    signature_fields!(run('/usr/bin/codesign', '-d', '--verbose=4', path, capture_stderr: true))
  end

  def self.verify_code!(path, identifier, host: false)
    run('/usr/bin/codesign', '--verify', '--strict', '--verbose=2', path)
    metadata = code_metadata(path)
    require!(metadata['Identifier'] == identifier, 'signed code identifier differs')
    requirement = "identifier \"#{identifier}\" and anchor apple generic and certificate leaf[subject.OU] = \"#{TEAM}\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    run('/usr/bin/codesign', '--verify', '--strict', "-R=#{requirement}", path)
    raw = run('/usr/bin/codesign', '-d', '--entitlements', ':-', path)
    value = {}
    # Entitlement XML must be converted from captured bytes, not reopened code.
    unless raw.empty?
      output, error, status = Open3.capture3('/usr/bin/plutil', '-convert', 'json', '-o', '-', '-', stdin_data: raw)
      require!(status.success?, "invalid entitlement plist: #{error}")
      value = JSON.parse(output)
    end
    entitlements!(value, host: host)
  end

  def self.rpaths(path)
    run('/usr/bin/otool', '-l', path).scan(/\bcmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset \d+\)/).flatten
  end

  # vtool prints linker/compiler `version` fields after LC_BUILD_VERSION.minos.
  # Bind the deployment target to its command and exact architecture instead of
  # treating every version-looking line as another minimum OS version.
  def self.deployment_versions!(metadata, path:, architectures:)
    require!(path.is_a?(String) && path.start_with?('/') && !path.match?(/[\r\n\0]/), 'invalid vtool binary path')
    require!(architectures.is_a?(Array) && !architectures.empty? &&
      architectures.uniq == architectures && (architectures - %w[arm64 x86_64]).empty?, 'invalid vtool architecture set')
    text = utf8_text(metadata, 'vtool build metadata')
    require!(text.bytesize <= 65_536 && text.end_with?("\n"), 'missing or oversized vtool build metadata')
    header = /\A#{Regexp.escape(path)}(?: \(architecture (arm64|x86_64)\))?:\z/
    slices = {}
    current = nil
    text.each_line do |line|
      line = line.chomp
      match = header.match(line)
      if match
        arch = match[1]
        require!(arch || architectures.length == 1, 'unbound universal vtool slice')
        arch ||= architectures.first
        require!(architectures.include?(arch) && !slices.key?(arch), 'duplicate or unexpected vtool slice')
        current = slices[arch] = []
      else
        require!(current && !line.strip.empty?, 'missing or malformed vtool slice header')
        current << line.strip
      end
    end
    require!(slices.keys.sort == architectures.sort, 'missing per-slice deployment target')
    version = '[0-9]+(?:\\.[0-9]+){1,2}'
    architectures.map do |arch|
      fields = slices.fetch(arch)
      require!(fields.first && fields.first.match?(/\ALoad command [0-9]+\z/), 'missing vtool load command')
      case fields[1]
      when 'cmd LC_BUILD_VERSION'
        size = /\Acmdsize ([0-9]{1,4})\z/.match(fields[2].to_s)
        minimum = /\Aminos (#{version})\z/.match(fields[4].to_s)
        count = /\Antools ([0-9]{1,2})\z/.match(fields[6].to_s)
        require!(size && minimum && count && fields[3] == 'platform MACOS' &&
          /\Asdk #{version}\z/.match?(fields[5].to_s), 'malformed or non-macOS build command')
        tools = count[1].to_i
        require!(tools <= 64 && size[1].to_i == 24 + 8 * tools && fields.length == 7 + 2 * tools,
          'ambiguous vtool build/tool records')
        fields.drop(7).each_slice(2) do |tool, tool_version|
          require!(/\Atool [A-Z0-9_]+\z/.match?(tool) && /\Aversion #{version}\z/.match?(tool_version),
            'malformed vtool compiler/linker version')
        end
        minimum[1]
      when 'cmd LC_VERSION_MIN_MACOSX'
        minimum = /\Aversion (#{version})\z/.match(fields[3].to_s)
        require!(fields.length == 5 && fields[2] == 'cmdsize 16' && minimum &&
          /\Asdk #{version}\z/.match?(fields[4].to_s), 'malformed legacy macOS minimum command')
        minimum[1]
      else
        raise Refusal, 'unsupported vtool deployment command'
      end
    end
  end

  def self.dependencies!(records, expected_relative, install_id: nil)
    slices = []
    counts = []
    records.each_line do |line|
      next if line.strip.empty?
      if line.match?(/\A\S.*:\s*\z/)
        slices << []
        counts << 0
      elsif line.match?(/\A\s+\S+\s+\(compatibility version /)
        require!(!slices.empty?, 'dependency without architecture header')
        counts[-1] += 1
        value = line.split.first
        require!(!value.include?('..') && !value.include?('//'), 'malformed dependency')
        system = value.match?(%r{\A/usr/lib/(?:lib[^/]+|system/[^/]+|swift/[^/]+)\.dylib\z}) || value.match?(%r{\A/System/Library/Frameworks/[^/]+\.framework/Versions/[^/]+/[^/]+\z})
        require!(system || expected_relative.include?(value) || value == install_id, "unreviewed dependency: #{value}")
        slices.last << value unless system
      else
        raise Refusal, 'malformed otool dependency output'
      end
    end
    require!(!slices.empty? && counts.all? { |count| count > 0 } && slices.all? { |slice| slice.sort == (expected_relative + [install_id].compact).sort }, 'missing, duplicate, or extra embedded dependency in an architecture slice')
    slices.length
  end

  # Both executables resolve Sparkle from their own Contents/Frameworks. The
  # broker must remain independently stageable and cannot import the host's
  # LiveKit or resolve code through the enclosing application.
  def self.code_loading_contract!(relative)
    require!(CODE.key?(relative), 'unreviewed distribution code path')
    compiled = ['Contents/MacOS/CaptureServer', 'Contents/MacOS/OpensteamerMediaBridge', BROKER_EXECUTABLE]
    framework_install = if relative == "#{LIVEKIT}/Versions/A/LiveKitWebRTC"
                          LIVEKIT_INSTALL
                        elsif SPARKLE_COPIES.any? { |framework| relative == "#{framework}/Versions/B/Sparkle" }
                          SPARKLE_INSTALL
                        end
    dependencies = case relative
                   when 'Contents/MacOS/CaptureServer' then [LIVEKIT_INSTALL, SPARKLE_INSTALL]
                   when BROKER_EXECUTABLE then [SPARKLE_INSTALL]
                   else []
                   end
    { 'rpaths' => (['Contents/MacOS/CaptureServer', BROKER_EXECUTABLE].include?(relative) ? [HOST_RPATH] : []),
      'dependencies' => dependencies, 'installID' => framework_install,
      'compiledArm64' => compiled.include?(relative) }.freeze
  end

  def self.verify_loading_contract!(relative, actual_rpaths:, dependency_output:)
    contract = code_loading_contract!(relative)
    require!(actual_rpaths == contract['rpaths'], "unreviewed rpaths: #{relative}")
    dependencies!(dependency_output, contract['dependencies'], install_id: contract['installID'])
  end

  # Explicit inside-out order, not codesign --deep. Each copy owns all of the
  # official framework's helper executables; only the outer host gets the
  # AppleEvents entitlement. Broker signing precedes enclosing app signing.
  def self.nested_signing_contract
    SPARKLE_COPIES.flat_map do |framework|
      spine = "#{framework}/Versions/B"
      [["#{spine}/XPCServices/Installer.xpc", 'org.sparkle-project.InstallerLauncher'],
       ["#{spine}/XPCServices/Downloader.xpc", 'org.sparkle-project.DownloaderService'],
       ["#{spine}/Autoupdate", 'org.sparkle-project.Sparkle.Autoupdate'],
       ["#{spine}/Updater.app", 'org.sparkle-project.Sparkle.Updater'],
       [framework, 'org.sparkle-project.Sparkle']]
    end + [[BROKER_EXECUTABLE, BROKER_ID], [BROKER, BROKER_ID],
           [LIVEKIT, 'io.livekit.LiveKitWebRTC'],
           ['Contents/MacOS/OpensteamerMediaBridge', 'org.example.opensteamer.MediaBridge']]
  end

  def self.broker_info(config)
    { 'CFBundleDevelopmentRegion' => 'en', 'CFBundleInfoDictionaryVersion' => '6.0',
      'CFBundleIdentifier' => BROKER_ID, 'CFBundleExecutable' => 'BelugaUpdater',
      'CFBundleName' => 'Beluga Updater', 'CFBundleDisplayName' => 'Beluga Updater',
      'CFBundlePackageType' => 'APPL', 'CFBundleShortVersionString' => config['version'],
      'CFBundleVersion' => config['build'].to_s, 'LSMinimumSystemVersion' => '14.0',
      'LSUIElement' => true, 'SUFeedURL' => config['feedURL'], 'SUPublicEDKey' => config['publicEDKey'],
      'SUVerifyUpdateBeforeExtraction' => true, 'SURequireSignedFeed' => true,
      'SUAllowsAutomaticUpdates' => false }
  end

  def self.broker_info!(value, config:)
    require!(value == broker_info(config), 'broker Info.plist metadata differs')
  end

  def self.aliases_and_tree!(app)
    canonical!(app)
    root = File.lstat(app)
    require!(root.directory? && File.basename(app) == 'Beluga Host.app', 'wrong distribution app root')
    aliases = {}
    executables = []
    Find.find(app) do |path|
      relative = path.delete_prefix("#{app}/")
      info = File.lstat(path)
      require!((info.mode & 0o022).zero?, "writable staged bundle node: #{relative}")
      if info.symlink?
        aliases[relative] = File.readlink(path)
        Find.prune
      elsif info.directory?
        require!((info.mode & 0o777) == 0o755, "directory permissions differ: #{relative}")
      else
        require!(info.file? && info.nlink == 1, "special or multiply-linked bundle node: #{relative}")
        mode = info.mode & 0o777
        require!([0o644, 0o755].include?(mode), "file permissions differ: #{relative}")
        prefix = File.open(path, 'rb') { |file| file.read(4) }.to_s
        macho = %w[feedface feedfacf cefaedfe cffaedfe cafebabe bebafeca cafebabf bfbafeca].include?(prefix.unpack1('H*'))
        require!(!prefix.start_with?('#!') && (!macho || CODE.key?(relative)), "unreviewed executable code hidden in resource: #{relative}")
        executables << relative if mode == 0o755
      end
    end
    require!(aliases == ALIASES, 'framework alias set differs or escapes the reviewed version spine')
    aliases.each_key do |relative|
      framework = ([LIVEKIT] + SPARKLE_COPIES).find { |candidate| relative.start_with?("#{candidate}/") }
      require!(framework && File.realpath(File.join(app, relative)).start_with?("#{app}/#{framework}/"), 'framework alias escapes its own embedded copy')
    end
    require!(executables.sort == CODE.keys.sort, 'unexpected executable payload (drivers/installers/scripts are not distributed)')
    exact_entries!(app, %w[Contents])
    exact_entries!(File.join(app, 'Contents'), %w[Frameworks Helpers Info.plist MacOS Resources _CodeSignature])
    exact_entries!(File.join(app, 'Contents/MacOS'), %w[CaptureServer OpensteamerMediaBridge])
    exact_entries!(File.join(app, 'Contents/Resources'), %w[AppIcon.icns BuildSource.json Release.json Sparkle-LICENSE.txt ThirdPartyNotices.md org.example.opensteamer.media.json])
    exact_entries!(File.join(app, 'Contents/Frameworks'), %w[LiveKitWebRTC.framework Sparkle.framework])
    exact_entries!(File.join(app, 'Contents/Helpers'), %w[BelugaUpdater.app])
    exact_entries!(File.join(app, BROKER), %w[Contents])
    exact_entries!(File.join(app, "#{BROKER}/Contents"), %w[Frameworks Info.plist MacOS Resources _CodeSignature])
    exact_entries!(File.join(app, "#{BROKER}/Contents/MacOS"), %w[BelugaUpdater])
    exact_entries!(File.join(app, "#{BROKER}/Contents/Resources"), %w[BuildSource.json Release.json Sparkle-LICENSE.txt])
    exact_entries!(File.join(app, "#{BROKER}/Contents/Frameworks"), %w[Sparkle.framework])
    exact_entries!(File.join(app, "#{LIVEKIT}/Versions"), %w[A Current])
    exact_entries!(File.join(app, "#{LIVEKIT}/Versions/A"), %w[Headers LiveKitWebRTC Modules Resources Versions _CodeSignature])
    exact_entries!(File.join(app, "#{LIVEKIT}/Versions/A/Versions"), %w[A])
    exact_entries!(File.join(app, "#{LIVEKIT}/Versions/A/Versions/A"), %w[Resources])
    exact_entries!(File.join(app, "#{LIVEKIT}/Versions/A/Versions/A/Resources"), %w[PrivacyInfo.xcprivacy])
    SPARKLE_COPIES.each do |framework|
      spine = "#{framework}/Versions/B"
      exact_entries!(File.join(app, "#{framework}/Versions"), %w[B Current])
      exact_entries!(File.join(app, spine), %w[Autoupdate Headers Modules PrivateHeaders Resources Sparkle Updater.app XPCServices _CodeSignature])
      exact_entries!(File.join(app, "#{spine}/XPCServices"), %w[Downloader.xpc Installer.xpc])
    end
    require!(File.lstat(app).dev == root.dev && File.lstat(app).ino == root.ino, 'bundle root changed during tree validation')
  end

  def self.exact_entries!(path, expected)
    require!(Dir.children(path).sort == expected.sort, "unexpected bundle entries: #{path}")
  end

  # beluga.bundle-tree-json-v1 is the full signed app tree, including signature
  # resources and embedded frameworks/helpers, not an executable-only closure.
  # Find's preorder visits the root first and each directory's children in sorted
  # Ruby String order; symlinks are lstat'd and never traversed. For each node,
  # append compact UTF-8 JSON [relative, mode & 0777, ftype] with no separator or
  # newline to SHA-256. Root relative is ""; descendants retain the leading "/".
  # Append the raw readlink target bytes for a link, or lowercase ASCII hex of
  # SHA-256(file bytes) for a regular file. Directories add only their JSON tuple.
  # UID/GID, timestamps, inodes, ACLs and extended attributes are not digest
  # inputs; this digest never substitutes for the distribution verifier's gates.
  def self.tree_digest(path)
    digest = Digest::SHA256.new
    Find.find(path.b) do |node|
      # Filesystem names can be tagged binary under LC_ALL=C. Validate their
      # existing UTF-8 bytes, without transcoding or changing the digest format.
      relative = utf8_text(node.b.delete_prefix(path.b), 'bundle tree relative path')
      info = File.lstat(node)
      digest.update([relative, info.mode & 0o777, info.ftype].to_json)
      if info.symlink?
        digest.update(File.readlink(node))
        Find.prune
      elsif info.file?
        digest.update(Digest::SHA256.file(node).hexdigest)
      end
    end
    digest.hexdigest
  end

  def self.candidate_identity!(value, config:)
    require!(value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) } &&
             value.keys.sort == CANDIDATE_IDENTITY_KEYS, 'candidate identity schema keys differ')
    require!(value['schema'] == CANDIDATE_IDENTITY_SCHEMA &&
             value['bundleTreeAlgorithm'] == BUNDLE_TREE_ALGORITHM, 'candidate identity schema/algorithm differs')
    version = value['version']
    build = value['build']
    require!(version.is_a?(String) && version.bytesize <= 64 &&
             /\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/.match?(version) &&
             version.split('.').all? { |part| part.to_i <= 2**32 - 1 } &&
             version == config['version'], 'candidate version differs from verified release')
    require!(build.is_a?(Integer) && build > 0 && build <= 2**63 - 1 &&
             build == config['build'], 'candidate build differs from verified release')
    %w[executableSHA256 bundleTreeSHA256].each do |key|
      require!(value[key].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(value[key]), 'candidate digest is not canonical SHA-256')
    end
    value.freeze
  end

  # Caller first verifies signatures/closure and supplies the admitted full-tree
  # checkpoint. Hash the actual executable before the final unchanged-tree check,
  # so identity is derived from those verified app bytes, never a build-report guess.
  def self.candidate_identity_for_app!(app, config:, expected_tree_sha256:)
    canonical!(app)
    require!(expected_tree_sha256.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(expected_tree_sha256), 'missing verified app tree digest')
    paired_phone_catalog_plist!(File.join(app, 'Contents/Info.plist'))
    executable = File.join(app, 'Contents/MacOS/CaptureServer')
    regular!(executable)
    executable_sha256 = Digest::SHA256.file(executable).hexdigest
    actual_tree_sha256 = tree_digest(app)
    require!(actual_tree_sha256 == expected_tree_sha256, 'app changed while deriving candidate identity')
    candidate_identity!({
      'schema' => CANDIDATE_IDENTITY_SCHEMA, 'version' => config['version'], 'build' => config['build'],
      'executableSHA256' => executable_sha256, 'bundleTreeSHA256' => actual_tree_sha256,
      'bundleTreeAlgorithm' => BUNDLE_TREE_ALGORITHM
    }, config: config)
  end

  def self.tools!(directory)
    canonical!(directory)
    require!(File.directory?(directory), 'Sparkle tool directory is missing')
    SPARKLE_TOOLS.each do |name, expected|
      path = File.join(directory, name)
      regular!(path)
      require!(File.executable?(path) && Digest::SHA256.file(path).hexdigest == expected, 'Sparkle 2.10.0 signing tool bytes differ from pinned official artifact')
    end
  end

  def self.appcast(config, dmg_name, size, signature, now = Time.now, candidate_identity:)
    candidate_identity!(candidate_identity, config: config)
    require!(size.is_a?(Integer) && size > 0, 'empty update payload')
    require!(dmg_name == "Beluga-Mac-#{config['version']}-#{config['build']}.dmg", 'update filename differs from version')
    require!(Base64.strict_decode64(signature).bytesize == 64 && Base64.strict_encode64(Base64.strict_decode64(signature)) == signature, 'invalid update signature')
    url = "https://github.com/#{config['repository']}/releases/download/mac-v#{config['version']}/#{dmg_name}"
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:beluga="#{CANDIDATE_XML_NAMESPACE}">
        <channel>
          <title>Beluga Mac updates</title>
          <link>https://github.com/#{config['repository']}</link>
          <description>Signed Beluga Mac client releases</description>
          <language>en</language>
          <item>
            <title>Beluga #{config['version']}</title>
            <pubDate>#{now.utc.rfc2822}</pubDate>
            <sparkle:version>#{config['build']}</sparkle:version>
            <sparkle:shortVersionString>#{config['version']}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <enclosure url="#{url}" length="#{size}" type="application/octet-stream" sparkle:edSignature="#{signature}" beluga:artifactSchema="#{candidate_identity['schema']}" beluga:executableSHA256="#{candidate_identity['executableSHA256']}" beluga:bundleTreeSHA256="#{candidate_identity['bundleTreeSHA256']}" beluga:bundleTreeAlgorithm="#{candidate_identity['bundleTreeAlgorithm']}" />
          </item>
        </channel>
      </rss>
    XML
  rescue ArgumentError
    raise Refusal, 'invalid update signature'
  end
end
