import BelugaCore
import Foundation
import XCTest
@testable import CaptureServer

/// Actual linked C producer/verifier with native copied-state adoption. These do not
/// substitute for the separate actor/task drain tests or installed handoff proof.
final class BelugaRustRuntimeCatalogTests: XCTestCase {
    func testExactLinkedLayoutAndAllNativeStageIDs() {
        XCTAssertTrue(BelugaRustRuntimeCatalog.layoutIsExact)
        XCTAssertEqual(BelugaRustRuntimeCatalog.Stage.allCases.map(\.rawValue), Array(0..<58))
        XCTAssertEqual(BelugaRustRuntimeCatalog.flags([true, false, true]), 5)
    }

    func testFirstPairGrantIsHistoricalAndConsumedBeforeBootstrapStop() throws {
        var owner = BelugaRustRuntimeCatalog()
        try owner.require(.startupInstalled, [true, true, true, true, true])
        XCTAssertEqual(owner.state.eligible, 1)
        let begin = try owner.require(.begin, [true, true], operation: .pair)
        XCTAssertEqual(begin.value, 1)
        XCTAssertEqual(owner.state.eligible, 0)
        XCTAssertEqual(owner.state.first_grant, 1)
        try owner.require(.retirementEnter, [true, true])
        let drain = try owner.require(.retirementDrained, [true])
        XCTAssertEqual(drain.value, 1)
        try owner.require(.retirementFinish, [true, true])
        let installed = try owner.require(.installIntent, [true])
        XCTAssertEqual(installed.value, 1)
        XCTAssertEqual(owner.state.first_grant, 0)
        XCTAssertEqual(owner.state.intent, 1)
        try owner.require(.end, [true, true])
        XCTAssertEqual(owner.state.intent, 1)
        let taken = try owner.require(.takeIntent, [true])
        XCTAssertEqual(taken.value, 1)
        XCTAssertEqual(owner.state.intent, 0)
        XCTAssertEqual(try owner.require(.takeIntent, [false]).value, 0)
        XCTAssertFalse(owner.isPoisoned)
    }

    func testValidRefusalPreservesStateWithoutPoisonAndNativeErrorOrdering() throws {
        var owner = BelugaRustRuntimeCatalog()
        let before = words(owner.state)
        XCTAssertThrowsError(try owner.require(.preflight, [true, false], operation: .select)) {
            XCTAssertEqual($0 as? WorldwidePairedPhoneCatalogError, .unknownPhone)
        }
        XCTAssertThrowsError(try owner.require(.preflight, [false, false, true, false, false], operation: .pair)) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertThrowsError(try owner.require(.preflight, [false, false, false, false, false], operation: .pair)) {
            XCTAssertEqual($0 as? WorldwidePairedPhoneCatalogError, .capacityReached)
        }
        XCTAssertEqual(words(owner.state), before)
        XCTAssertFalse(owner.isPoisoned)
        try owner.require(.owner, [true])
    }

    func testMalformedResultCannotInstallStateOrGrantAuthority() throws {
        var owner = BelugaRustRuntimeCatalog(resultMutation: { _, event, actual in
            guard event.opcode == BelugaRustRuntimeCatalog.Stage.begin.rawValue else { return actual }
            var altered = actual
            altered.state.first_grant ^= 1
            return altered
        })
        try owner.require(.startupInstalled, [true, true, true, true, true])
        let retained = words(owner.state)
        assertBridgeError { try owner.require(.begin, [true, true], operation: .pair) }
        XCTAssertEqual(words(owner.state), retained)
        XCTAssertTrue(owner.isPoisoned)
        XCTAssertFalse(owner.permits(.owner, [true]))
        assertBridgeError { try owner.require(.takeIntent, [false]) }
        owner.revoke()
        XCTAssertEqual(words(owner.state), retained, "Native cleanup cannot counterfeit a verified revoke")
    }

