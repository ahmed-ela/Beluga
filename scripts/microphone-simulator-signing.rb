#!/usr/bin/ruby
# Simulator artifact evidence only. This never builds, signs, installs, or launches.
require 'digest'
require 'json'
require 'open3'
require 'rexml/document'

module MicrophoneSimulatorSigning
  class Refusal < StandardError; end

  DEPENDENCIES = ['/usr/bin/codesign', '/usr/bin/plutil'].map(&:freeze).freeze
  BUNDLE_ID = 'org.example.AudioStreamer.dev'.freeze
  APPLICATION_ID = 'MSMG8CJLB3.org.example.AudioStreamer.dev'.freeze
  MEDIA_GROUP = 'group.org.example.AudioStreamer.dev.media'.freeze
  MAX_EXECUTABLE_BYTES = 64 * 1024 * 1024
  MAX_INFO_BYTES = 1024 * 1024
  MAX_XML_BYTES = 2 * 1024 * 1024
  MAX_ENTITLEMENT_BYTES = 4096
  MAX_SIGNATURE_BYTES = 1024 * 1024
  MAX_TOOL_BYTES = 2 * 1024 * 1024
  MAX_RECORD_BYTES = 8192
  U64_MAX = (1 << 64) - 1
  PLIST_DOCTYPE = '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'.freeze
  STAT_KEYS = %w[device inode uid gid mode size mtimeNanoseconds ctimeNanoseconds].freeze
  FILE_KEYS = %w[path sha256 stat].freeze
  SECTION_KEYS = %w[offset length sha256].freeze

  def self.require!(condition, reason)
    raise Refusal, reason unless condition
  end

  def self.der_value(tag, bytes)
    size = bytes.bytesize
    length = if size < 128
               [size].pack('C')
             else
               octets = []; n = size
               while n > 0
                 octets.unshift(n & 255); n >>= 8
               end
               [128 | octets.length, *octets].pack('C*')
             end
    [tag].pack('C') + length + bytes.b
  end
  # The pinned Xcode representation, not a general DER-entitlement decoder.
  CANONICAL_DER = der_value(0x70, der_value(2, "\x01".b) + der_value(0xb0,
    der_value(0x30, der_value(0x0c, 'application-identifier') + der_value(0x0c, APPLICATION_ID)) +
    der_value(0x30, der_value(0x0c, 'com.apple.security.application-groups') +
      der_value(0x30, der_value(0x0c, MEDIA_GROUP))))).freeze
  DER_SHA256 = Digest::SHA256.hexdigest(CANONICAL_DER).freeze

  def self.absolute_path?(path)
    path.is_a?(String) && path.bytesize <= 4096 && path.start_with?('/') &&
      !path.match?(/[\x00\r\n]/) && File.expand_path(path) == path
  end

  def self.stat_record(stat)
    { 'device' => stat.dev, 'inode' => stat.ino, 'uid' => stat.uid, 'gid' => stat.gid,
      'mode' => stat.mode, 'size' => stat.size,
      'mtimeNanoseconds' => stat.mtime.to_i * 1_000_000_000 + stat.mtime.nsec,
      'ctimeNanoseconds' => stat.ctime.to_i * 1_000_000_000 + stat.ctime.nsec }
  end

  def self.read_regular(path, maximum)
    require!(absolute_path?(path) && File.realpath(path) == path, 'artifact path is not canonical')
    before = File.lstat(path)
    require!(before.file? && !before.symlink? && before.size > 0 && before.size <= maximum,
             'artifact is not a bounded regular file')
    bytes = nil
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      require!(stat_record(file.stat) == stat_record(before), 'artifact changed while opening')
      bytes = file.read(maximum + 1)
      require!(bytes && bytes.bytesize == before.size && bytes.bytesize <= maximum &&
               stat_record(file.stat) == stat_record(before), 'artifact changed while reading')
    end
    require!(File.realpath(path) == path && stat_record(File.lstat(path)) == stat_record(before),
             'artifact path or identity changed')
    [{ 'path' => path, 'sha256' => Digest::SHA256.hexdigest(bytes), 'stat' => stat_record(before) }, bytes]
  rescue SystemCallError
    raise Refusal, 'artifact is missing or unreadable', cause: nil
  end

  def self.parse_plist(xml, maximum = MAX_XML_BYTES)
    require!(xml.is_a?(String) && xml.bytesize <= maximum, 'plist exceeds bounded input')
    text = xml.dup.force_encoding(Encoding::UTF_8)
    require!(text.valid_encoding?, 'plist encoding is invalid')
    # Remove only the standard non-entity DTD; no internal/external entities,
    # comments, CDATA or arbitrary processing instructions are supported.
    text = text.sub(/\A\s*<\?xml version="1\.0" encoding="UTF-8"\?>/, '')
    text = text.sub(/\A\s*#{Regexp.escape(PLIST_DOCTYPE)}/, '')
    require!(!text.include?('<!') && !text.include?('<?'), 'plist declarations are unsupported')
    require!(text.count('<') <= 4096, 'plist token bound is invalid')
    tokens = text.scan(/<[^<>]*>/m)
    require!(tokens.length <= 4096 && tokens.length == text.count('<'), 'plist token bound is invalid')
    stack = []
    tokens.each do |token|
      match = /\A<(\/)?([a-z]+)(?: version="1\.0")?(\/)?\s*>\z/.match(token)
      require!(match, 'plist tag is malformed')
      if match[1]
        require!(!match[3] && stack.pop == match[2], 'plist nesting is malformed')
      elsif !match[3]
        stack << match[2]
        require!(stack.length <= 16, 'plist nesting exceeds bound')
      end
    end
    require!(stack.empty?, 'plist nesting is incomplete')
    document = REXML::Document.new(text)
    root = document.root
    attributes = root && root.attributes.each_attribute.map { |attribute| [attribute.name, attribute.value] }.to_h
    require!(root && root.name == 'plist' && attributes == { 'version' => '1.0' } &&
             document.elements.to_a.length == 1 && root.elements.to_a.length == 1 &&
             root.texts.all? { |value| value.value.strip.empty? }, 'plist root is invalid')
    parse_plist_element(root.elements[1])
  rescue REXML::ParseException
    raise Refusal, 'plist XML is malformed (contents redacted)', cause: nil
  end

  def self.parse_plist_element(element)
    require!(element.attributes.empty?, 'plist value attributes are unsupported')
    children = element.elements.to_a
    case element.name
    when 'dict'
      require!(children.length.even? && element.texts.all? { |text| text.value.strip.empty? }, 'plist dictionary is malformed')
      result = {}
      children.each_slice(2) do |key, value|
        require!(key.name == 'key' && key.attributes.empty? && key.elements.to_a.empty?, 'plist key is malformed')
        name = key.texts.map(&:value).join
        require!(!result.key?(name), 'plist duplicate key is forbidden')
        result[name] = parse_plist_element(value)
      end
      result
    when 'array'
      require!(element.texts.all? { |text| text.value.strip.empty? }, 'plist array is malformed')
      children.map { |child| parse_plist_element(child) }
    when 'string', 'integer'
      require!(children.empty?, 'plist scalar contains elements')
      value = element.texts.map(&:value).join
      if element.name == 'integer'
        require!(value.match?(/\A-?[0-9]{1,20}\z/), 'plist integer is invalid')
        value = value.to_i
        require!((-(1 << 63)..U64_MAX).cover?(value), 'plist integer width is invalid')
      end
      value
    when 'true', 'false'
      require!(children.empty? && element.texts.all? { |text| text.value.strip.empty? }, 'plist boolean is malformed')
      element.name == 'true'
    else
      raise Refusal, 'plist value type is unsupported'
    end
  end
  private_class_method :parse_plist_element

  def self.validate_info(info)
    require!(info.is_a?(Hash) && info['CFBundleIdentifier'] == BUNDLE_ID &&
             info['CFBundleExecutable'] == 'Beluga' && info['CFBundlePackageType'] == 'APPL' &&
             info['CFBundleSupportedPlatforms'] == ['iPhoneSimulator'] &&
             info['DTPlatformName'] == 'iphonesimulator' && info['BelugaMediaAppGroup'] == MEDIA_GROUP,
             'app Info identity is not the exact development Simulator app')
    { 'bundleIdentifier' => BUNDLE_ID, 'executable' => 'Beluga', 'bundlePackageType' => 'APPL',
      'supportedPlatforms' => ['iPhoneSimulator'], 'platformName' => 'iphonesimulator',
      'mediaAppGroup' => MEDIA_GROUP }
  end

  def self.range!(offset, length, total, reason)
    require!(offset.is_a?(Integer) && length.is_a?(Integer) && offset >= 0 && length >= 0 &&
             offset <= total && length <= total - offset, reason)
  end

  def self.macho_name(bytes)
    name, padding = bytes.split("\x00", 2)
    require!(padding.nil? || padding.bytes.all?(&:zero?), 'Mach-O fixed name is noncanonical')
    name
  end
  private_class_method :macho_name

  def self.parse_macho(bytes)
    require!(bytes.is_a?(String) && bytes.bytesize >= 32 && bytes.bytesize <= MAX_EXECUTABLE_BYTES,
             'Mach-O input size is invalid')
    u32 = ->(offset) { range!(offset, 4, bytes.bytesize, 'Mach-O scalar is out of bounds'); bytes.byteslice(offset, 4).unpack1('V') }
    u64 = ->(offset) { range!(offset, 8, bytes.bytesize, 'Mach-O scalar is out of bounds'); bytes.byteslice(offset, 8).unpack1('Q<') }
    require!(u32.call(0) == 0xfeedfacf && u32.call(4) == 0x0100000c && u32.call(8) == 0 &&
             u32.call(12) == 2 && u32.call(28) == 0, 'Mach-O must be thin little-endian arm64 MH_EXECUTE')
    count = u32.call(16); command_bytes = u32.call(20)
    require!(count > 0 && count <= 128 && command_bytes <= 65536, 'Mach-O load-command count exceeds bound')
    range!(32, command_bytes, bytes.bytesize, 'Mach-O load commands exceed file')
    cursor = 32; text = nil; sections = {}; build = nil; signature = nil
    count.times do
      range!(cursor, 8, 32 + command_bytes, 'Mach-O load command header exceeds table')
      command = u32.call(cursor); size = u32.call(cursor + 4)
      require!(size >= 8 && size % 8 == 0, 'Mach-O load command size is invalid')
      range!(cursor, size, 32 + command_bytes, 'Mach-O load command exceeds table')
      if command == 0x19
        require!(size >= 72, 'Mach-O segment is incomplete')
        nsects = u32.call(cursor + 64)
        require!(nsects <= 32 && size == 72 + nsects * 80, 'Mach-O segment section geometry is invalid')
        name = macho_name(bytes.byteslice(cursor + 8, 16))
        fileoff = u64.call(cursor + 40); filesize = u64.call(cursor + 48)
        range!(fileoff, filesize, bytes.bytesize, 'Mach-O segment exceeds file')
        if name == '__TEXT'
          require!(text.nil? && fileoff == 0 && filesize > 0, 'Mach-O __TEXT segment is missing or duplicate')
          text = { 'fileSize' => filesize, 'vmAddress' => u64.call(cursor + 24) }
        end
        nsects.times do |index|
          base = cursor + 72 + index * 80
          section_name = macho_name(bytes.byteslice(base, 16))
          section_segment = macho_name(bytes.byteslice(base + 16, 16))
          next unless %w[__entitlements __ents_der].include?(section_name)
          require!(name == '__TEXT' && section_segment == '__TEXT' && !sections.key?(section_name),
                   'Mach-O entitlement section is misplaced or duplicate')
          offset = u32.call(base + 48); length = u64.call(base + 40)
          range!(offset, length, fileoff + filesize, 'Mach-O entitlement section exceeds segment')
          require!(length > 0 && length <= MAX_ENTITLEMENT_BYTES && offset >= 32 + command_bytes &&
                   u64.call(base + 32) == u64.call(cursor + 24) + offset &&
                   [52, 56, 60, 64, 68, 72, 76].all? { |field| u32.call(base + field) == 0 },
                   'Mach-O entitlement section geometry is invalid')
          sections[section_name] = { 'offset' => offset, 'length' => length,
            'sha256' => Digest::SHA256.hexdigest(bytes.byteslice(offset, length)) }
        end
      elsif command == 0x32
        require!(build.nil? && size >= 24 && u32.call(cursor + 8) == 7 &&
                 u32.call(cursor + 20) <= 16 && size == 24 + u32.call(cursor + 20) * 8,
                 'Mach-O Simulator build-version command is invalid or duplicate')
        build = 7
      elsif command == 0x1d
        require!(signature.nil? && size == 16, 'Mach-O code signature command is invalid or duplicate')
        signature = { 'offset' => u32.call(cursor + 8), 'length' => u32.call(cursor + 12) }
        require!(signature['length'] >= 12 && signature['length'] <= MAX_SIGNATURE_BYTES,
                 'Mach-O embedded signature size is invalid')
        range!(signature['offset'], signature['length'], bytes.bytesize, 'Mach-O embedded signature exceeds file')
      elsif [0x24, 0x25, 0x2f, 0x30].include?(command)
        raise Refusal, 'Mach-O legacy platform commands are unsupported'
      end
      cursor += size
    end
    require!(cursor == 32 + command_bytes && text && build && signature &&
             sections.keys.sort == %w[__entitlements __ents_der].sort,
             'Mach-O required Simulator signing commands or sections are absent')
    xml = sections.fetch('__entitlements'); der = sections.fetch('__ents_der')
    require!(xml['offset'] + xml['length'] <= der['offset'] ||
             der['offset'] + der['length'] <= xml['offset'], 'Mach-O entitlement sections overlap')
    entitlement = parse_plist(bytes.byteslice(xml['offset'], xml['length']), MAX_ENTITLEMENT_BYTES)
    require!(entitlement == { 'application-identifier' => APPLICATION_ID,
                             'com.apple.security.application-groups' => [MEDIA_GROUP] },
             'Mach-O development entitlements are not exact')
    require!(bytes.byteslice(der['offset'], der['length']) == CANONICAL_DER,
             'Mach-O DER does not match the exact canonical XML entitlement identity')
    directory = parse_code_directory(bytes, signature, text['fileSize'])
    [xml, der].each do |section|
      range!(section['offset'], section['length'], directory['codeLimit'],
             'Mach-O entitlements are not covered by the CodeDirectory')
    end
    { 'architecture' => 'arm64', 'platform' => 7, 'fileType' => 2,
      'xml' => xml, 'der' => der, 'codeSignature' => signature, 'codeDirectory' => directory,
      'xmlDerParity' => true, 'coveredCodePagesVerified' => true }
  end

  def self.parse_code_directory(bytes, signature, text_size)
    start = signature['offset']; total = signature['length']
    read = ->(offset) { range!(offset, 4, start + total, 'signature scalar exceeds bounds'); bytes.byteslice(offset, 4).unpack1('N') }
    require!(read.call(start) == 0xfade0cc0, 'embedded signature is not a SuperBlob')
    length = read.call(start + 4); count = read.call(start + 8)
    require!(length >= 12 && length <= total && count > 0 && count <= 16 && 12 + count * 8 <= length,
             'embedded signature table geometry is invalid')
    slots = {}; ranges = []; directory = nil
    count.times do |index|
      type = read.call(start + 12 + index * 8); offset = read.call(start + 16 + index * 8)
      require!(!slots.key?(type) && offset >= 12 + count * 8 && offset <= length - 8,
               'embedded signature slot is duplicate or out of bounds')
      slots[type] = true
      blob_size = read.call(start + offset + 4)
      range!(offset, blob_size, length, 'embedded signature blob exceeds bounds')
      require!(blob_size >= 8 && ranges.all? { |first, size| offset + blob_size <= first || first + size <= offset },
               'embedded signature blobs overlap')
      ranges << [offset, blob_size]
      require!(!(0x1000..0x1005).cover?(type), 'alternate CodeDirectories are unsupported')
      directory = [start + offset, blob_size] if type == 0
    end
    require!(directory, 'primary CodeDirectory is absent')
    offset, size = directory
    require!(size >= 88 && read.call(offset) == 0xfade0c02 && read.call(offset + 8) == 0x20400 &&
             read.call(offset + 12) == 2, 'CodeDirectory version or ad-hoc flags are unsupported')
    hash_offset = read.call(offset + 16); identifier_offset = read.call(offset + 20)
    special_count = read.call(offset + 24); code_count = read.call(offset + 28); limit = read.call(offset + 32)
    require!(special_count <= 16 && code_count > 0 && limit == start &&
             bytes.getbyte(offset + 36) == 32 && bytes.getbyte(offset + 37) == 2 &&
             bytes.getbyte(offset + 38) == 0 && bytes.getbyte(offset + 39) == 14 &&
             [40, 44, 48, 52, 56, 60, 64, 68].all? { |field| read.call(offset + field) == 0 } &&
             bytes.byteslice(offset + 72, 8).unpack1('Q>') == text_size &&
             bytes.byteslice(offset + 80, 8).unpack1('Q>') == 1,
             'CodeDirectory contiguous SHA256 coverage geometry is unsupported')
    require!(code_count == (limit + 16383) / 16384 && hash_offset >= 88 + special_count * 32 &&
             hash_offset + code_count * 32 == size && identifier_offset >= 88 &&
             identifier_offset < hash_offset - special_count * 32,
             'CodeDirectory hash or identifier geometry is invalid')
    identifier_room = hash_offset - special_count * 32 - identifier_offset
    identifier = bytes.byteslice(offset + identifier_offset, identifier_room).split("\x00", 2).first
    require!(identifier == BUNDLE_ID && bytes.getbyte(offset + identifier_offset + identifier.bytesize) == 0,
             'CodeDirectory identifier is not the development app')
    code_count.times do |index|
      page_offset = index * 16384; page_size = [16384, limit - page_offset].min
      require!(Digest::SHA256.digest(bytes.byteslice(page_offset, page_size)) ==
               bytes.byteslice(offset + hash_offset + index * 32, 32), 'CodeDirectory code-page hash differs')
    end
    { 'offset' => offset, 'length' => size, 'sha256' => Digest::SHA256.hexdigest(bytes.byteslice(offset, size)),
      'version' => 0x20400, 'flags' => 2, 'codeLimit' => limit, 'codeSlots' => code_count,
      'pageSizeLog2' => 14, 'hashType' => 2, 'hashSize' => 32 }
  end
  private_class_method :parse_code_directory

  def self.run_tool(argv)
    output = ''.b; errors = ''.b; status = nil
    Open3.popen3(*argv, pgroup: true) do |input, stdout, stderr, waiter|
      input.close; streams = [stdout, stderr]
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
      begin
        until streams.empty?
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          require!(remaining > 0, 'signing collector tool deadline expired')
          ready = IO.select(streams, nil, nil, [remaining, 0.25].min)
          next unless ready
          ready[0].each do |stream|
            part = stream.read_nonblock(16384, exception: false)
            if part.nil?
              streams.delete(stream); stream.close
            elsif part != :wait_readable
              (stream == stdout ? output : errors) << part
              require!(output.bytesize + errors.bytesize <= MAX_TOOL_BYTES, 'signing collector tool output exceeds bound')
            end
          end
        end
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        require!(remaining > 0 && waiter.join(remaining), 'signing collector tool deadline expired')
        status = waiter.value
      ensure
        if waiter.alive?
          begin Process.kill('KILL', -waiter.pid); rescue Errno::ESRCH; end
          waiter.join
        end
      end
    end
    [output, status.success?]
  rescue SystemCallError, IOError
    raise Refusal, 'signing collector tool failed', cause: nil
  end
  private_class_method :run_tool

  def self.collect(app)
    collect_with_executor(app, method(:run_tool))
  end

  # Private injection seam for offline refusal fixtures only; the CLI cannot
  # select an executor, tool path, signature skip, architecture, or identity.
  def self.collect_with_executor(app, executor)
    require!(absolute_path?(app) && app.end_with?('.app') && File.realpath(app) == app,
             'app path is not a canonical absolute app bundle')
    app_stat = File.lstat(app)
    require!(app_stat.directory? && !app_stat.symlink?, 'app bundle is not a regular directory')
    info_file, = read_regular(app + '/Info.plist', MAX_INFO_BYTES)
    executable_file, executable_bytes = read_regular(app + '/Beluga', MAX_EXECUTABLE_BYTES)
    pin = lambda do
      require!(File.realpath(app) == app && stat_record(File.lstat(app)) == stat_record(app_stat), 'app bundle identity changed')
      require!(read_regular(info_file['path'], MAX_INFO_BYTES).first == info_file &&
               read_regular(executable_file['path'], MAX_EXECUTABLE_BYTES).first == executable_file,
               'app executable or Info identity changed during collection')
    end
    verify = lambda do
      output, success = executor.call([DEPENDENCIES[0], '--verify', '--strict', app])
      require!(output.is_a?(String) && output.bytesize <= MAX_TOOL_BYTES && success == true,
               'strict app signature verification failed')
      pin.call
    end
    verify.call
    info_xml, success = executor.call([DEPENDENCIES[1], '-convert', 'xml1', '-o', '-', '--', info_file['path']])
    require!(success == true && info_xml.is_a?(String) && info_xml.bytesize <= MAX_XML_BYTES,
             'app Info collection failed')
    pin.call
    info_identity = validate_info(parse_plist(info_xml))
    proof = parse_macho(executable_bytes)
    verify.call
    record = { 'schema' => 'beluga.microphone.simulator-signing.v1',
      'claim' => 'signed-arm64-simulator-development-appgroup', 'appPath' => app,
      'appStat' => stat_record(app_stat), 'info' => info_file.merge(info_identity),
      'executable' => executable_file.merge(proof), 'applicationIdentifier' => APPLICATION_ID,
      'applicationGroups' => [MEDIA_GROUP], 'infoTool' => DEPENDENCIES[1],
      'signature' => { 'tool' => DEPENDENCIES[0], 'before' => true, 'after' => true } }
    validate_record(record, expected_app: app)
    record
  rescue SystemCallError
    raise Refusal, 'app artifact is missing or unreadable', cause: nil
  end
  private_class_method :collect_with_executor

  def self.keys!(value, keys)
    require!(value.is_a?(Hash) && value.keys.sort == keys.sort, 'signing record field set is invalid')
  end
  private_class_method :keys!

  def self.validate_record(record, expected_app: nil)
    # Replay validates captured evidence, not a live app or an unauthenticated
    # record. The caller must pin the retained record's digest and collector/tool.
    keys!(record, %w[schema claim appPath appStat info executable applicationIdentifier applicationGroups infoTool signature])
    require!(record['schema'] == 'beluga.microphone.simulator-signing.v1' &&
             record['claim'] == 'signed-arm64-simulator-development-appgroup' &&
             absolute_path?(record['appPath']) && record['appPath'].end_with?('.app') &&
             (expected_app.nil? || record['appPath'] == expected_app) &&
             record['applicationIdentifier'] == APPLICATION_ID && record['applicationGroups'] == [MEDIA_GROUP] &&
             record['infoTool'] == DEPENDENCIES[1], 'signing record identity is invalid')
    stat_valid = lambda do |stat, type, maximum|
      keys!(stat, STAT_KEYS)
      require!(stat.values.all? { |value| value.is_a?(Integer) && (0..U64_MAX).cover?(value) } &&
               stat['inode'] > 0 && stat['mode'] & 0o170000 == type && stat['size'] <= maximum,
               'signing record filesystem identity is invalid')
    end
    stat_valid.call(record['appStat'], 0o040000, U64_MAX)
    sha_valid = ->(sha) { sha.is_a?(String) && sha.match?(/\A[0-9a-f]{64}\z/) }
    info = record['info']; executable = record['executable']
    keys!(info, FILE_KEYS + %w[bundleIdentifier executable bundlePackageType supportedPlatforms platformName mediaAppGroup])
    keys!(executable, FILE_KEYS + %w[architecture platform fileType xml der codeSignature codeDirectory xmlDerParity coveredCodePagesVerified])
    [[info, 'Info.plist', MAX_INFO_BYTES], [executable, 'Beluga', MAX_EXECUTABLE_BYTES]].each do |file, name, maximum|
      require!(file['path'] == record['appPath'] + '/' + name && sha_valid.call(file['sha256']), 'signing record file path or hash is invalid')
      stat_valid.call(file['stat'], 0o100000, maximum)
      require!(file['stat']['size'] > 0, 'signing record file is empty')
    end
    require!(executable['platform'].is_a?(Integer) && executable['fileType'].is_a?(Integer) &&
             info.values_at('bundleIdentifier', 'executable', 'bundlePackageType', 'supportedPlatforms', 'platformName', 'mediaAppGroup') ==
             [BUNDLE_ID, 'Beluga', 'APPL', ['iPhoneSimulator'], 'iphonesimulator', MEDIA_GROUP] &&
             executable.values_at('architecture', 'platform', 'fileType', 'xmlDerParity', 'coveredCodePagesVerified') ==
             ['arm64', 7, 2, true, true], 'signing record Simulator proof is invalid')
    signature = executable['codeSignature']; directory = executable['codeDirectory']
    keys!(signature, %w[offset length])
    keys!(directory, %w[offset length sha256 version flags codeLimit codeSlots pageSizeLog2 hashType hashSize])
    keys!(record['signature'], %w[tool before after])
    require!(record['signature'] == { 'tool' => DEPENDENCIES[0], 'before' => true, 'after' => true } &&
             directory.values_at('version', 'flags', 'pageSizeLog2', 'hashType', 'hashSize') == [0x20400, 2, 14, 2, 32] &&
             sha_valid.call(directory['sha256']), 'signing record signature or CodeDirectory proof is invalid')
    integer_fields = signature.values + directory.reject { |key, _value| key == 'sha256' }.values
    require!(integer_fields.all? { |value| value.is_a?(Integer) && (0..U64_MAX).cover?(value) }, 'signing record coverage scalar is invalid')
    size = executable['stat']['size']
    range!(signature['offset'], signature['length'], size, 'signing record signature exceeds file')
    range!(directory['offset'], directory['length'], signature['offset'] + signature['length'], 'signing record CodeDirectory exceeds signature')
    require!(signature['length'].between?(12, MAX_SIGNATURE_BYTES) && directory['offset'] >= signature['offset'] + 12 &&
             directory['length'] >= 88 && directory['codeLimit'] == signature['offset'] &&
             directory['codeSlots'] > 0 && directory['codeSlots'] == (directory['codeLimit'] + 16383) / 16384,
             'signing record code coverage geometry is invalid')
    %w[xml der].each do |name|
      section = executable[name]; keys!(section, SECTION_KEYS)
      require!(sha_valid.call(section['sha256']) && section['length'].is_a?(Integer) &&
               section['length'].between?(1, MAX_ENTITLEMENT_BYTES), 'signing record section evidence is invalid')
      range!(section['offset'], section['length'], directory['codeLimit'], 'signing record section lacks signed coverage')
    end
    xml = executable['xml']; der = executable['der']
    require!(der['length'] == CANONICAL_DER.bytesize && der['sha256'] == DER_SHA256 &&
             (xml['offset'] + xml['length'] <= der['offset'] || der['offset'] + der['length'] <= xml['offset']),
             'signing record canonical DER parity or section geometry is invalid')
    require!(JSON.generate(record).bytesize <= MAX_RECORD_BYTES, 'signing record exceeds bound')
    true
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    MicrophoneSimulatorSigning.require!(ARGV.length == 1, 'usage: microphone-simulator-signing.rb ABSOLUTE_SIMULATOR_APP')
    puts JSON.generate(MicrophoneSimulatorSigning.collect(ARGV[0]))
  rescue MicrophoneSimulatorSigning::Refusal
    warn 'microphone Simulator signing refused (artifact contents redacted)'
    exit 1
  end
end
