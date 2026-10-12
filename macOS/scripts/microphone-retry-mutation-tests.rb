# frozen_string_literal: true
# Offline decoder/source checks. No tools, native framework or runtime is launched.
require_relative '../../shared/Rust/BelugaCore/scripts/mutation-tests'

module BelugaCoreMicrophoneRetryArtifactTests
  RETRY_ORACLE = BelugaCoreMicrophoneRetryMutationOracle

  def retry_outcome_text(test, passed:)
    prefix = "   Finished `test` profile [unoptimized + debuginfo] target(s) in 1.0s\n" \
      "    Running tests/microphone_forwarding_retry.rs (target/debug/deps/microphone_forwarding_retry-abcdef)\n" \
      "\nrunning 1 test\ntest #{test} ... #{passed ? 'ok' : 'FAILED'}\n"
    return prefix + "test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 9 filtered out; finished in 0.00s\n" if passed
    prefix + "\nfailures:\n\n---- #{test} stdout ----\n" \
      "thread '#{test}' (123) panicked at tests/microphone_forwarding_retry.rs:94:5:\n" \
      "assertion `left == right` failed\n  left: 1\n right: 0\n\n" \
      "failures:\n    #{test}\n\n" \
      "test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 9 filtered out; finished in 0.00s\n" \
      "error: test failed, to rerun pass `--test microphone_forwarding_retry`\n"
  end

  def test_microphone_retry_mutation_decoder_requires_compiled_named_assertion_and_restoration
    assert_equal 7, RETRY_ORACLE::NAMES.length
    assert_equal 7, RETRY_ORACLE::NAMES.uniq.length
    RETRY_ORACLE::TESTS.each do |test|
      [true, false].each do |passed|
        assert_nil RETRY_ORACLE.validate!(retry_outcome_text(test, passed: passed), test,
          passed: passed, exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false)
      end
    end
  end

  def test_microphone_retry_mutation_decoder_rejects_compile_signal_timeout_missing_or_wrong_cases
    test = RETRY_ORACLE::CORRELATION
    failed = retry_outcome_text(test, passed: false)
    bad_texts = [
      failed.sub(/.*Finished.*\n/, ''), failed.sub(/.*Running.*\n/, ''),
      failed.sub('running 1 test', 'running 0 tests'), failed.sub('9 filtered out', '8 filtered out'),
      failed.sub('0 ignored', '1 ignored'), failed.sub(test, 'foreign_test'),
      failed.sub('assertion `left == right` failed', 'explicit panic'),
      failed.sub('tests/microphone_forwarding_retry.rs:94:5:', 'src/foreign.rs:94:5:'),
      failed.sub('---- ' + test + ' stdout ----', '---- foreign stdout ----'),
      failed.sub('1 failed;', '0 failed;'), failed + "error: could not compile\n",
      failed + "killed by signal\n", failed + "timed out\n", failed + "skipped\n",
      failed + "running 1 test\n", failed + "test foreign ... ok\n",
      failed + "test result: ok. 1 passed\n"
    ]
    bad_texts.each do |text|
      assert_raises(RuntimeError) { RETRY_ORACLE.validate!(text, test,
        passed: false, exitstatus: 101, termsig: nil, timed_out: false) }
    end
    [[0, nil, false], [101, 9, false], [101, nil, true]].each do |status, signal, timeout|
      assert_raises(RuntimeError) { RETRY_ORACLE.validate!(failed, test,
        passed: false, exitstatus: status, termsig: signal, timed_out: timeout) }
    end
    restored = retry_outcome_text(test, passed: true)
    assert_raises(RuntimeError) { RETRY_ORACLE.validate!(restored + "failures:\n", test,
      passed: true, exitstatus: 0, termsig: nil, timed_out: false) }
  end

  def test_microphone_retry_mutation_anchors_are_unique_and_tests_exist_without_editing_them
    product = File.binread(File.join(BelugaCoreArtifact::CRATE, 'src/microphone_forwarding_retry.rs'))
    tests = File.binread(File.join(BelugaCoreArtifact::CRATE, RETRY_ORACLE::TEST_PATH))
    RETRY_ORACLE::CONTROLS.each do |name, path, suite, before, after, test|
      assert_equal 'src/microphone_forwarding_retry.rs', path, name
      assert_equal RETRY_ORACLE::SUITE, suite, name
      assert_equal 1, product.scan(before).length, name
      refute_equal before, after, name
      refute_includes product, after, name
      assert_equal 1, tests.scan("fn #{test}(").length, name
    end
  end
end
