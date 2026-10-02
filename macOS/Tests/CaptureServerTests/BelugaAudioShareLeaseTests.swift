import Foundation
import XCTest
@testable import CaptureServer

final class BelugaAudioShareLeaseTests: XCTestCase {
    private let nonce = "AAAAAAAAAAAAAAAAAAAAAA"
    func testExactFreshNonceAdvancesOnlyBoundedOriginalOwnerLease() {
        let clock = ShareLeaseClock()
        let lease = BelugaAudioShareLease(absoluteDeadline: 20_000_000_000,
            authenticationDeadline: 5_000_000_000, now: clock.read)
        XCTAssertTrue(lease.expectAcknowledgement(nonce: nonce))
        XCTAssertFalse(lease.expectAcknowledgement(nonce: nonce))
        XCTAssertFalse(lease.acknowledge(nonce: "AQEBAQEBAQEBAQEBAQEBAQ", leaseMilliseconds: 15_000))
        XCTAssertFalse(lease.acknowledge(nonce: nonce, leaseMilliseconds: 15_001))
        clock.set(1_000_000_000)
        XCTAssertTrue(lease.acknowledge(nonce: nonce, leaseMilliseconds: 15_000))
        XCTAssertFalse(lease.acknowledge(nonce: nonce, leaseMilliseconds: 15_000))
        clock.set(14_999_999_999)
        XCTAssertTrue(lease.isValid)
        clock.set(15_000_000_001)
        XCTAssertFalse(lease.isValid, "Uses send time, not receipt time")
        XCTAssertFalse(lease.expectAcknowledgement(nonce: nonce))
    }
    func testExpiredOrRevokedOwnerNeverReopensAndAbsoluteExpiryNeverExtends() {
        let clock = ShareLeaseClock()
        let lease = BelugaAudioShareLease(absoluteDeadline: 8_000_000_000,
            authenticationDeadline: 5_000_000_000, now: clock.read)
        XCTAssertTrue(lease.expectAcknowledgement(nonce: nonce))
        XCTAssertTrue(lease.acknowledge(nonce: nonce, leaseMilliseconds: 15_000))
        clock.set(8_000_000_000)
        XCTAssertFalse(lease.isValid)
        clock.set(1)
        XCTAssertFalse(lease.isValid)
        XCTAssertFalse(lease.acknowledge(nonce: nonce, leaseMilliseconds: 15_000))
        let revoked = BelugaAudioShareLease(absoluteDeadline: 100, authenticationDeadline: 50,
                                          now: clock.read)
        XCTAssertTrue(revoked.expectAcknowledgement(nonce: nonce))
        revoked.revoke()
        XCTAssertFalse(revoked.isValid)
        XCTAssertFalse(revoked.acknowledge(nonce: nonce, leaseMilliseconds: 1))
    }
}

private final class ShareLeaseClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 1
    func read() -> UInt64 { lock.withLock { value } }
    func set(_ value: UInt64) { lock.withLock { self.value = value } }
}
