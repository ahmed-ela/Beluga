// Pure copied-value parity runner. No native CaptureServer target is loaded.
import Darwin
import XCTest

// This separate fixture build must define BELUGA_HANDOFF_PURE_STUB_FIXTURE,
// use a copied C-module header and actual admitted copied Rust exports, and link
// only Foundation/XCTest. Never import/load CaptureServer or native frameworks.
#if BELUGA_HANDOFF_PURE_STUB_FIXTURE
let suite = BelugaRustMacChromeHandoffSourcePolicyTests.defaultTestSuite
suite.run()
guard let run = suite.testRun, run.testCaseCount == 9, run.executionCount == 9,
      run.skipCount == 0, run.totalFailureCount == 0, run.hasSucceeded else { exit(1) }
#else
fatalError("Pure source harness cannot load the native CaptureServer target")
#endif
