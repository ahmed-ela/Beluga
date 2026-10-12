// Isolated actual-C copied-scalar bridge qualifier; no CaptureServer is loaded.
import Darwin
import Foundation
import XCTest

#if BELUGA_MIC_INPUT_LEASE_BRIDGE_FIXTURE && DEBUG
private let expectedMethods = [
    "testInputLeaseLiteralLayoutsAndAllFourCopiedOperations",
    "testInputLeaseNativeIntegerBoundaryAndNoSuccessfulSwiftFallback",
    "testInputLeaseWholeResultRejectsEveryFieldAndCoherentWrongAction",
    "testInputLeaseMalformedFactsRemainRefusedEvenWithCanonicalInvalidResult",
].sorted()

private final class BridgeObservation: NSObject, XCTestObservation {
    var started: [String] = []
    var finished: [String] = []
    var refused = false

    private func method(_ testCase: XCTestCase) -> String? {
        guard testCase is BelugaRustMicrophoneInputLeaseTests else { return nil }
        let pattern = #"^-\[(?:[A-Za-z_][A-Za-z0-9_]*\.)?BelugaRustMicrophoneInputLeaseTests (test[A-Za-z0-9_]+)\]$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: testCase.name,
                  range: NSRange(testCase.name.startIndex..., in: testCase.name)),
              let range = Range(match.range(at: 1), in: testCase.name) else { return nil }
        let name = String(testCase.name[range])
        return expectedMethods.contains(name) ? name : nil
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard let name = method(testCase), !started.contains(name) else { refused = true; return }
        started.append(name)
        print("MIC_INPUT_LEASE_XCTEST_STARTED \(name)")
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let name = method(testCase), started.contains(name), !finished.contains(name),
              let run = testCase.testRun, run.testCaseCount == 1, run.executionCount == 1,
              run.skipCount == 0, run.totalFailureCount == 0, run.hasSucceeded else {
            refused = true; return
        }
        finished.append(name)
        print("MIC_INPUT_LEASE_XCTEST_FINISHED \(name)")
    }
}

private let observation = BridgeObservation()
XCTestObservationCenter.shared.addTestObserver(observation)
let suite = BelugaRustMicrophoneInputLeaseTests.defaultTestSuite
guard suite.testCaseCount == 4 else { exit(1) }
suite.run()
guard let run = suite.testRun, run.testCaseCount == 4, run.executionCount == 4,
      run.skipCount == 0, run.totalFailureCount == 0, run.hasSucceeded,
      !observation.refused, observation.started.sorted() == expectedMethods,
      observation.finished.sorted() == expectedMethods else { exit(1) }
print("MIC_INPUT_LEASE_XCTEST_COUNTS cases=4 executions=4 skipped=0 failures=0")
XCTestObservationCenter.shared.removeTestObserver(observation)
#elseif BELUGA_MIC_INPUT_LEASE_BRIDGE_FIXTURE
// Release is freshly compiled to prove the production bridge does not rely on
// DEBUG corruption helpers. Its executable is deliberately never run.
print("MIC_INPUT_LEASE_RELEASE_COMPILE_ONLY")
#else
fatalError("The isolated bridge fixture define is required")
#endif
