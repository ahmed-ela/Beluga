import Foundation
import XCTest
@testable import CaptureServer

final class BelugaAudioShareOwnerGateTests: XCTestCase {
    func testOwnershipMustBeGrantedAndCannotReviveAfterRetirement() {
        let gate = BelugaAudioShareOwnerGate()
        XCTAssertFalse(gate.isValid)
        XCTAssertTrue(gate.activate())
        XCTAssertFalse(gate.activate())
        XCTAssertTrue(gate.isValid)
        gate.revoke()
        XCTAssertFalse(gate.isValid)
        XCTAssertFalse(gate.activate())
    }

    func testHostInvalidationRetiresShareAuthorityBeforeNativeShutdown() async throws {
        let gate = BelugaAudioShareOwnerGate()
        let lifetime = CaptureServiceLifetime(additionalMedia: .init(
            gate: gate, becameOwned: {}, shutdown: {
                XCTAssertFalse(gate.isValid)
                return false
            }
        ))
        try lifetime.activateAdditionalMedia()
        XCTAssertTrue(gate.isValid)
        lifetime.invalidate()
        XCTAssertFalse(gate.isValid)
        let proof = await lifetime.shutdown()
        XCTAssertFalse(proof.additionalNativeCaptureIsConfirmed)
        XCTAssertFalse(proof.allNativeCapturesAreConfirmed)
        XCTAssertFalse(CaptureServerFatalExitPolicy.mayRemoveVirtualDisplay(
            shutdownConfirmation: proof, lanAudioStopIsConfirmed: true
        ))
        XCTAssertThrowsError(try lifetime.activateAdditionalMedia())
    }
}
