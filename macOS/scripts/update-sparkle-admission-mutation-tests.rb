# frozen_string_literal: true
# Offline decoder/source checks only. No compiler, SDK or native runtime is launched.
require_relative '../../shared/Rust/BelugaCore/scripts/mutation-tests'

module BelugaCoreUpdateSparkleAdmissionArtifactTests
  SPARKLE_ADMISSION_ORACLE = BelugaCoreUpdateSparkleAdmissionMutationOracle

  def sparkle_admission_outcome_text(test, passed:)
    prefix = "   Finished `test` profile [unoptimized + debuginfo] target(s) in 1.0s\n" \
      "    Running tests/update_sparkle_admission.rs (target/debug/deps/update_sparkle_admission-abcdef)\n" \
      "\nrunning 1 test\ntest #{test} ... #{passed ? 'ok' : 'FAILED'}\n"
    return prefix + "test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 7 filtered out; finished in 0.00s\n" if passed
    prefix + "\nfailures:\n\n---- #{test} stdout ----\n" \
      "thread '#{test}' (123) panicked at tests/update_sparkle_admission.rs:94:5:\n" \
      "assertion `left == right` failed\n  left: 1\n right: 0\n\n" \
      "failures:\n    #{test}\n\n" \
      "test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 7 filtered out; finished in 0.00s\n" \
      "error: test failed, to rerun pass `--test update_sparkle_admission`\n"
  end

  def test_update_sparkle_admission_mutation_decoder_requires_compiled_named_assertion_and_restoration
    assert_equal (1..17).map { |value| format('USA-M%02d', value) }, SPARKLE_ADMISSION_ORACLE::NAMES
    assert_equal 17, SPARKLE_ADMISSION_ORACLE::NAMES.uniq.length
    SPARKLE_ADMISSION_ORACLE::TESTS.each do |test|
      [true, false].each do |passed|
        assert_nil SPARKLE_ADMISSION_ORACLE.validate!(sparkle_admission_outcome_text(test, passed: passed), test,
          passed: passed, exitstatus: passed ? 0 : 101, termsig: nil, timed_out: false)
      end
    end
  end

  def test_update_sparkle_admission_mutation_decoder_rejects_compile_signal_timeout_missing_or_wrong_cases
    test = SPARKLE_ADMISSION_ORACLE::CORRELATION
    failed = sparkle_admission_outcome_text(test, passed: false)
    bad_texts = [
      failed.sub(/.*Finished.*\n/, ''), failed.sub(/.*Running.*\n/, ''),
      failed.sub('running 1 test', 'running 0 tests'), failed.sub('7 filtered out', '8 filtered out'),
      failed.sub('0 ignored', '1 ignored'), failed.sub(test, 'foreign_test'),
      failed.sub('assertion `left == right` failed', 'explicit panic'),
      failed.sub('tests/update_sparkle_admission.rs:94:5:', 'src/foreign.rs:94:5:'),
      failed.sub('---- ' + test + ' stdout ----', '---- foreign stdout ----'),
      failed.sub('1 failed;', '0 failed;'), failed + "error: could not compile\n",
      failed + "killed by signal\n", failed + "timed out\n", failed + "skipped\n",
      failed + "running 1 test\n", failed + "test foreign ... ok\n",
      failed + "test result: ok. 1 passed\n",
      failed.sub('Running tests/update_sparkle_admission.rs', 'Running tests/update_admission.rs'),
      failed.sub('target/debug/deps/update_sparkle_admission-abcdef', 'target/debug/deps/foreign-abcdef'),
      failed.sub('Finished `test` profile', 'Finished `dev` profile'),
      failed.sub('error: test failed, to rerun pass `--test update_sparkle_admission`',
        'error: test failed, to rerun pass `--test update_admission`'),
      failed.sub('    ' + test + "\n\n", "    foreign_test\n\n"),
      failed + "\xff".b
    ]
    bad_texts.each do |text|
      assert_raises(RuntimeError) { SPARKLE_ADMISSION_ORACLE.validate!(text, test,
        passed: false, exitstatus: 101, termsig: nil, timed_out: false) }
    end
    [[0, nil, false], [101, 9, false], [101, nil, true], [101, nil, nil]].each do |status, signal, timeout|
      assert_raises(RuntimeError) { SPARKLE_ADMISSION_ORACLE.validate!(failed, test,
        passed: false, exitstatus: status, termsig: signal, timed_out: timeout) }
    end
    assert_raises(RuntimeError) { SPARKLE_ADMISSION_ORACLE.validate!(failed, 'foreign_test',
      passed: false, exitstatus: 101, termsig: nil, timed_out: false) }
    assert_raises(RuntimeError) { SPARKLE_ADMISSION_ORACLE.validate!(failed, test,
      passed: nil, exitstatus: 101, termsig: nil, timed_out: false) }
    restored = sparkle_admission_outcome_text(test, passed: true)
    [restored + "failures:\n", restored + "assertion `left == right` failed\n",
      restored + "error: unexpected\n", restored + "---- #{test} stdout ----\n",
      restored.sub('1 passed; 0 failed', '0 passed; 0 failed'),
      restored + "thread '#{test}' panicked at tests/update_sparkle_admission.rs:94:5:\n",
      restored.sub('0 ignored', '1 ignored'), restored + "skipped\n"].each do |text|
      assert_raises(RuntimeError) { SPARKLE_ADMISSION_ORACLE.validate!(text, test,
        passed: true, exitstatus: 0, termsig: nil, timed_out: false) }
    end
    [[101, nil, false], [0, 9, false], [0, nil, true], [0, nil, nil]].each do |status, signal, timeout|
      assert_raises(RuntimeError) { SPARKLE_ADMISSION_ORACLE.validate!(restored, test,
        passed: true, exitstatus: status, termsig: signal, timed_out: timeout) }
    end
  end

  def test_update_sparkle_admission_mutation_anchors_are_unique_full_lines_and_eight_ordinary_tests_remain_intact
    product = File.binread(File.join(BelugaCoreArtifact::CRATE, 'src/update_sparkle_admission.rs'))
    tests = File.binread(File.join(BelugaCoreArtifact::CRATE, SPARKLE_ADMISSION_ORACLE::TEST_PATH))
    assert_equal 8, tests.scan(/^#\[test\]\nfn \w+\(/).length
    product_lines = product.lines.map(&:chomp)
    SPARKLE_ADMISSION_ORACLE::CONTROLS.each do |name, path, suite, before, after, test|
      assert_equal 'src/update_sparkle_admission.rs', path, name
      assert_equal SPARKLE_ADMISSION_ORACLE::SUITE, suite, name
      assert_equal 1, product.scan(before).length, name
      assert_equal 1, product_lines.count(before), name
      refute_equal before, after, name
      refute_includes product_lines, after, name
      assert_equal 1, tests.scan("fn #{test}(").length, name
    end
  end
end
