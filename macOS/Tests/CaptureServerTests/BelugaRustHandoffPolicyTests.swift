import BelugaCore
import Foundation
import XCTest
@testable import CaptureServer

final class BelugaRustHandoffPolicyTests: XCTestCase {
    func testEveryKnownInputMatchesIndependentAdmissionAndReasonSpecification() {
        XCTAssertEqual(beluga_core_abi_version(), 1)
        for flags in UInt32(0)...UInt32(127) {
            let started = flags & 1 != 0
            let finished = flags & 2 != 0
            let changingPhone = flags & 4 != 0
            let requestInFlight = flags & 8 != 0
            let sessionReady = flags & 16 != 0
            let targetPresent = flags & 32 != 0
            let commandInstalled = flags & 64 != 0
            let expectedReason: BelugaMediaHandoffDisabledReason
            if finished { expectedReason = .stopped }
            else if !started { expectedReason = .notStarted }
            else if changingPhone { expectedReason = .changingPhone }
            else if requestInFlight { expectedReason = .requestInFlight }
            else if !sessionReady { expectedReason = .waitingForSession }
            else if !targetPresent { expectedReason = .targetUnavailable }
            else if !commandInstalled { expectedReason = .commandUnavailable }
            else { expectedReason = .ready }
            let expectedEnabled = started && !finished && !changingPhone && !requestInFlight
                && sessionReady && targetPresent && commandInstalled

            let result = BelugaRustHandoffPolicy.evaluate(
                hasStarted: started, finished: finished, changingPhone: changingPhone,
                requestInFlight: requestInFlight, sessionReady: sessionReady,
                targetPresent: targetPresent, commandInstalled: commandInstalled
            )
            XCTAssertEqual(result.visible, started, "Input \(flags)")
            XCTAssertEqual(result.enabled, expectedEnabled, "Input \(flags)")
            XCTAssertEqual(result.reason, expectedReason, "Input \(flags)")

            let raw = beluga_core_handoff_menu_policy(1, flags)
            XCTAssertEqual(raw.abi_version, 1, "Input \(flags)")
            XCTAssertEqual(raw.visible, started ? 1 : 0, "Input \(flags)")
            XCTAssertEqual(raw.enabled, expectedEnabled ? 1 : 0, "Input \(flags)")
            XCTAssertEqual(raw.reason, expectedReason.rawValue, "Input \(flags)")
        }
    }

    func testUnknownAbiCannotEnableOrHideStartedControl() {
        for version in [UInt32(0), 2, .max] {
            for flags in [UInt32(0), 1, 113, 127] {
                let result = beluga_core_handoff_menu_policy(version, flags)
                XCTAssertEqual(result.abi_version, 1)
                XCTAssertEqual(result.visible, flags & 1)
                XCTAssertEqual(result.enabled, 0)
                XCTAssertEqual(result.reason, 8)
            }
        }
    }

    func testEveryUnknownFlagBitFailsClosedEvenWhenAdmissionFlagsAreReady() {
        // Bits 0, 4, 5 and 6 are the independently specified admitted state.
        let admitted: UInt32 = 113
        for offset in 7..<32 {
            let unknown = UInt32(1) << offset
            for flags in [unknown, unknown | admitted] {
                let result = beluga_core_handoff_menu_policy(1, flags)
                XCTAssertEqual(result.abi_version, 1)
                XCTAssertEqual(result.visible, flags & 1, "Unknown bit \(offset)")
                XCTAssertEqual(result.enabled, 0, "Unknown bit \(offset)")
                XCTAssertEqual(result.reason, 9, "Unknown bit \(offset)")
            }
        }
        let allUnknown = beluga_core_handoff_menu_policy(1, .max)
        XCTAssertEqual(allUnknown.visible, 1)
        XCTAssertEqual(allUnknown.enabled, 0)
        XCTAssertEqual(allUnknown.reason, 9)
    }

    func testAbiFailureTakesPrecedenceOverUnknownFlagsAndRuntimeReadiness() {
        let result = beluga_core_handoff_menu_policy(0, .max)
        XCTAssertEqual(result.abi_version, 1)
        XCTAssertEqual(result.visible, 1)
        XCTAssertEqual(result.enabled, 0)
        XCTAssertEqual(result.reason, 8)
    }

    func testMalformedForeignOutputFailsClosedWithoutHidingStartedControl() {
        for started in [false, true] {
            let visible: UInt32 = started ? 1 : 0
            let malformed: [(UInt32, UInt32, UInt32, UInt32)] = [
                (0, visible, 0, 6), (2, visible, 0, 6), (.max, visible, 0, 6),
                (1, visible ^ 1, 0, 6),
                (1, 2, 0, 6), (1, .max, 0, 6),
                (1, visible, 2, 6), (1, visible, .max, 6),
                (1, visible, 0, 9), (1, visible, 0, .max),
                (1, visible, 0, 0), (1, visible, 1, 1), (1, 0, 1, 0)
            ]
            for (version, returnedVisibility, enabled, reason) in malformed {
                var raw = beluga_core_handoff_menu_policy_t()
                raw.abi_version = version
                raw.visible = returnedVisibility
                raw.enabled = enabled
                raw.reason = reason
                let result = BelugaRustHandoffPolicy.decode(raw, hasStarted: started)
                XCTAssertEqual(result.visible, started)
                XCTAssertFalse(result.enabled)
                XCTAssertEqual(result.reason, .incompatibleCore)
            }
        }
    }

    func testDisabledReasonsAlwaysHaveAnExplanationButReadyDoesNot() {
        XCTAssertNil(BelugaMediaHandoffDisabledReason.ready.message)
        for raw in UInt32(1)...UInt32(8) {
            let reason = BelugaMediaHandoffDisabledReason(rawValue: raw)
            XCTAssertNotNil(reason)
            XCTAssertFalse(reason?.message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        XCTAssertNil(BelugaMediaHandoffDisabledReason(rawValue: 9))
        XCTAssertNil(BelugaMediaHandoffDisabledReason(rawValue: .max))
    }
}
