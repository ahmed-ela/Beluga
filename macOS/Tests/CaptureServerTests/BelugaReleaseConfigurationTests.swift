import Foundation
import XCTest
@testable import BelugaUpdateCore
@testable import CaptureServer

final class BelugaReleaseConfigurationTests: XCTestCase {
    private var valid: [String: Any] {
        [
            "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "100",
            "SUFeedURL": "https://updates.beluga.test/mac/appcast.xml",
            "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
            "SUVerifyUpdateBeforeExtraction": true, "SURequireSignedFeed": true,
            "SUAllowsAutomaticUpdates": false
        ]
    }

    func testCompleteSignedDistributionConfiguration() throws {
        let value = try BelugaReleaseConfiguration(info: valid)
        XCTAssertEqual(value.version, "0.2.0")
        XCTAssertEqual(value.build, 100)
        XCTAssertEqual(value.publicKey.count, 32)
    }

    func testEverySecurityFieldIsRequired() {
        for key in valid.keys {
            var info = valid
            info.removeValue(forKey: key)
            XCTAssertThrowsError(try BelugaReleaseConfiguration(info: info), key)
        }
    }

    func testInsecureFeedAndKeyMutationsAreRejected() {
        let mutations: [(String, Any)] = [
            ("SUFeedURL", "http://updates.beluga.test/mac/appcast.xml"),
            ("SUFeedURL", "https://user:password@updates.beluga.test/mac/appcast.xml"),
            ("SUFeedURL", "https://updates.beluga.test/mac/appcast.xml?token=secret"),
            ("SUFeedURL", "https://updates.beluga.test/mac/appcast.xml#token"),
            ("SUFeedURL", "https://localhost/mac/appcast.xml"),
            ("SUFeedURL", "https://placeholder.invalid/mac/appcast.xml"),
            ("SUPublicEDKey", Data(repeating: 0, count: 32).base64EncodedString()),
            ("SUPublicEDKey", Data(repeating: 7, count: 31).base64EncodedString()),
            ("CFBundleShortVersionString", "0.02.0"),
            ("CFBundleShortVersionString", "1.0"),
            ("CFBundleVersion", "0100"), ("CFBundleVersion", "0"),
            ("SUVerifyUpdateBeforeExtraction", false), ("SURequireSignedFeed", false),
            ("SUAllowsAutomaticUpdates", true)
        ]
        for (key, value) in mutations {
            var info = valid
            info[key] = value
            XCTAssertThrowsError(try BelugaReleaseConfiguration(info: info), key)
        }
    }

    func testUpdateWaitsForEveryOwnedActivityAndTeardown() {
        let quiet = BelugaUpdateAdmission(isInteractiveApplication: true,
                                         teardownComplete: true)
        XCTAssertTrue(quiet.permitsUpdate)
        var states = [BelugaUpdateAdmission]()
        var state = quiet; state.isInteractiveApplication = false; states.append(state)
        state = quiet; state.hasActiveMedia = true; states.append(state)
        state = quiet; state.hasPendingPairing = true; states.append(state)
        state = quiet; state.hasAudioShares = true; states.append(state)
        state = quiet; state.teardownComplete = false; states.append(state)
        for value in states { XCTAssertFalse(value.permitsUpdate) }
    }
}