    func testEveryResultByteBitIsRejectedBeforeNativeStateAdoptionAndPoisonIsSticky() throws {
        for byte in 0..<40 {
            for bit in 0..<8 {
                let calls = RuntimeCatalogBridgeCallCounter()
                var owner = BelugaRustRuntimeCatalog(resultMutation: { _, event, actual in
                    calls.increment()
                    guard event.opcode == BelugaRustRuntimeCatalog.Stage.begin.rawValue else { return actual }
                    var altered = actual
                    withUnsafeMutableBytes(of: &altered) { $0[byte] ^= UInt8(1 << bit) }
                    return altered
                })
                try owner.require(.startupInstalled, [true, true, true, true, true])
                let retained = words(owner.state)
                assertBridgeError { try owner.require(.begin, [true, true], operation: .pair) }
                XCTAssertEqual(words(owner.state), retained, "byte=\(byte) bit=\(bit)")
                let countAtFault = calls.value
                XCTAssertFalse(owner.permits(.owner, [true]))
                assertBridgeError { try owner.require(.clearIntent) }
                owner.revoke()
                XCTAssertEqual(calls.value, countAtFault, "Poison must not call the producer again")
                XCTAssertEqual(words(owner.state), retained)
            }
        }
    }

    func testMalformedEventEchoCannotBecomeVerifiedSuccess() throws {
        for field in 0..<4 {
            var owner = BelugaRustRuntimeCatalog()
            let retained = words(owner.state)
            var event = BelugaRustRuntimeCatalog.Event()
            event.opcode = BelugaRustRuntimeCatalog.Stage.owner.rawValue
            event.facts = 1
            switch field {
            case 0: event.opcode = UInt32.max
            case 1: event.operation = 1
            case 2: event.facts = 2
            default: event.reserved = 1
            }
            assertBridgeError { try owner.checked(event) }
            XCTAssertEqual(words(owner.state), retained)
            XCTAssertTrue(owner.isPoisoned)
        }
    }

    func testCallerCannotRecreateConsumedFirstPairGrant() throws {
        var owner = BelugaRustRuntimeCatalog()
        try owner.require(.startupInstalled, [true, true, true, true, true])
        XCTAssertEqual(owner.state.eligible, 1)
        XCTAssertEqual(try owner.require(.begin, [true, true], operation: .select).value, 0)
        try owner.require(.retirementDrained, [true])
        try owner.require(.end, [true, true])
        XCTAssertEqual(owner.state.eligible, 0)
        try owner.require(.begin, [true, true], operation: .pair)
        try owner.require(.retirementDrained, [true])
        let retained = words(owner.state)
        assertBridgeError { try owner.require(.installIntent, [true]) }
        XCTAssertEqual(words(owner.state), retained)
    }

    func testRevokedCopiedAuthorityAllowsOnlyExactRetainedDrainNotNewAdmission() throws {
        var owner = BelugaRustRuntimeCatalog()
        try owner.require(.begin, [true, true], operation: .select)
        owner.revoke()
        XCTAssertEqual(owner.state.phase, 3)
        try owner.require(.retirementEnter, [true, true])
        XCTAssertEqual(try owner.require(.retirementDrained, [true]).value, 1)
        XCTAssertThrowsError(try owner.require(.retirementFinish, [true, true])) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(owner.permits(.owner, [true]))
        XCTAssertFalse(owner.isPoisoned)
        try owner.require(.preparedRetire, [true, true, true])
        XCTAssertEqual(owner.state.phase, 3)
    }

    private func words(_ s: BelugaRustRuntimeCatalog.State) -> [UInt32] {
        [s.abi_version, s.phase, s.operation, s.eligible, s.intent, s.first_grant]
    }
    private func assertBridgeError<T>(_ body: () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? WorldwidePhoneCatalogRuntimeError, .invalidRuntimeCatalogBridge, file: file, line: line)
        }
    }
}

private final class RuntimeCatalogBridgeCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
