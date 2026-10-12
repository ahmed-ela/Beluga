import BelugaCore
import BelugaUpdateCore
import XCTest

final class BelugaRustUpdateAvailabilityTests: XCTestCase {
    private typealias Bridge = BelugaRustUpdateAvailability

    private func admission(_ flags: UInt32) -> BelugaUpdateAdmission {
        .init(isInteractiveApplication: flags & 1 != 0, hasActiveMedia: flags & 2 != 0,
              hasPendingPairing: flags & 4 != 0, hasAudioShares: flags & 8 != 0,
              teardownComplete: flags & 16 != 0)
    }

    // Independently retained original Swift predicates and status precedence.
    private func reference(_ flags: UInt32) -> Bridge.Snapshot {
        let permits = flags & 1 != 0 && flags & 16 != 0
            && flags & (2 | 4 | 8) == 0
        let release = flags & 32 != 0
        let busy = flags & (64 | 128) != 0
        let failed = flags & 256 != 0
        let inProgress = release && (busy || failed)
        let status: Bridge.Status = !release ? .development : failed ? .recovery
            : busy ? .owned : permits ? .ready : .unavailable
        return .init(permitsUpdate: permits, isUpdateInProgress: inProgress,
                     canCheckForUpdates: release && !inProgress && permits, status: status)
    }

    func testExactCopiedLayoutsAndAll512OriginalPolicyCombinations() throws {
        XCTAssertTrue(Bridge.layoutIsExact)
        for flags: UInt32 in 0..<512 {
            let raw = Bridge.Request(abi_version: 1, flags: flags)
            let expected = reference(flags)
            XCTAssertEqual(Bridge.evaluate(raw), expected, "flags=\(flags)")
            XCTAssertEqual(Bridge.evaluate(admission(flags), isRelease: flags & 32 != 0,
                taskInProgress: flags & 64 != 0, needsReadiness: flags & 128 != 0,
                failed: flags & 256 != 0), expected, "native flags=\(flags)")
            XCTAssertEqual(admission(flags).permitsUpdate, expected.permitsUpdate)
            let actual = beluga_core_update_admission_decide(raw)
            XCTAssertEqual(beluga_core_update_admission_result_is_valid(raw, actual), 1)
        }
    }

    func testUnknownABIAndEveryUnknownFlagDenyWithoutForeignAuthority() {
        for abi: UInt32 in [0, 2, .max] {
            XCTAssertNil(Bridge.evaluate(.init(abi_version: abi, flags: 49)))
        }
        for bit in 9..<32 {
            for flags: UInt32 in [0, 49, 511] {
                let request = Bridge.Request(abi_version: 1, flags: flags | UInt32(1) << bit)
                let denied = beluga_core_update_admission_decide(request)
                XCTAssertEqual(denied.status, 1)
                XCTAssertEqual(denied.permits_update, 0)
                XCTAssertEqual(denied.can_check, 0)
                XCTAssertEqual(denied.is_in_progress, 1)
                XCTAssertEqual(denied.status_kind, 1)
                XCTAssertEqual(beluga_core_update_admission_result_is_valid(request, denied), 0)
                XCTAssertNil(Bridge.evaluate(request))
            }
        }
    }

    func testEveryCopiedResultFieldIsVerifiedAgainstTheActualRequest() {
        for flags: UInt32 in [0, 49, 51, 113, 177, 305] {
            let request = Bridge.Request(abi_version: 1, flags: flags)
            for field in 0..<6 {
                XCTAssertNil(Bridge.evaluate(request, resultMutation: { _, actual in
                    var result = actual
                    switch field {
                    case 0: result.abi_version = 2
                    case 1: result.status = 1
                    case 2: result.permits_update ^= 1
                    case 3: result.is_in_progress ^= 1
                    case 4: result.can_check ^= 1
                    default: result.status_kind = (result.status_kind + 1) % 5
                    }
                    return result
                }), "flags=\(flags), field=\(field)")
            }
        }
    }

    func testCoherentForeignPlansCannotGrantOrEraseRecoveryAndNoFallbackExists() {
        for (current, foreign): (UInt32, UInt32) in [(51, 49), (305, 49), (113, 49),
                                                    (177, 49), (49, 51), (0, 49)] {
            let request = Bridge.Request(abi_version: 1, flags: current)
            XCTAssertNil(Bridge.evaluate(request, resultMutation: { _, _ in
                beluga_core_update_admission_decide(.init(abi_version: 1, flags: foreign))
            }))
            XCTAssertEqual(Bridge.evaluate(request), reference(current))
        }
    }
}
