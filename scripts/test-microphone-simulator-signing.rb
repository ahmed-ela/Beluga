#!/usr/bin/ruby
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'microphone-simulator-signing'

class MicrophoneSimulatorSigningTests < Minitest::Test
  Signing = MicrophoneSimulatorSigning
  XML = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + Signing::PLIST_DOCTYPE + "\n" +
    '<plist version="1.0"><dict><key>application-identifier</key><string>' + Signing::APPLICATION_ID +
    '</string><key>com.apple.security.application-groups</key><array><string>' + Signing::MEDIA_GROUP +
    '</string></array></dict></plist>').freeze
  INFO = { 'CFBundleIdentifier' => Signing::BUNDLE_ID, 'CFBundleExecutable' => 'Beluga',
    'CFBundlePackageType' => 'APPL', 'CFBundleSupportedPlatforms' => ['iPhoneSimulator'],
    'DTPlatformName' => 'iphonesimulator', 'BelugaMediaAppGroup' => Signing::MEDIA_GROUP }.freeze
  INFO_XML = ('<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>' +
    INFO.map { |key, value| '<key>' + key + '</key>' + (value.is_a?(Array) ?
      '<array><string>' + value.first + '</string></array>' : '<string>' + value + '</string>') }.join +
    '</dict></plist>').freeze

  def macho_name(value)
    value.ljust(16, "\x00")
  end

  def section(label, offset, size)
    macho_name(label) + macho_name('__TEXT') + [0x100000000 + offset, size].pack('Q<2') +
      [offset, 0, 0, 0, 0, 0, 0, 0].pack('V8')
  end

  # A synthetic byte fixture with code-page checksums, not real code signing.
  def macho_fixture(xml: XML, der: Signing::CANONICAL_DER, duplicate_build: false,
                    duplicate_xml: false, duplicate_signature: false)
    sections = [section('__entitlements', 512, xml.bytesize), section('__ents_der', 8192, der.bytesize)]
    sections << section('__entitlements', 512, xml.bytesize) if duplicate_xml
    segment = [0x19, 72 + 80 * sections.length].pack('V2') + macho_name('__TEXT') +
      [0x100000000, 16384, 0, 16384].pack('Q<4') + [5, 5, sections.length, 0].pack('V4') + sections.join
    build = [0x32, 24, 7, 0x110000, 0x1a0500, 0].pack('V6')
    identifier = Signing::BUNDLE_ID + "\x00"
    directory_size = 88 + identifier.bytesize + 32
    signature_size = 20 + directory_size
    signature = [0x1d, 16, 16384, signature_size].pack('V4')
    commands = segment + build + (duplicate_build ? build : '') + signature + (duplicate_signature ? signature : '')
    count = 3 + (duplicate_build ? 1 : 0) + (duplicate_signature ? 1 : 0)
    bytes = [0xfeedfacf, 0x0100000c, 0, 2, count, commands.bytesize, 0, 0].pack('V8') + commands
    bytes = bytes.ljust(16384, "\x00")
    bytes[512, xml.bytesize] = xml
    bytes[8192, der.bytesize] = der
    directory = [0xfade0c02, directory_size, 0x20400, 2, 88 + identifier.bytesize,
      88, 0, 1, 16384].pack('N9') + [32, 2, 0, 14].pack('C4') +
      [0, 0, 0, 0].pack('N4') + [0, 0, 16384, 1].pack('Q>4') + identifier + Digest::SHA256.digest(bytes)
    bytes + [0xfade0cc0, signature_size, 1, 0, 20].pack('N5') + directory
  end

  def refuse(bytes, reason)
    error = assert_raises(Signing::Refusal) { Signing.parse_macho(bytes) }
    assert_includes error.message, reason
  end

  def with_app
    Dir.mktmpdir('beluga-simulator-signing-unit-') do |directory|
      app = File.realpath(directory) + '/Beluga.app'
      FileUtils.mkdir(app)
      File.binwrite(app + '/Beluga', macho_fixture)
      File.binwrite(app + '/Info.plist', INFO_XML)
      yield app
    end
  end

  def fake_executor(calls, &intercept)
    lambda do |argv|
      calls << argv
      override = intercept && intercept.call(argv, calls.length)
      next override if override
      argv.first == Signing::DEPENDENCIES[1] ? [INFO_XML, true] : ['', true]
    end
  end

  def collect_fixture(app, executor = fake_executor([]))
    Signing.send(:collect_with_executor, app, executor)
  end

  def test_exact_signed_simulator_parser_and_canonical_der_parity
    proof = Signing.parse_macho(macho_fixture)
    assert_equal 'arm64', proof['architecture']
    assert_equal 7, proof['platform']
    assert_equal 16384, proof['codeDirectory']['codeLimit']
    assert_equal true, proof['coveredCodePagesVerified']
    assert_equal true, proof['xmlDerParity']
    assert_equal 163, proof['der']['length']
    assert_equal Signing::DER_SHA256, proof['der']['sha256']
    assert_equal Signing::APPLICATION_ID, Signing.parse_plist(XML)['application-identifier']
  end

  def test_wrong_thin_architecture_filetype_and_physical_platform_refuse
    [[0, 0xcafebabe], [4, 0x01000007], [8, 2], [12, 6], [28, 1]].each do |offset, value|
      bytes = macho_fixture; bytes[offset, 4] = [value].pack('V')
      refuse(bytes, 'thin little-endian arm64')
    end
    bytes = macho_fixture; bytes[32 + 232 + 8, 4] = [2].pack('V')
    refuse(bytes, 'Simulator build-version')
  end

  def test_missing_duplicate_and_malformed_load_commands_refuse
    refuse(macho_fixture(duplicate_build: true), 'build-version')
    refuse(macho_fixture(duplicate_xml: true), 'duplicate')
    refuse(macho_fixture(duplicate_signature: true), 'signature command')
    [[16, 129], [20, 65537], [36, 7], [32 + 64, 33], [32 + 232 + 20, 17]].each do |offset, value|
      bytes = macho_fixture; bytes[offset, 4] = [value].pack('V')
      assert_raises(Signing::Refusal) { Signing.parse_macho(bytes) }
    end
    bytes = macho_fixture; bytes[32 + 232, 4] = [0].pack('V')
    refuse(bytes, 'absent')
    refuse(macho_fixture.byteslice(0, 300), 'load commands exceed file')
  end

  def test_section_bounds_placement_overlap_and_coverage_refuse
    xml_section = 32 + 72; der_section = xml_section + 80
    [[xml_section + 48, 16380], [xml_section + 56, 1]].each do |offset, value|
      bytes = macho_fixture; bytes[offset, 4] = [value].pack('V')
      assert_raises(Signing::Refusal) { Signing.parse_macho(bytes) }
    end
    bytes = macho_fixture; bytes[xml_section + 40, 8] = [4097].pack('Q<')
    refuse(bytes, 'section geometry')
    bytes = macho_fixture; bytes[xml_section + 16, 16] = macho_name('__DATA')
    refuse(bytes, 'misplaced')
    bytes = macho_fixture; bytes[der_section + 32, 8] = [0x100000000 + 512].pack('Q<')
    bytes[der_section + 48, 4] = [512].pack('V')
    refuse(bytes, 'overlap')
    bytes = macho_fixture; bytes[32 + 24, 8] = [0x100000001].pack('Q<')
    refuse(bytes, 'section geometry')
  end

  def test_duplicate_xml_keys_wrong_identifier_and_group_refuse
    duplicate = XML.sub('</dict>', '<key>application-identifier</key><string>' + Signing::APPLICATION_ID + '</string></dict>')
    refuse(macho_fixture(xml: duplicate), 'duplicate key')
    refuse(macho_fixture(xml: XML.sub(Signing::APPLICATION_ID, 'MSMG8CJLB3.org.example.AudioStreamer')), 'not exact')
    refuse(macho_fixture(xml: XML.sub(Signing::MEDIA_GROUP, 'group.org.example.AudioStreamer.media')), 'not exact')
    extra_group = XML.sub('</array>', '<string>' + Signing::MEDIA_GROUP + '</string></array>')
    refuse(macho_fixture(xml: extra_group), 'not exact')
    extra_key = XML.sub('</dict>', '<key>fake-green</key><true/></dict>')
    refuse(macho_fixture(xml: extra_key), 'not exact')
  end

  def test_malformed_xml_entities_and_parser_bounds_refuse
    ['<plist version="1.0"><dict>', XML.sub('</string>', '</array>'),
     XML.sub('<dict>', '<dict fake="yes">'), XML.sub(Signing::PLIST_DOCTYPE, '<!DOCTYPE plist [<!ENTITY leak "x">]>')].each do |xml|
      assert_raises(Signing::Refusal) { Signing.parse_plist(xml) }
    end
    assert_raises(Signing::Refusal) { Signing.parse_plist('<plist version="1.0">' + '<array>' * 17 + '</array>' * 17 + '</plist>') }
    padded = XML + ' ' * (Signing::MAX_XML_BYTES + 1 - XML.bytesize)
    error = assert_raises(Signing::Refusal) { Signing.parse_plist(padded) }
    assert_includes error.message, 'bounded input'
    error = assert_raises(Signing::Refusal) { Signing.parse_plist('<' * 4097) }
    assert_includes error.message, 'token bound'
    assert_raises(Signing::Refusal) { Signing.parse_plist(XML + "\xff".b) }
  end

  def test_dtd_inside_scalar_and_root_mixed_content_cannot_be_normalized_green
    without_dtd = XML.sub(Signing::PLIST_DOCTYPE, '')
    injected = without_dtd.sub(Signing::APPLICATION_ID, Signing::APPLICATION_ID + Signing::PLIST_DOCTYPE)
    error = assert_raises(Signing::Refusal) { Signing.parse_plist(injected) }
    assert_includes error.message, 'declarations'
    mixed = XML.sub('<dict>', 'fake-green<dict>')
    error = assert_raises(Signing::Refusal) { Signing.parse_plist(mixed) }
    assert_includes error.message, 'root is invalid'
    assert_raises(Signing::Refusal) { Signing.parse_plist(XML + '<plist version="1.0"><dict/></plist>') }
  end

  def test_nul_confused_fixed_macho_names_are_not_entitlement_sections
    [32 + 8, 32 + 72, 32 + 72 + 16].each do |offset|
      bytes = macho_fixture
      original = bytes.byteslice(offset, 16).split("\x00", 2).first
      confused = (original[0, 2] + "\x00" + original[2..-1]).ljust(16, "\x00")
      bytes[offset, 16] = confused
      refuse(bytes, 'fixed name is noncanonical')
    end
  end

  def test_nonwhitespace_document_siblings_are_not_signed_plist_content
    plain = '<plist' + XML.split('<plist', 2).last
    [XML + 'fake-green', 'fake-green' + plain].each do |xml|
      assert_raises(Signing::Refusal) { Signing.parse_plist(xml) }
    end
  end

  def test_canonical_der_changes_or_noncanonical_encoding_refuse
    der = Signing::CANONICAL_DER.dup; der[-1] = 'b'
    refuse(macho_fixture(der: der), 'canonical XML')
    refuse(macho_fixture(der: Signing::CANONICAL_DER + "\x00"), 'canonical XML')
    refuse(macho_fixture(der: "\x30\x00"), 'canonical XML')
  end

  def test_code_directory_page_hash_and_unsigned_bytes_refuse
    bytes = macho_fixture; bytes[12000] = 'x'
    refuse(bytes, 'code-page hash differs')
    bytes = macho_fixture; bytes[-1] = 'x'
    refuse(bytes, 'code-page hash differs')
    bytes = macho_fixture; bytes[32 + 232 + 24, 4] = [0].pack('V')
    refuse(bytes, 'absent')
  end

  def test_code_directory_scatter_limits_version_and_blob_bounds_refuse
    directory = 16384 + 20
    [[directory + 8, 0x20500], [directory + 12, 0], [directory + 32, 8192],
     [directory + 44, 1], [directory + 28, 2], [directory + 16, 20],
     [16384 + 8, 17], [16384 + 16, 999999], [directory + 4, 999999]].each do |offset, value|
      bytes = macho_fixture; bytes[offset, 4] = [value].pack('N')
      assert_raises(Signing::Refusal) { Signing.parse_macho(bytes) }
    end
    bytes = macho_fixture; bytes[directory + 39] = "\x0c"
    refuse(bytes, 'coverage geometry')
    bytes = macho_fixture; bytes[directory + 88] = 'x'
    refuse(bytes, 'identifier')
  end

  def test_collector_pins_info_executable_and_verifies_signature_twice
    with_app do |app|
      calls = []; record = collect_fixture(app, fake_executor(calls))
      assert_equal [[Signing::DEPENDENCIES[0], '--verify', '--strict', app],
        [Signing::DEPENDENCIES[1], '-convert', 'xml1', '-o', '-', '--', app + '/Info.plist'],
        [Signing::DEPENDENCIES[0], '--verify', '--strict', app]], calls
      assert Signing.validate_record(record, expected_app: app)
      assert_equal record, collect_fixture(app)
      assert_equal Digest::SHA256.file(app + '/Beluga').hexdigest, record['executable']['sha256']
      assert_equal Digest::SHA256.file(app + '/Info.plist').hexdigest, record['info']['sha256']
      assert_equal [Signing::MEDIA_GROUP], record['applicationGroups']
      assert_operator JSON.generate(record).bytesize, :<=, Signing::MAX_RECORD_BYTES
    end
  end

  def test_collector_first_or_final_signature_failure_never_returns_record
    [1, 3].each do |failure_call|
      with_app do |app|
        calls = []
        executor = fake_executor(calls) { |_argv, count| ['', false] if count == failure_call }
        error = assert_raises(Signing::Refusal) { collect_fixture(app, executor) }
        assert_includes error.message, 'signature verification failed'
        assert_equal failure_call, calls.length
      end
    end
  end

  def test_collector_detects_executable_or_info_mutation_at_every_tool_boundary
    [1, 2, 3].each do |boundary|
      %w[Beluga Info.plist].each do |name|
        with_app do |app|
          calls = []
          executor = fake_executor(calls) do |_argv, count|
            File.open(app + '/' + name, 'ab') { |file| file.write('x') } if count == boundary
            nil
          end
          error = assert_raises(Signing::Refusal) { collect_fixture(app, executor) }
          assert_includes error.message, 'identity changed'
          assert_equal boundary, calls.length
        end
      end
    end
  end

  def test_collector_same_bytes_file_replacement_and_symlink_refuse
    with_app do |app|
      calls = []
      executor = fake_executor(calls) do |_argv, count|
        if count == 1
          File.rename(app + '/Beluga', app + '/old-executable')
          File.binwrite(app + '/Beluga', macho_fixture)
        end
        nil
      end
      assert_raises(Signing::Refusal) { collect_fixture(app, executor) }
    end
    with_app do |app|
      File.rename(app + '/Beluga', app + '/real-executable')
      File.symlink(app + '/real-executable', app + '/Beluga')
      assert_raises(Signing::Refusal) { collect_fixture(app) }
    end
  end

  def test_collector_digest_pin_refuses_same_size_bytes_with_stat_times_masked
    original_stat = Signing.method(:stat_record)
    stable_times = lambda do |stat|
      original_stat.call(stat).merge('mtimeNanoseconds' => 0, 'ctimeNanoseconds' => 0)
    end
    %w[Beluga Info.plist].each do |name|
      with_app do |app|
        before_size = File.size(app + '/' + name)
        executor = fake_executor([]) do |_argv, count|
          if count == 1
            File.open(app + '/' + name, 'r+b') do |file|
              offset = name == 'Beluga' ? 12000 : 2
              file.seek(offset); changed = file.read(1).getbyte(0) ^ 1
              file.seek(offset); file.write([changed].pack('C'))
            end
          end
          nil
        end
        Signing.stub(:stat_record, stable_times) do
          error = assert_raises(Signing::Refusal) { collect_fixture(app, executor) }
          assert_includes error.message, 'executable or Info identity changed'
        end
        assert_equal before_size, File.size(app + '/' + name)
      end
    end
  end

  def test_collector_stat_pin_refuses_mode_change_with_unchanged_bytes
    %w[Beluga Info.plist].each do |name|
      with_app do |app|
        before_sha = Digest::SHA256.file(app + '/' + name).hexdigest
        executor = fake_executor([]) do |_argv, count|
          File.chmod(File.stat(app + '/' + name).mode ^ 0o010, app + '/' + name) if count == 1
          nil
        end
        error = assert_raises(Signing::Refusal) { collect_fixture(app, executor) }
        assert_includes error.message, 'executable or Info identity changed'
        assert_equal before_sha, Digest::SHA256.file(app + '/' + name).hexdigest
      end
    end
  end

  def test_collector_wrong_info_plutil_failure_or_unsigned_fixture_refuse
    with_app do |app|
      wrong = INFO_XML.sub(Signing::MEDIA_GROUP, 'group.wrong')
      assert_raises(Signing::Refusal) { collect_fixture(app, fake_executor([]) { |argv, _count| [wrong, true] if argv.first == Signing::DEPENDENCIES[1] }) }
      assert_raises(Signing::Refusal) { collect_fixture(app, fake_executor([]) { |argv, _count| ['', false] if argv.first == Signing::DEPENDENCIES[1] }) }
      File.binwrite(app + '/Beluga', 'unsigned fixture')
      error = assert_raises(Signing::Refusal) { collect_fixture(app) }
      assert_includes error.message, 'Mach-O'
    end
  end

  def test_replay_rejects_false_green_unknown_fields_paths_and_bounds
    with_app do |app|
      original = collect_fixture(app)
      mutations = [
        ->(record) { record['schema'] = 'wrong' },
        ->(record) { record['signature']['before'] = false },
        ->(record) { record['signature']['after'] = false },
        ->(record) { record['signature']['tool'] = '/tmp/codesign' },
        ->(record) { record['skipSignature'] = true },
        ->(record) { record['info']['path'] = '/tmp/Info.plist' },
        ->(record) { record['info']['supportedPlatforms'] = ['iPhoneOS'] },
        ->(record) { record['executable']['architecture'] = 'x86_64' },
        ->(record) { record['executable']['platform'] = 7.0 },
        ->(record) { record['executable']['fileType'] = 2.0 },
        ->(record) { record['executable']['xmlDerParity'] = false },
        ->(record) { record['executable']['coveredCodePagesVerified'] = false },
        ->(record) { record['executable']['der']['sha256'] = '0' * 64 },
        ->(record) { record['executable']['xml']['offset'] = 16384 },
        ->(record) { record['executable']['codeDirectory']['codeSlots'] = 2 },
        ->(record) { record['executable']['codeDirectory']['codeLimit'] = 16385 },
        ->(record) { record['executable']['stat']['mode'] = 0o120644 },
        ->(record) { record['executable']['sha256'] = 'A' * 64 },
        ->(record) { record['appStat']['inode'] = 0 }
      ]
      mutations.each do |mutate|
        record = Marshal.load(Marshal.dump(original)); mutate.call(record)
        assert_raises(Signing::Refusal) { Signing.validate_record(record, expected_app: app) }
      end
      assert_raises(Signing::Refusal) { Signing.validate_record(original, expected_app: app + '-wrong') }
    end
  end

  def test_production_api_has_no_executor_or_signature_skip_option
    assert_equal [[:req, :app]], Signing.method(:collect).parameters
    refute Signing.respond_to?(:collect_with_executor)
    refute Signing.respond_to?(:run_tool)
    assert_equal ['/usr/bin/codesign', '/usr/bin/plutil'], Signing::DEPENDENCIES
    assert Signing::DEPENDENCIES.frozen?
    assert Signing::DEPENDENCIES.all?(&:frozen?)
    assert_raises(FrozenError) { Signing::DEPENDENCIES.first.replace('/tmp/fake') }
  end
end

class MicrophoneSimulatorSigningBehaviorReporter < Minitest::StatisticsReporter
  def report
    super
    io.puts 'microphone Simulator signing behavior tests passed' if count > 0 && passed? && results.none?(&:skipped?)
  end
end

Minitest.extensions << 'microphone_simulator_signing'
def Minitest.plugin_microphone_simulator_signing_init(options)
  reporter << MicrophoneSimulatorSigningBehaviorReporter.new(options[:io], options)
end
