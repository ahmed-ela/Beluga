import XCTest
@testable import BelugaUpdateCore
@testable import CaptureServer

final class BelugaUpdateTransactionTests: XCTestCase {
    private var idleAdmission: BelugaUpdateAdmission {
        BelugaUpdateAdmission(isInteractiveApplication: true, teardownComplete: true)
    }

    func testManualReservationImmediatelyFencesRuntimeBeforeSparkleProbe() {
        var policy = BelugaUpdateTransaction()
        XCTAssertFalse(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        XCTAssertTrue(policy.reserveInteractiveCheck(admission: idleAdmission,
                                                     sparkleSessionInProgress: false))
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false),
                      "Runtime start must be fenced even before Sparkle's async probe begins")
        XCTAssertFalse(policy.reserveInteractiveCheck(admission: idleAdmission,
                                                      sparkleSessionInProgress: false))
        XCTAssertTrue(policy.admitCheck(.interactive, admission: idleAdmission))
    }

    func testSparkleBackgroundProbeFencesRuntimeBeforeItsAdmissionCallback() {
        var policy = BelugaUpdateTransaction()
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: true))
        XCTAssertFalse(policy.reserveInteractiveCheck(admission: idleAdmission,
                                                      sparkleSessionInProgress: true))
        XCTAssertTrue(policy.admitCheck(.background, admission: idleAdmission))
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false))
    }

    func testStreamingBeginningDuringDownloadCannotPassFinalInstallGate() {
        var policy = BelugaUpdateTransaction()
        XCTAssertTrue(policy.reserveInteractiveCheck(admission: idleAdmission,
                                                     sparkleSessionInProgress: false))
        XCTAssertTrue(policy.admitCheck(.interactive, admission: idleAdmission))
        var streaming = idleAdmission
        streaming.hasActiveMedia = true
        XCTAssertFalse(policy.admitInstallation(admission: streaming,
                                                sparkleSessionInProgress: true))
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false),
                      "A denied install remains fenced until Sparkle actually completes")
        policy.finishCycle(.interactive, sparkleSessionInProgress: true)
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        policy.finishCycle(.interactive, sparkleSessionInProgress: false)
        XCTAssertFalse(policy.isUpdateInProgress(sparkleSessionInProgress: false))
    }

    func testEveryFreshAdmissionDimensionCanRefuseInstallation() {
        var states: [BelugaUpdateAdmission] = []
        var state = idleAdmission; state.isInteractiveApplication = false; states.append(state)
        state = idleAdmission; state.hasActiveMedia = true; states.append(state)
        state = idleAdmission; state.hasPendingPairing = true; states.append(state)
        state = idleAdmission; state.hasAudioShares = true; states.append(state)
        state = idleAdmission; state.teardownComplete = false; states.append(state)
        for denied in states {
            var policy = BelugaUpdateTransaction()
            XCTAssertTrue(policy.admitCheck(.background, admission: idleAdmission))
            XCTAssertFalse(policy.admitInstallation(admission: denied,
                                                    sparkleSessionInProgress: true))
            XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        }
    }

    func testInstallRequiresAcceptedNonInformationalCheckAndLiveSparkleSession() {
        var policy = BelugaUpdateTransaction()
        XCTAssertFalse(policy.admitInstallation(admission: idleAdmission,
                                                sparkleSessionInProgress: true))
        XCTAssertTrue(policy.admitCheck(.information, admission: idleAdmission))
        XCTAssertFalse(policy.admitInstallation(admission: idleAdmission,
                                                sparkleSessionInProgress: true))
        policy.finishCycle(.information, sparkleSessionInProgress: false)
        XCTAssertTrue(policy.admitCheck(.interactive, admission: idleAdmission))
        XCTAssertFalse(policy.admitInstallation(admission: idleAdmission,
                                                sparkleSessionInProgress: false))
        XCTAssertTrue(policy.admitInstallation(admission: idleAdmission,
                                               sparkleSessionInProgress: true))
        XCTAssertFalse(policy.admitCheck(.background, admission: idleAdmission))
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false))
    }

    func testOnlyMatchingActualCompletionReleasesReservationOrActiveCheck() {
        var policy = BelugaUpdateTransaction()
        XCTAssertTrue(policy.reserveInteractiveCheck(admission: idleAdmission,
                                                     sparkleSessionInProgress: false))
        policy.finishCycle(.background, sparkleSessionInProgress: false)
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        XCTAssertFalse(policy.admitCheck(.background, admission: idleAdmission))
        XCTAssertTrue(policy.admitCheck(.interactive, admission: idleAdmission))
        policy.finishCycle(.information, sparkleSessionInProgress: false)
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        policy.finishCycle(.interactive, sparkleSessionInProgress: false)
        XCTAssertFalse(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        policy.finishCycle(.interactive, sparkleSessionInProgress: false)
        XCTAssertFalse(policy.isUpdateInProgress(sparkleSessionInProgress: false))
    }

    func testAutomaticChecksCannotAdmitWhileHostOrTeardownIsBusy() {
        for check in [BelugaUpdateTransaction.Check.background, .information] {
            var policy = BelugaUpdateTransaction()
            var busy = idleAdmission; busy.hasActiveMedia = true
            XCTAssertFalse(policy.admitCheck(check, admission: busy))
            XCTAssertFalse(policy.isUpdateInProgress(sparkleSessionInProgress: false))
            busy = idleAdmission; busy.teardownComplete = false
            XCTAssertFalse(policy.admitCheck(check, admission: busy))
            XCTAssertTrue(policy.admitCheck(check, admission: idleAdmission))
            policy.finishCycle(check, sparkleSessionInProgress: false)
            XCTAssertFalse(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        }
    }

    func testImmediateBackgroundContinuationKeepsFenceUntilNewCycleCompletes() {
        var policy = BelugaUpdateTransaction()
        XCTAssertTrue(policy.admitCheck(.background, admission: idleAdmission))
        // Sparkle omits the prior completion when immediately handing a resumable update to
        // its next serial driver. Do not clear authority in that brief session=false window.
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        XCTAssertTrue(policy.admitCheck(.interactive, admission: idleAdmission))
        policy.finishCycle(.background, sparkleSessionInProgress: false)
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        policy.finishCycle(.interactive, sparkleSessionInProgress: false)
        XCTAssertFalse(policy.isUpdateInProgress(sparkleSessionInProgress: false))

        XCTAssertTrue(policy.admitCheck(.background, admission: idleAdmission))
        var busy = idleAdmission; busy.hasAudioShares = true
        XCTAssertFalse(policy.admitCheck(.interactive, admission: busy))
        XCTAssertTrue(policy.isUpdateInProgress(sparkleSessionInProgress: false))
        policy.finishCycle(.interactive, sparkleSessionInProgress: false)
        XCTAssertFalse(policy.isUpdateInProgress(sparkleSessionInProgress: false))
    }
}
