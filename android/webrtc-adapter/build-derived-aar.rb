require 'digest'
require 'json'
require 'zlib'
require 'fileutils'
require_relative 'build-command'

module DerivedWebRtcAar
  class Invalid < StandardError; end
  class UniqueHash < Hash
    def []=(key, value)
      raise Invalid, 'Duplicate JSON field' if key?(key)
      super
    end
  end
  ROOT = File.realpath(__dir__)
  RAW_SHA = '8ad5e5fd02f0177743ddb566bea329006bef7689b944f6351717cd1d018958c0'
  JAR_SHA = '737a44bde15d6bd7108bfb756c4772985dea77d8f87e27e2f70ff4b3b1921a10'
  SOURCE_SHA = '96c77cbea46cb507e22c39118cbcff6989d7473d1061e3a5a09b46a631d8560b'
  SDK_SHA = 'd9eb9da824d9e247a352f570f01e1169e725b2954bca9e283a71786c59b59f9a'
  ANNOTATIONS_SHA = '1e343917ebf27ba96fe4dc52b1cad7fd32b738fbc6355bb6cd5b3b305d7212d0'
  NOTICES = {'LICENSE.webrtc' => 'ab00a482b6a3902e40211b43c5d0441962ea99b6cc7c25c0f243fa270b78d482',
    'PATENTS.webrtc' => '01462e2068d1a04c2274f3389773014c14ed9bc3446b28303543bd3e3c064145'}.freeze
  NATIVE = {'armeabi-v7a' => '762f3d5e1c4c69c3f02f2383540f40e1142cb631e9d99e86bdb1602f4c277559',
    'arm64-v8a' => '7b299113fcd743de7dc5559686b21fc2681b2c8598347d8dc0743d2e004995ca',
    'x86' => '80e7b1b7e07bb5a53841a8cacabf942a6f3eb8ee9759a1731741dd912f367f19',
    'x86_64' => '0717afcc43da0c1aabd904f9ef0653efc8f3d37b5750f39a123697e7910b623a'}.freeze
  PREFIX = 'org/webrtc/audio/'
  ORIGINAL_CLASSES = [PREFIX + 'WebRtcAudioTrack.class', PREFIX + 'WebRtcAudioTrack$AudioTrackThread.class'].freeze
  OUTPUT_CLASSES = (ORIGINAL_CLASSES + [PREFIX + 'WebRtcAudioTrack$OutputLease.class',
    PREFIX + 'PlaybackOutputObserver.class']).sort.freeze
  MAX_ARCHIVE = 96 * 1024 * 1024
  MAX_ENTRY = 32 * 1024 * 1024
  module_function
  def require!(condition, message); raise Invalid, message unless condition; end
  def digest(bytes); Digest::SHA256.hexdigest(bytes); end
  def parse(bytes); JSON.parse(bytes, object_class: UniqueHash); end
  def canonical_file(path, limit = MAX_ARCHIVE)
    require!(path.is_a?(String) && path.start_with?('/') && !path.include?("\0"), 'Absolute input required')
    stat = File.lstat(path)
    require!(stat.file? && !stat.symlink? && File.realpath(path) == path && stat.size <= limit, 'Unsafe input file')
    path
  end
  def file_bytes(path, limit = MAX_ARCHIVE)
    canonical_file(path, limit)
    bytes = File.binread(path, limit + 1) || ''.b
    require!(bytes.bytesize <= limit, 'Input size bound')
    bytes
  end
  def write_new(path, bytes)
    File.open(path, 'wx', 0600) { |file| file.write(bytes) }
  end
  def canonical_json(value)
    case value
    when Hash then '{' + value.keys.sort.map { |key| JSON.generate(key) + ':' + canonical_json(value.fetch(key)) }.join(',') + '}'
    when Array then '[' + value.map { |entry| canonical_json(entry) }.join(',') + ']'
    else JSON.generate(value)
    end
  end
  def name!(name)
    require!(name.is_a?(String) && name.ascii_only? && name.match?(/\A[A-Za-z0-9_.$+\/-]+\z/) &&
      !name.start_with?('/') && !name.end_with?('/') &&
      name.split('/').none? { |part| part.empty? || part == '.' || part == '..' }, 'Unsafe archive path')
  end
  def take(bytes, offset, length)
    require!(offset >= 0 && length >= 0 && offset + length <= bytes.bytesize, 'Truncated ZIP')
    bytes.byteslice(offset, length)
  end
  def u16(bytes, offset); take(bytes, offset, 2).unpack1('v'); end
  def u32(bytes, offset); take(bytes, offset, 4).unpack1('V'); end
  def inflate(payload, size)
    decoder = Zlib::Inflate.new(-Zlib::MAX_WBITS); output = +''.b
    begin
      (0...payload.bytesize).step(16_384) do |offset|
        output << decoder.inflate(payload.byteslice(offset, 16_384))
        require!(output.bytesize <= size, 'Expanded ZIP entry exceeds declared size')
      end
      output << decoder.finish
      require!(decoder.finished? && decoder.total_in == payload.bytesize && output.bytesize == size, 'Incomplete ZIP deflate stream')
      output
    ensure
      decoder.close
    end
  end
  def read_zip(bytes)
    require!(bytes.bytesize.between?(22, MAX_ARCHIVE), 'ZIP size bound')
    ending = bytes.rindex("PK\x05\x06".b)
    require!(ending && ending + 22 <= bytes.bytesize, 'Missing ZIP end')
    require!(u16(bytes, ending + 4).zero? && u16(bytes, ending + 6).zero? &&
      ending + 22 + u16(bytes, ending + 20) == bytes.bytesize, 'Split/trailing ZIP')
    count = u16(bytes, ending + 10); cursor = u32(bytes, ending + 16)
    require!(count.between?(1, 2048) && u16(bytes, ending + 8) == count &&
      cursor + u32(bytes, ending + 12) == ending, 'ZIP central bounds')
    central = cursor; entries = {}; ranges = []; expanded = 0
    count.times do
      require!(take(bytes, cursor, 4) == "PK\x01\x02".b, 'Bad central record')
      flags = u16(bytes, cursor + 8); method = u16(bytes, cursor + 10)
      crc = u32(bytes, cursor + 16); compressed = u32(bytes, cursor + 20); size = u32(bytes, cursor + 24)
      n = u16(bytes, cursor + 28); extra = u16(bytes, cursor + 30); comment = u16(bytes, cursor + 32)
      name = take(bytes, cursor + 46, n); name!(name)
      mode = u32(bytes, cursor + 38) >> 16
      require!(!entries.key?(name) && [0, 8].include?(method) && (flags & ~0x808).zero? &&
        u16(bytes, cursor + 34).zero? && [0, 0100000].include?(mode & 0170000), 'Duplicate/encrypted/nonregular ZIP entry')
      require!(size <= MAX_ENTRY && compressed <= MAX_ARCHIVE && (expanded += size) <= MAX_ARCHIVE, 'ZIP expansion bound')
      local = u32(bytes, cursor + 42)
      require!(take(bytes, local, 4) == "PK\x03\x04".b && u16(bytes, local + 6) == flags &&
        u16(bytes, local + 8) == method && u16(bytes, local + 26) == n, 'Local ZIP header differs')
      require!(take(bytes, local + 30, n) == name, 'Local ZIP name differs')
      start = local + 30 + n + u16(bytes, local + 28); finish = start + compressed
      if (flags & 8).zero?
        require!([u32(bytes, local + 14), u32(bytes, local + 18), u32(bytes, local + 22)] == [crc, compressed, size], 'Local ZIP sizes differ')
      else
        descriptor = finish
        descriptor += 4 if take(bytes, descriptor, 4) == "PK\x07\x08".b
        require!(take(bytes, descriptor, 12).unpack('VVV') == [crc, compressed, size], 'ZIP descriptor differs')
        finish = descriptor + 12
      end
      require!(finish <= central, 'ZIP entry overlaps central directory')
      ranges << [local, finish]
      payload = take(bytes, start, compressed)
      payload = inflate(payload, size) if method == 8
      require!(payload.bytesize == size && Zlib.crc32(payload) == crc, 'ZIP payload size/CRC differs')
      entries[name] = payload
      cursor += 46 + n + extra + comment
      require!(cursor <= ending, 'Central record exceeds bounds')
    end
    require!(cursor == ending, 'Central record count differs')
    position = 0
    ranges.sort.each { |first, last| require!(first == position, 'Overlapping/gapped ZIP entries'); position = last }
    require!(position == central, 'Unclaimed ZIP bytes')
    entries
  end
  def write_zip(entries)
    require!(entries.is_a?(Hash) && entries.length.between?(1, 2048), 'ZIP entry count')
    body = +''.b; central = +''.b
    entries.keys.sort.each do |name|
      name!(name); data = entries.fetch(name).b
      require!(data.bytesize <= MAX_ENTRY, 'ZIP entry bound')
      offset = body.bytesize; crc = Zlib.crc32(data); size = data.bytesize
      # Stored payloads, fixed DOS date 1980-01-01, sorted names, regular mode0644.
      body << [0x04034b50, 20, 0, 0, 0, 33, crc, size, size, name.bytesize, 0].pack('VvvvvvVVVvv') << name << data
      central << [0x02014b50, 0x314, 20, 0, 0, 0, 33, crc, size, size,
        name.bytesize, 0, 0, 0, 0, 0100644 << 16, offset].pack('VvvvvvvVVVvvvvvVV') << name
      require!(body.bytesize + central.bytesize + 22 <= MAX_ARCHIVE, 'Output ZIP size bound')
    end
    body + central + [0x06054b50, 0, 0, entries.length, entries.length, central.bytesize, body.bytesize, 0].pack('VvvvvVVv')
  end
  def apply_patch(source, patch)
    original = source.lines; lines = patch.lines
    require!(source.end_with?("\n") && patch.end_with?("\n") &&
      lines.shift == "--- a/WebRtcAudioTrack.java\n" && lines.shift == "+++ b/WebRtcAudioTrack.java\n", 'Unexpected patch headers')
    result = []; consumed = 0; hunks = 0
    until lines.empty?
      header = lines.shift.match(/\A@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@[^\n]*\n\z/)
      require!(header, 'Malformed patch hunk')
      old_start, old_count, new_start, new_count = [header[1].to_i - 1, (header[2] || '1').to_i,
        header[3].to_i - 1, (header[4] || '1').to_i]
      old = []; replacement = []
      until lines.empty? || lines.first.start_with?('@@ ')
        line = lines.shift; require!([' ', '+', '-'].include?(line[0]), 'Malformed patch line')
        old << line[1..-1] unless line.start_with?('+')
        replacement << line[1..-1] unless line.start_with?('-')
      end
      require!(old_start >= consumed && old.length == old_count && replacement.length == new_count &&
        original[old_start, old_count] == old, 'Patch context/count mismatch; fuzz is forbidden')
      result.concat(original[consumed...old_start]); require!(result.length == new_start, 'Patch offset is forbidden')
      result.concat(replacement); consumed = old_start + old_count; hunks += 1
    end
    require!(hunks > 0, 'Empty patch')
    result.concat(original[consumed..-1]).join
  end
  def class17!(bytes)
    require!(bytes.bytesize >= 8 && bytes.byteslice(0, 4) == "\xca\xfe\xba\xbe".b &&
      bytes.byteslice(4, 4).unpack('nn') == [0, 61], 'Adapter output is not Java17 non-preview')
  end
  def merge_classes(original, compiled)
    family = original.keys.select { |name| name.match?(/\Aorg\/webrtc\/audio\/WebRtcAudioTrack(?:\$[^\/]+)?\.class\z/) }.sort
    require!(family == ORIGINAL_CLASSES.sort && !original.key?(PREFIX + 'PlaybackOutputObserver.class'), 'Original replacement family differs')
    require!(compiled.keys.sort == OUTPUT_CLASSES, 'Compiled output inventory differs')
    compiled.each_value { |bytes| class17!(bytes) }
    result = original.reject { |name, _| ORIGINAL_CLASSES.include?(name) }.merge(compiled)
    original.each { |name, bytes| require!(result[name] == bytes, 'Unrelated class changed') unless ORIGINAL_CLASSES.include?(name) }
    result
  end
  def methods(text)
    text.scan(/^  (.+\([^\n]*\);)\n    descriptor: (.+)$/).sort
  end
  def compile(config, work, patched, raw_jar, runner: AdapterBuildCommand)
    classes = work + '/classes'; Dir.mkdir(classes, 0700)
    environment = {'PATH' => '/usr/bin:/bin', 'HOME' => work, 'TMPDIR' => work, 'LANG' => 'C', 'LC_ALL' => 'C'}
    command = lambda do |label, argv|
      out = work + '/' + label + '.stdout'; err = work + '/' + label + '.stderr'
      runner.run(argv: argv, environment: environment, stdout: out, stderr: err, timeout: 60,
        cwd: work, output_limit: 2 * 1024 * 1024)
      file_bytes(out, 2 * 1024 * 1024)
    end
    command.call('javac', [config.fetch('jdkHome') + '/bin/javac', '--release', '17', '-encoding', 'UTF-8',
      '-proc:none', '-implicit:none', '-sourcepath', work + '/empty-sourcepath', '-cp',
      [raw_jar, config.fetch('androidJar'), config.fetch('annotationsJar')].join(':'), '-d', classes,
      patched, ROOT + '/src/org/webrtc/audio/PlaybackOutputObserver.java'])
    ORIGINAL_CLASSES.each_with_index do |name, index|
      klass = name.delete_suffix('.class').tr('/', '.')
      original = methods(command.call("abi-original-#{index}", [config.fetch('jdkHome') + '/bin/javap', '-p', '-s', '-classpath', raw_jar, klass]))
      modified = methods(command.call("abi-modified-#{index}", [config.fetch('jdkHome') + '/bin/javap', '-p', '-s', '-classpath', classes + ':' + raw_jar, klass]))
      require!(!original.empty? && (original - modified).empty?, 'Original method descriptors changed')
    end
    found = Dir.glob(classes + '/**/*', File::FNM_DOTMATCH).reject { |path| ['.', '..'].include?(File.basename(path)) }
    found.each { |path| require!(!File.symlink?(path) && (File.directory?(path) || File.file?(path)), 'Unexpected compiler filesystem object') }
    found.select { |path| File.file?(path) }.to_h { |path| [path.delete_prefix(classes + '/'), file_bytes(path, MAX_ENTRY)] }
  end
  def build(config_path, output, runner: AdapterBuildCommand)
    config_bytes = file_bytes(config_path, 65_536); config = parse(config_bytes)
    keys = %w[schema rawAar upstreamSource jdkHome androidJar annotationsJar inputPins]
    require!(config.is_a?(Hash) && config.keys.sort == keys.sort && config['schema'] == 'beluga.webrtc-derived-aar.inputs.v1', 'Unexpected input manifest')
    home = config['jdkHome']; require!(home.is_a?(String) && File.directory?(home) && File.realpath(home) == home, 'Canonical JDK home required')
    pins = config['inputPins']; require!(pins.is_a?(Hash), 'Input pin inventory required')
    adapter_inputs = %w[build-derived-aar.rb build-command.rb WebRtcAudioTrack.patch LICENSE.webrtc PATENTS.webrtc src/org/webrtc/audio/PlaybackOutputObserver.java].map { |name| ROOT + '/' + name }
    required = [config['rawAar'], config['upstreamSource'], config['androidJar'], config['annotationsJar'],
      home + '/bin/javac', home + '/bin/javap', home + '/release', AdapterBuildCommand::PS] + adapter_inputs
    require!(pins.keys.sort == required.sort && pins.values.all? { |value| value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/) }, 'Exact input pins required')
    recheck = lambda do
      require!(file_bytes(config_path, 65_536) == config_bytes, 'Input manifest changed')
      pins.each { |path, expected| require!(digest(file_bytes(path)) == expected, 'Input changed: ' + path) }
    end
    recheck.call
    require!(pins[config['rawAar']] == RAW_SHA && pins[config['upstreamSource']] == SOURCE_SHA &&
      pins[config['androidJar']] == SDK_SHA && pins[config['annotationsJar']] == ANNOTATIONS_SHA &&
      pins[AdapterBuildCommand::PS] == AdapterBuildCommand::PS_SHA, 'Wrong upstream/SDK/tool identity')
    NOTICES.each { |name, expected| require!(pins[ROOT + '/' + name] == expected, 'Upstream notice changed') }
    require!(file_bytes(home + '/release', 65_536).lines.count { |line| line.match?(/\AJAVA_VERSION="21(?:\.|\+)[^"]*"\n\z/) } == 1, 'JDK21 required')
    require!(output.is_a?(String) && output.start_with?('/') && File.basename(output) != '.' && File.basename(output) != '..' &&
      File.realpath(File.dirname(output)) == File.dirname(output) && !File.exist?(output) && !File.symlink?(output), 'Output must be absent under a canonical parent')
    raw = read_zip(file_bytes(config['rawAar'])); expected_aar = ['AndroidManifest.xml', 'classes.jar'] + NATIVE.keys.map { |abi| "jni/#{abi}/libjingle_peerconnection_so.so" }
    require!(raw.keys.sort == expected_aar.sort && digest(raw.fetch('classes.jar')) == JAR_SHA, 'Raw AAR membership/classes differ')
    NATIVE.each { |abi, expected| require!(digest(raw.fetch("jni/#{abi}/libjingle_peerconnection_so.so")) == expected, 'Native payload differs') }
    original = read_zip(raw.fetch('classes.jar'))
    require!(original.length == 433 && original.keys.all? { |name| name.end_with?('.class') }, 'Original classes inventory differs')
    patched_bytes = apply_patch(file_bytes(config['upstreamSource']), file_bytes(ROOT + '/WebRtcAudioTrack.patch'))
    Dir.mkdir(output, 0700); work = output + '/work'; Dir.mkdir(work, 0700)
    patched = work + '/WebRtcAudioTrack.java'; write_new(patched, patched_bytes)
    raw_jar = work + '/original-classes.jar'; write_new(raw_jar, raw.fetch('classes.jar'))
    compiled = compile(config, work, patched, raw_jar, runner: runner)
    combined = merge_classes(original, compiled)
    jar = write_zip(combined); require!(read_zip(jar) == combined, 'Derived JAR readback differs')
    provenance = {'schema' => 'beluga.webrtc-derived-aar.provenance.v1', 'rawAarSHA256' => RAW_SHA,
      'originalClassesSHA256' => JAR_SHA, 'upstreamRevision' => '73cb8180f7258ee292878d6edd05177f41883962',
      'upstreamSourceSHA256' => SOURCE_SHA, 'patchSHA256' => pins[ROOT + '/WebRtcAudioTrack.patch'],
      'observerSourceSHA256' => pins[ROOT + '/src/org/webrtc/audio/PlaybackOutputObserver.java'],
      'patchedSourceSHA256' => digest(patched_bytes), 'javaRelease' => 17,
      'compilerSHA256' => pins[home + '/bin/javac'], 'jdkReleaseSHA256' => pins[home + '/release'],
      'androidJarSHA256' => SDK_SHA, 'annotationsJarSHA256' => ANNOTATIONS_SHA,
      'builderSHA256' => pins[ROOT + '/build-derived-aar.rb'],
      'commandSupervisorSHA256' => pins[ROOT + '/build-command.rb'], 'noticeSHA256' => NOTICES,
      'adapterClasses' => compiled.transform_values { |bytes| digest(bytes) }, 'nativePayloads' => NATIVE,
      'productEnabled' => false, 'runtimeQualified' => false}
    entries = raw.merge('classes.jar' => jar)
    NOTICES.each_key { |name| entries['META-INF/beluga-webrtc-adapter/' + name] = file_bytes(ROOT + '/' + name) }
    entries['META-INF/beluga-webrtc-adapter/provenance.json'] = canonical_json(provenance) + "\n"
    aar = write_zip(entries); checked = read_zip(aar)
    require!(checked == entries && raw.all? { |name, bytes| name == 'classes.jar' || checked[name] == bytes }, 'Unrelated AAR entry changed')
    recheck.call
    artifact = output + '/libwebrtc-derived.aar'; write_new(artifact, aar)
    require!(file_bytes(artifact) == aar, 'Published derived AAR differs')
    recheck.call
    receipt = provenance.merge('status' => 'DERIVED_AAR_BUILT_NOT_ADMITTED', 'artifactSHA256' => digest(aar),
      'artifact' => artifact, 'inputManifestSHA256' => digest(config_bytes), 'inputPins' => pins,
      'unrelatedJarEntriesPreserved' => original.length - ORIGINAL_CLASSES.length,
      'originalNativeBytesPreserved' => true, 'signingPerformed' => false)
    write_new(output + '/receipt.json', canonical_json(receipt) + "\n")
    receipt
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: ruby build-derived-aar.rb --inputs /absolute/inputs.json --output /absolute/absent-directory' unless
    ARGV.length == 4 && ARGV[0] == '--inputs' && ARGV[2] == '--output'
  begin
    result = DerivedWebRtcAar.build(ARGV[1], ARGV[3])
    puts result.fetch('status')
  rescue StandardError, Interrupt => error
    warn 'Derived AAR failed: ' + error.class.name
    exit 1
  end
end
