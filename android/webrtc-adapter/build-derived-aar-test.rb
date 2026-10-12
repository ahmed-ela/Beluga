require 'minitest/autorun'
require 'tmpdir'
require_relative 'build-derived-aar'

class DerivedWebRtcAarTest < Minitest::Test
  D = DerivedWebRtcAar
  def class_bytes(major = 61); "\xca\xfe\xba\xbe".b + [0, major].pack('nn') + 'fixture'; end
  def original
    D::ORIGINAL_CLASSES.to_h { |name| [name, class_bytes(65)] }.merge('org/webrtc/Untouched.class' => 'unchanged')
  end
  def compiled; D::OUTPUT_CLASSES.to_h { |name| [name, class_bytes] }; end
  def test_archive_is_deterministic_and_payload_exact
    entries = {'z/native.so' => "\0\xff\x80".b, 'a/license.txt' => "notice\n"}
    first = D.write_zip(entries)
    assert_equal first, D.write_zip(entries.to_a.reverse.to_h)
    assert_equal entries, D.read_zip(first)
    assert_equal 0, D.u16(first, 10)
    assert_equal 33, D.u16(first, 12)
    assert_equal D.digest(first), D.digest(D.write_zip(D.read_zip(first)))
  end
  def test_unsafe_names_and_duplicate_entries_rejected
    ['/absolute', '../escape', 'x/../escape', 'x//y', 'x\\y', 'directory/', "x\0y", './x'].each do |name|
      assert_raises(D::Invalid) { D.write_zip(name => 'data') }
    end
    duplicate = D.write_zip('a.class' => 'same', 'b.class' => 'same').gsub('b.class', 'a.class')
    assert_raises(D::Invalid) { D.read_zip(duplicate) }
  end
  def test_corruption_local_mismatch_and_trailing_data_rejected
    zip = D.write_zip('only.class' => 'data')
    corrupt = zip.dup; offset = 30 + 'only.class'.bytesize; corrupt.setbyte(offset, corrupt.getbyte(offset) ^ 1)
    assert_raises(D::Invalid) { D.read_zip(corrupt) }
    mismatch = zip.dup; mismatch.setbyte(30, 'X'.ord)
    assert_raises(D::Invalid) { D.read_zip(mismatch) }
    assert_raises(D::Invalid) { D.read_zip(zip + 'trailing') }
    assert_raises(D::Invalid) { D.read_zip(zip.byteslice(0, zip.bytesize - 1)) }
  end
  def test_raw_deflate_is_bounded_and_complete
    encoder = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    packed = encoder.deflate('hello' * 100, Zlib::FINISH); encoder.close
    assert_equal 'hello' * 100, D.inflate(packed, 500)
    assert_raises(D::Invalid) { D.inflate(packed, 499) }
    assert_raises(D::Invalid) { D.inflate(packed + 'trailing', 500) }
  end
  def patch
    "--- a/WebRtcAudioTrack.java\n+++ b/WebRtcAudioTrack.java\n@@ -2,2 +2,3 @@\n two\n-three\n+THREE\n+four\n"
  end
  def test_patch_requires_exact_context_counts_and_positions
    assert_equal "one\ntwo\nTHREE\nfour\n", D.apply_patch("one\ntwo\nthree\n", patch)
    assert_raises(D::Invalid) { D.apply_patch("one\nwrong\nthree\n", patch) }
    assert_raises(D::Invalid) { D.apply_patch("inserted\none\ntwo\nthree\n", patch) }
    assert_raises(D::Invalid) { D.apply_patch("one\ntwo\nthree\n", patch.sub('+2,3', '+3,3')) }
    assert_raises(D::Invalid) { D.apply_patch("one\ntwo\nthree\n", patch.sub('-2,2', '-2,1')) }
    assert_raises(D::Invalid) { D.apply_patch("one\ntwo\nthree\n", patch.sub('a/WebRtcAudioTrack', 'a/Other')) }
  end
  def test_replace_original_family_exactly_once
    result = D.merge_classes(original, compiled)
    assert_equal 5, result.length
    assert_equal 'unchanged', result.fetch('org/webrtc/Untouched.class')
    D::OUTPUT_CLASSES.each { |name| assert_equal class_bytes, result.fetch(name) }
    assert_raises(D::Invalid) { D.merge_classes(original.reject { |name, _| name == D::ORIGINAL_CLASSES.first }, compiled) }
    assert_raises(D::Invalid) { D.merge_classes(original.merge(D::PREFIX + 'WebRtcAudioTrack$Unexpected.class' => class_bytes), compiled) }
    assert_raises(D::Invalid) { D.merge_classes(original.merge(D::PREFIX + 'PlaybackOutputObserver.class' => class_bytes), compiled) }
    assert_raises(D::Invalid) { D.merge_classes(original, compiled.merge('other.class' => class_bytes)) }
    assert_raises(D::Invalid) { D.merge_classes(original, compiled.merge(D::OUTPUT_CLASSES.first => class_bytes(65))) }
  end
  def test_canonical_provenance_and_duplicate_json_rejection
    first = {'z' => {'b' => 2, 'a' => 1}, 'a' => [false, 17]}
    assert_equal D.canonical_json(first), D.canonical_json(first.to_a.reverse.to_h)
    assert_equal first, D.parse(D.canonical_json(first))
    assert_raises(D::Invalid) { D.parse('{"schema":1,"schema":2}') }
  end
  class CompilerDouble
    attr_reader :calls
    attr_accessor :remove_method
    def initialize; @calls = []; end
    def run(**options)
      @calls << options
      argv = options.fetch(:argv)
      if argv.first.end_with?('/javac')
        output = argv.fetch(argv.index('-d') + 1)
        D::OUTPUT_CLASSES.each do |name|
          target = output + '/' + name; FileUtils.mkdir_p(File.dirname(target))
          D.write_new(target, "\xca\xfe\xba\xbe".b + [0, 61].pack('nn') + 'fixture')
        end
        text = ''
      else
        text = "  private void originalMethod();\n    descriptor: ()V\n"
        text = '' if @remove_method && options.fetch(:stdout).include?('modified')
      end
      D.write_new(options.fetch(:stdout), text)
      D.write_new(options.fetch(:stderr), '')
    end
  end
  def test_compiler_command_uses_sdk_release17_and_descriptor_checks
    Dir.mktmpdir('adapter-command-double-') do |work|
      work = File.realpath(work)
      runner = CompilerDouble.new
      config = {'jdkHome' => '/explicit/jdk21', 'androidJar' => '/actual/android.jar', 'annotationsJar' => '/exact/annotations.jar'}
      result = D.compile(config, work, work + '/WebRtcAudioTrack.java', work + '/classes.jar', runner: runner)
      assert_equal D::OUTPUT_CLASSES, result.keys.sort
      assert_equal 5, runner.calls.length
      call = runner.calls.first; argv = call.fetch(:argv)
      assert_equal ['--release', '17'], argv[1, 2]
      assert_includes argv, '-proc:none'
      assert_includes argv, '-implicit:none'
      assert_equal work + '/classes.jar:/actual/android.jar:/exact/annotations.jar', argv[argv.index('-cp') + 1]
      assert_equal 60, call.fetch(:timeout)
      assert_equal({'PATH' => '/usr/bin:/bin', 'HOME' => work, 'TMPDIR' => work, 'LANG' => 'C', 'LC_ALL' => 'C'}, call.fetch(:environment))
    end
  end
  def test_descriptor_loss_stops_before_merge
    Dir.mktmpdir('adapter-command-reject-') do |work|
      work = File.realpath(work)
      runner = CompilerDouble.new; runner.remove_method = true
      config = {'jdkHome' => '/explicit/jdk21', 'androidJar' => '/actual/android.jar', 'annotationsJar' => '/exact/annotations.jar'}
      assert_raises(D::Invalid) { D.compile(config, work, work + '/WebRtcAudioTrack.java', work + '/classes.jar', runner: runner) }
      assert_equal 3, runner.calls.length
    end
  end
end
