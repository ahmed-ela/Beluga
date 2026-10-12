import CaptureCore
import Foundation
import XCTest
@testable import CaptureServer

final class WorldwideScreenServiceFeatureProfileTests: XCTestCase {
    func testProductionPrimaryConfigurationAdvertisesHandoffWithAvailableMediaController() {
        let configuration = WorldwideScreenService.makePeerConfiguration(
            iceServers: [], icePolicy: .relayOnly, maximumVideoBitrate: 8_000_000,
            featureProfile: .fullPrimary, remoteMediaControllerIsAvailable: true
        )
        XCTAssertEqual(configuration.role, .host)
        XCTAssertEqual(configuration.icePolicy, .relayOnly)
        XCTAssertEqual(configuration.maximumVideoBitrate, 8_000_000)
        XCTAssertEqual(configuration.mediaTopology, .full)
        XCTAssertTrue(configuration.supportsRemoteMediaControls)
        XCTAssertTrue(configuration.supportsMediaHandoff)
        XCTAssertTrue(configuration.supportsAudioClientDiagnostics)
    }

    func testProductionHandoffConfigurationRejectsUnavailableControllerAndSecondaryOwnership() {
        for profile in [WorldwideScreenServiceFeatureProfile.fullPrimary, .secondaryTest] {
            for controllerIsAvailable in [false, true] {
                let configuration = WorldwideScreenService.makePeerConfiguration(
                    iceServers: [], icePolicy: .directPreferred, maximumVideoBitrate: 4_000_000,
                    featureProfile: profile, remoteMediaControllerIsAvailable: controllerIsAvailable
                )
                let mayControlMedia = profile == .fullPrimary && controllerIsAvailable
                XCTAssertEqual(configuration.supportsMediaHandoff, mayControlMedia)
                XCTAssertEqual(configuration.supportsRemoteMediaControls, mayControlMedia)
                XCTAssertEqual(configuration.mediaTopology, profile.transportMediaTopology)
                XCTAssertEqual(configuration.supportsAudioClientDiagnostics, profile == .fullPrimary)
            }
        }
    }

    func testFullPrimaryOwnsEveryProcessGlobalMediaFeature() {
        let profile = WorldwideScreenServiceFeatureProfile.fullPrimary

        XCTAssertTrue(profile.allowsSystemAudio)
        XCTAssertTrue(profile.allowsIPhoneMicrophoneAndDefaultInputRouting)
        XCTAssertTrue(profile.allowsNowPlaying)
        XCTAssertTrue(profile.allowsAudioClientDiagnostics)
        XCTAssertEqual(profile.transportMediaTopology, .full)
        XCTAssertEqual(
            profile.maximumVideoBitrate(configured: 50_000_000),
            50_000_000
        )
    }

    func testSecondaryTestIsScreenOnlyForProcessGlobalMediaFeatures() {
        let profile = WorldwideScreenServiceFeatureProfile.secondaryTest

        XCTAssertFalse(profile.allowsSystemAudio)
        XCTAssertFalse(profile.allowsIPhoneMicrophoneAndDefaultInputRouting)
        XCTAssertFalse(profile.allowsNowPlaying)
        XCTAssertFalse(profile.allowsAudioClientDiagnostics)
        XCTAssertEqual(profile.transportMediaTopology, .videoControlOnly)
        XCTAssertEqual(
            profile.maximumVideoBitrate(configured: 50_000_000),
            4_000_000
        )
        XCTAssertEqual(
            profile.maximumVideoBitrate(configured: 3_000_000),
            3_000_000
        )
    }

    func testSecondaryDoesNotEvenInstallAudioDiagnosticsReportStorage()
        async throws {
        let service = try WorldwideScreenService(
            endpoint: URL(string: "wss://example.invalid")!,
            forceRelay: false,
            screenDisplayID: nil,
            systemAudioDisplayID: nil,
            maximumWidth: 1_280,
            framesPerSecond: 30,
            maximumVideoBitrate: 8_000_000,
            featureProfile: .secondaryTest,
            remoteInputController: MacRemoteInputController(
                allowRemoteControl: false
            ),
            logger: ConsoleLogger(verbose: false)
        )

        let writerIsInstalled = await service
            .audioClientDiagnosticsReportWriterIsInstalledForTesting

        XCTAssertFalse(writerIsInstalled)
    }

    func testRestrictedViewerRecoveryDoesNotWaitForForbiddenAudioState() {
        XCTAssertTrue(
            WorldwideScreenService.recoveryAudioIsReady(
                allowsSystemAudio: false,
                systemAudioIsLive: false,
                audioAuthorizationIsValid: false
            )
        )
    }

    func testPrimaryRecoveryRequiresLiveAuthorizedSystemAudio() {
        XCTAssertFalse(
            WorldwideScreenService.recoveryAudioIsReady(
                allowsSystemAudio: true,
                systemAudioIsLive: false,
                audioAuthorizationIsValid: true
            )
        )
        XCTAssertFalse(
            WorldwideScreenService.recoveryAudioIsReady(
                allowsSystemAudio: true,
                systemAudioIsLive: true,
                audioAuthorizationIsValid: false
            )
        )
        XCTAssertTrue(
            WorldwideScreenService.recoveryAudioIsReady(
                allowsSystemAudio: true,
                systemAudioIsLive: true,
                audioAuthorizationIsValid: true
            )
        )
    }
}
