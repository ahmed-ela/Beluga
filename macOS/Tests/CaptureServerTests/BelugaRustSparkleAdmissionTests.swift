import BelugaCore
import BelugaUpdateCore
import XCTest

final class BelugaRustSparkleAdmissionTests: XCTestCase {
    private typealias Bridge = BelugaRustSparkleAdmission

    private func reference(phase: UInt32, flags: UInt32) -> Bridge.Action {
        if phase == 1 {
            return flags & 1 == 0 ? .foreignUpdater : flags & 2 == 0 ? .nonManualCheck
                : flags & 4 == 0 ? .authorityNotRetained : .queryAuthority
        }
        return flags & 1 == 0 ? .authorityNotRetained : flags & 2 == 0
            ? .checkNotRequested : .consumeAndAdmit
    }

    func testExactLayoutsAndTwelveOriginalGuardCombinationsThroughActualABI() {
        XCTAssertTrue(Bridge.layoutIsExact)
        for (phase, count): (UInt32, UInt32) in [(1, 8), (2, 4)] {
            for flags in 0..<count {
                let raw = Bridge.Request(abi_version: 1, phase: phase, flags: flags)
                let expected = reference(phase: phase, flags: flags)
                XCTAssertEqual(Bridge.evaluate(raw), expected)
                let actual = beluga_core_update_sparkle_admission_decide(raw)
                XCTAssertEqual(actual.action, expected.rawValue)
                XCTAssertEqual(beluga_core_update_sparkle_admission_result_is_valid(raw, actual), 1)
                if phase == 1 {
                    XCTAssertEqual(Bridge.prefix(exactCallback: flags & 1 != 0,
                        manualCheck: flags & 2 != 0, running: flags & 4 != 0), expected)
                } else {
                    XCTAssertEqual(Bridge.finish(retained: flags & 1 != 0,
                        freshRequest: flags & 2 != 0), expected)
                }
            }
        }
    }

    func testUnknownABIPhaseAndEveryPhaseSpecificUnknownFlagRefuse() {
        for abi: UInt32 in [0, 2, .max] {
            for phase: UInt32 in [1, 2] {
                XCTAssertNil(Bridge.evaluate(.init(abi_version: abi, phase: phase, flags: 3)))
            }
        }
        for phase: UInt32 in [0, 3, .max] {
            XCTAssertNil(Bridge.evaluate(.init(abi_version: 1, phase: phase, flags: 3)))
        }
        for (phase, firstBit, count): (UInt32, Int, UInt32) in [(1, 3, 8), (2, 2, 4)] {
            for bit in firstBit..<32 {
                for flags in 0..<count {
                    let raw = Bridge.Request(abi_version: 1, phase: phase,
                        flags: flags | UInt32(1) << bit)
                    let denied = beluga_core_update_sparkle_admission_decide(raw)
                    XCTAssertEqual(denied.abi_version, 1)
                    XCTAssertEqual(denied.status, 1)
                    XCTAssertEqual(denied.action, 0)
                    XCTAssertEqual(beluga_core_update_sparkle_admission_result_is_valid(raw, denied), 0)
                    XCTAssertNil(Bridge.evaluate(raw))
                }
            }
        }
    }

    func testEveryResultFieldAndCoherentWrongActionsAreCorrelatedToActualRequest() {
        for (phase, count): (UInt32, UInt32) in [(1, 8), (2, 4)] {
            for flags in 0..<count {
                let raw = Bridge.Request(abi_version: 1, phase: phase, flags: flags)
                for field in 0..<3 {
                    XCTAssertNil(Bridge.evaluate(raw, resultMutation: { _, actual in
                        var result = actual
                        switch field {
                        case 0: result.abi_version = 2
                        case 1: result.status = 1
                        default: result.action = result.action % 6 + 1
                        }
                        return result
                    }))
                }
                for action: UInt32 in 0...7 where action != reference(phase: phase, flags: flags).rawValue {
                    XCTAssertNil(Bridge.evaluate(raw, resultMutation: { _, _ in
                        Bridge.Result(abi_version: 1, status: 0, action: action)
                    }))
                }
            }
        }
    }

    func testQueryAndAdmissionCannotCrossVerifiedPhasesAndValidDenialsStayValid() {
        let prefix = Bridge.Request(abi_version: 1, phase: 1, flags: 7)
        let finish = Bridge.Request(abi_version: 1, phase: 2, flags: 3)
        XCTAssertNil(Bridge.evaluate(prefix, resultMutation: { _, _ in
            beluga_core_update_sparkle_admission_decide(finish)
        }))
        XCTAssertNil(Bridge.evaluate(finish, resultMutation: { _, _ in
            beluga_core_update_sparkle_admission_decide(prefix)
        }))
        XCTAssertEqual(Bridge.evaluate(.init(abi_version: 1, phase: 1, flags: 0)), .foreignUpdater)
        XCTAssertEqual(Bridge.evaluate(.init(abi_version: 1, phase: 1, flags: 1)), .nonManualCheck)
        XCTAssertEqual(Bridge.evaluate(.init(abi_version: 1, phase: 2, flags: 2)), .authorityNotRetained)
        XCTAssertEqual(Bridge.evaluate(.init(abi_version: 1, phase: 2, flags: 1)), .checkNotRequested)
    }
}
