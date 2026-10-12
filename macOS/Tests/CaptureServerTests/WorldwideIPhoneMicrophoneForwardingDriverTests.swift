#if os(macOS) && DEBUG
import AudioToolbox
import CaptureCore
import Foundation
import XCTest
@testable import CaptureServer

final class WorldwideIPhoneMicrophoneForwardingDriverTests:
    XCTestCase
{
    func testVisibleEndpointWithoutHiddenSinkFailsClosed()
        async {
        let factory = DriverTestOutputFactory(
            outputs: [
                DriverTestOutput(
                    progressSnapshots: readyProgressSnapshots()
                ),
            ]
        )
        let harness = DriverTestHarness(factory: factory)
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            BlackHoleDeviceAvailabilitySnapshot(
                monitorEpoch: epoch,
                deviceGeneration: 1,
                defaultInputEndpoint: .init(
                    deviceID: 79,
                    deviceUID: "com.elamin.opensteamer.virtual-microphone.input"
                ),
                hiddenMirrorSinkEndpoint: nil
            )
        )

        let result = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 0)
        XCTAssertFalse(track.isEnabled)
        XCTAssertEqual(result.phase, .waitingForDevice)
        XCTAssertEqual(result.deviceUID, "com.elamin.opensteamer.virtual-microphone.input")
        XCTAssertNil(result.sinkDeviceUID)
        XCTAssertFalse(result.hiddenWriterSelectionProven)
    }

    func testTransientOutputConstructionFailureRetriesSameGenerationAndBecomesHealthy()
        async {
        let retryGate = DriverSuspensionGate()
        let ready = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(outputs: [])
        let harness = DriverTestHarness(
            factory: factory,
            retryGate: retryGate
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(
            peer: peer,
            generation: 1
        )

        let availableSnapshot = snapshot(
            epoch: epoch,
            generation: 1,
            available: true
        )
        let drive = Task {
            await harness.updateDevice(availableSnapshot)
        }

        let retryWasScheduled = await eventually {
            guard factory.requestCount == 1 else {
                return false
            }
            return await retryGate.hasEntered()
        }
        XCTAssertTrue(retryWasScheduled)
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertFalse(track.isEnabled)
        let unavailable = await harness.snapshot()
        XCTAssertEqual(
            unavailable.phase,
            .outputUnavailable
        )
        XCTAssertEqual(
            unavailable.lastFailureCategory,
            .outputUnavailable
        )
        XCTAssertEqual(unavailable.attemptGeneration, 1)

        factory.append(ready)
        await retryGate.open()
        await drive.value

        let final = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertEqual(
            factory.requestedUIDs,
            [
                "com.elamin.opensteamer.virtual-microphone.writer",
                "com.elamin.opensteamer.virtual-microphone.writer",
            ]
        )
        XCTAssertEqual(factory.requestedDeviceIDs, [89, 89])
        XCTAssertEqual(ready.startCount, 1)
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(final.phase, .forwardingHealthy)
        XCTAssertTrue(final.exactTrackAdmitted)
        XCTAssertTrue(final.queueRunning)
        XCTAssertTrue(final.hiddenWriterSelectionProven)
        XCTAssertEqual(final.attemptGeneration, 2)
        XCTAssertEqual(
            final.currentKey?.deviceGeneration,
            1
        )
    }

    func testTransientStartFailureRetriesSameGenerationAndBecomesHealthy()
        async {
        let retryGate = DriverSuspensionGate()
        let failing = DriverTestOutput(
            startError: DriverTestError.start
        )
        let ready = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [failing, ready]
        )
        let harness = DriverTestHarness(
            factory: factory,
            retryGate: retryGate
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: false
            )
        )
        XCTAssertEqual(factory.requestCount, 0)
        XCTAssertFalse(track.isEnabled)
        let waitingForDevicePhase = await harness.snapshot().phase
        XCTAssertEqual(
            waitingForDevicePhase,
            .waitingForDevice
        )

        let availableSnapshot = snapshot(
            epoch: epoch,
            generation: 2,
            available: true
        )
        let drive = Task {
            await harness.updateDevice(availableSnapshot)
        }
        let retryWasScheduled = await eventually {
            guard failing.startCount == 1 else {
                return false
            }
            return await retryGate.hasEntered()
        }
        XCTAssertTrue(retryWasScheduled)
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertEqual(failing.stopCount, 1)
        XCTAssertFalse(track.isEnabled)
        let startFailedPhase = await harness.snapshot().phase
        XCTAssertEqual(
            startFailedPhase,
            .startFailed
        )

        await retryGate.open()
        await drive.value
        let final = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertEqual(ready.startCount, 1)
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(final.phase, .forwardingHealthy)
        XCTAssertTrue(final.exactTrackAdmitted)
        XCTAssertEqual(final.monitorEpoch, epoch)
        XCTAssertEqual(final.deviceGeneration, 2)
        XCTAssertEqual(final.deviceUID, "com.elamin.opensteamer.virtual-microphone.input")
        XCTAssertEqual(final.sinkDeviceUID, "com.elamin.opensteamer.virtual-microphone.writer")
        XCTAssertEqual(
            final.currentKey?.deviceGeneration,
            2
        )
        XCTAssertEqual(
            final.currentKey?.transportAuthorizationEpoch,
            1
        )
        XCTAssertEqual(
            factory.requestedUIDs,
            ["com.elamin.opensteamer.virtual-microphone.writer", "com.elamin.opensteamer.virtual-microphone.writer"]
        )

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        XCTAssertEqual(
            factory.requestCount,
            2,
            "A duplicate monitor snapshot must not create another attempt."
        )
    }

    func testSharedClockStartupFailureDoesNotRetryExactKey()
        async {
        let rejection = capturedSharedClockRejection()
        let failureProbe = DriverSharedClockFailureProbe()
        let failing = DriverTestOutput(
            startError:
                BlackHoleMicrophoneOutputError
                    .sharedClockUnsafe(rejection)
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [failing, replacement]
        )
        let harness = DriverTestHarness(
            factory: factory,
            sharedClockFailureHandler: { key, rejection in
                failureProbe.record(
                    key: key,
                    rejection: rejection
                )
            }
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )

        let terminal = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertEqual(failing.startCount, 1)
        XCTAssertEqual(failing.stopCount, 1)
        XCTAssertFalse(track.isEnabled)
        XCTAssertEqual(terminal.phase, .sharedClockUnsafe)
        XCTAssertEqual(
            terminal.lastFailureCategory,
            .sharedClockUnsafe
        )
        XCTAssertEqual(
            failureProbe.entries,
            [
                .init(
                    key: WorldwideIPhoneMicrophoneForwardingKey(
                        monitorEpoch: epoch,
                        deviceGeneration: 1,
                        peerGeneration: 1,
                        transportAuthorizationEpoch: 1,
                        trackGeneration: 1
                    ),
                    rejection: rejection
                ),
            ],
            "The service callback must receive the exact rejected attempt key and captured clock evidence."
        )

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        XCTAssertEqual(
            factory.requestCount,
            1,
            "A deterministic shared-clock rejection must not enter the same-key retry loop."
        )

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertTrue(track.isEnabled)
        let recovered = await harness.snapshot()
        XCTAssertEqual(recovered.phase, .forwardingHealthy)
        XCTAssertEqual(recovered.currentKey?.deviceGeneration, 2)
    }

    func testFormatStartupFailureReachesHandlerAndDoesNotRetryExactKey()
        async {
        let rejection =
            BlackHoleMicrophoneOutputFormatRejection
                .unexpectedDeviceChannelCount(actual: 4)
        let failureProbe = DriverFormatFailureProbe()
        let failing = DriverTestOutput(
            startError:
                BlackHoleMicrophoneOutputError
                    .formatUnsafe(rejection)
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [failing, replacement]
        )
        let harness = DriverTestHarness(
            factory: factory,
            formatFailureHandler: { key, rejection in
                failureProbe.record(
                    key: key,
                    rejection: rejection
                )
            }
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )

        let terminal = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertEqual(failing.startCount, 1)
        XCTAssertEqual(failing.stopCount, 1)
        XCTAssertFalse(track.isEnabled)
        XCTAssertEqual(terminal.phase, .formatUnsafe)
        XCTAssertEqual(
            terminal.lastFailureCategory,
            .formatUnsafe
        )
        XCTAssertEqual(
            failureProbe.entries,
            [
                .init(
                    key: WorldwideIPhoneMicrophoneForwardingKey(
                        monitorEpoch: epoch,
                        deviceGeneration: 1,
                        peerGeneration: 1,
                        transportAuthorizationEpoch: 1,
                        trackGeneration: 1
                    ),
                    rejection: rejection
                ),
            ],
            "The service callback must receive the exact rejected key and format/readback evidence."
        )

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        XCTAssertEqual(
            factory.requestCount,
            1,
            "A deterministic format rejection must not retry the exact key."
        )

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertTrue(track.isEnabled)
        let recovered = await harness.snapshot()
        XCTAssertEqual(recovered.phase, .forwardingHealthy)
        XCTAssertEqual(recovered.currentKey?.deviceGeneration, 2)
    }

    func testStartFailureRetryBudgetIsBoundedPerGeneration()
        async {
        let failures = (0..<3).map { _ in
            DriverTestOutput(startError: DriverTestError.start)
        }
        let ready = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: failures + [ready]
        )
        let harness = DriverTestHarness(factory: factory)
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 3)
        XCTAssertFalse(track.isEnabled)
        let exhaustedPhase = await harness.snapshot().phase
        XCTAssertEqual(
            exhaustedPhase,
            .startFailed
        )

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 3)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 4)
        XCTAssertTrue(track.isEnabled)
        let recoveredPhase = await harness.snapshot().phase
        XCTAssertEqual(
            recoveredPhase,
            .forwardingHealthy
        )
    }

    func testDeviceGenerationChangeDuringRetryDelayUsesOnlyLatestKey()
        async {
        let retryGate = DriverSuspensionGate()
        let failing = DriverTestOutput(
            startError: DriverTestError.start
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [failing, replacement]
        )
        let harness = DriverTestHarness(
            factory: factory,
            retryGate: retryGate
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        let firstSnapshot = snapshot(
            epoch: epoch,
            generation: 1,
            available: true
        )
        let firstDrive = Task {
            await harness.updateDevice(firstSnapshot)
        }
        let retryWasSuspended = await eventually {
            await retryGate.hasEntered()
        }
        XCTAssertTrue(retryWasSuspended)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        await retryGate.open()
        await firstDrive.value

        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertEqual(failing.stopCount, 1)
        XCTAssertEqual(replacement.stopCount, 0)
        XCTAssertTrue(track.isEnabled)
        let result = await harness.snapshot()
        XCTAssertEqual(
            result.currentKey?.deviceGeneration,
            2
        )
        XCTAssertEqual(result.phase, .forwardingHealthy)
    }

    func testOutputUnavailableExhaustsBoundedRetriesUntilNewDeviceGeneration()
        async {
        let factory = DriverTestOutputFactory(outputs: [])
        let harness = DriverTestHarness(factory: factory)
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )

        XCTAssertEqual(factory.requestCount, 3)
        XCTAssertEqual(
            factory.requestedUIDs,
            [
                "com.elamin.opensteamer.virtual-microphone.writer",
                "com.elamin.opensteamer.virtual-microphone.writer",
                "com.elamin.opensteamer.virtual-microphone.writer",
            ]
        )
        let outputUnavailablePhase = await harness.snapshot().phase
        XCTAssertEqual(
            outputUnavailablePhase,
            .outputUnavailable
        )
        XCTAssertFalse(track.isEnabled)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 3)

        let ready = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        factory.append(ready)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )

        XCTAssertEqual(factory.requestCount, 4)
        let forwardingHealthyPhase = await harness.snapshot().phase
        XCTAssertEqual(
            forwardingHealthyPhase,
            .forwardingHealthy
        )
        XCTAssertTrue(track.isEnabled)
    }

    func testInitialMonitorSnapshotBeforePeerAndTrackIsRetained()
        async {
        let output = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(outputs: [output])
        let harness = DriverTestHarness(factory: factory)
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await harness.beginMonitoring(epoch)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 0)

        await harness.replacePeer(peer, generation: 1)
        await harness.installTrack(track)
        await harness.authorize(peer: peer, generation: 1)

        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertTrue(track.isEnabled)
        let result = await harness.snapshot()
        XCTAssertEqual(result.deviceGeneration, 1)
        XCTAssertEqual(result.phase, .forwardingHealthy)
    }

    func testNewDeviceGenerationDuringSuspendedStartRedrivesOnlyLatest()
        async {
        let startGate = DriverSuspensionGate()
        let stale = DriverTestOutput(
            startGate: startGate,
            progressSnapshots: readyProgressSnapshots()
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [stale, replacement]
        )
        let harness = DriverTestHarness(factory: factory)
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)

        let firstSnapshot = snapshot(
            epoch: epoch,
            generation: 1,
            available: true
        )
        let firstDrive = Task {
            await harness.updateDevice(firstSnapshot)
        }
        let startWasEntered = await eventually {
            stale.startWasEntered
        }
        XCTAssertTrue(startWasEntered)
        let suspended = await harness.snapshot()
        XCTAssertEqual(
            suspended.lastAttemptedKey?.deviceGeneration,
            1
        )
        XCTAssertNotNil(suspended.currentAttemptID)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        await startGate.open()
        await firstDrive.value

        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertGreaterThanOrEqual(stale.stopCount, 1)
        XCTAssertEqual(replacement.startCount, 1)
        XCTAssertTrue(track.isEnabled)
        let currentDeviceGeneration = await harness.snapshot().currentKey?.deviceGeneration
        XCTAssertEqual(
            currentDeviceGeneration,
            2
        )
    }

    func testNewDeviceGenerationDuringSuspendedAdmissionRedrivesLatest()
        async {
        let admissionGate = DriverSuspensionGate()
        let peer = DriverTestPeer(
            admissionGate: admissionGate
        )
        let stale = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [stale, replacement]
        )
        let harness = DriverTestHarness(factory: factory)
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)

        let firstSnapshot = snapshot(
            epoch: epoch,
            generation: 1,
            available: true
        )
        let firstDrive = Task {
            await harness.updateDevice(firstSnapshot)
        }
        let admissionWasSuspended = await eventually {
            let gateHasEntered = await admissionGate.hasEntered()
            return peer.admissionCount == 1 && gateHasEntered
        }
        XCTAssertTrue(admissionWasSuspended)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        await admissionGate.open()
        await firstDrive.value

        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertGreaterThanOrEqual(stale.stopCount, 1)
        XCTAssertEqual(replacement.stopCount, 0)
        XCTAssertEqual(peer.admissionCount, 2)
        XCTAssertTrue(track.isEnabled)
        let forwardingHealthyPhase = await harness.snapshot().phase
        XCTAssertEqual(
            forwardingHealthyPhase,
            .forwardingHealthy
        )
    }

    func testNewDeviceGenerationDuringSuspendedReadinessRedrivesLatest()
        async {
        let readinessGate = DriverSuspensionGate()
        let stale = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [stale, replacement]
        )
        let harness = DriverTestHarness(
            factory: factory,
            readinessGate: readinessGate
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)

        let firstSnapshot = snapshot(
            epoch: epoch,
            generation: 1,
            available: true
        )
        let firstDrive = Task {
            await harness.updateDevice(firstSnapshot)
        }
        let readinessWasSuspended = await eventually {
            await readinessGate.hasEntered()
        }
        XCTAssertTrue(readinessWasSuspended)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        await readinessGate.open()
        await firstDrive.value

        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertGreaterThanOrEqual(stale.stopCount, 1)
        XCTAssertEqual(replacement.stopCount, 0)
        XCTAssertTrue(track.isEnabled)
        let currentDeviceGeneration = await harness.snapshot().currentKey?.deviceGeneration
        XCTAssertEqual(
            currentDeviceGeneration,
            2
        )
    }

    func testLatestDeviceWhileTransportUnhealthyIsConsumedByOneFreshAuthorization()
        async {
        let first = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let second = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [first, second]
        )
        let harness = DriverTestHarness(factory: factory)
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 0)
        let waitingForTransportPhase = await harness.snapshot().phase
        XCTAssertEqual(
            waitingForTransportPhase,
            .waitingForTransport
        )

        await harness.authorize(peer: peer, generation: 1)
        XCTAssertEqual(factory.requestCount, 1)
        let firstAuthorizationEpoch = await harness.snapshot().transportAuthorizationEpoch
        XCTAssertEqual(
            firstAuthorizationEpoch,
            1
        )

        await harness.invalidateTransport()
        XCTAssertFalse(track.isEnabled)
        XCTAssertGreaterThanOrEqual(first.stopCount, 1)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 1)

        await harness.authorize(peer: peer, generation: 1)
        XCTAssertEqual(factory.requestCount, 2)
        let secondAuthorizationEpoch = await harness.snapshot().transportAuthorizationEpoch
        XCTAssertEqual(
            secondAuthorizationEpoch,
            2
        )
        XCTAssertTrue(track.isEnabled)

        await harness.authorize(peer: peer, generation: 1)
        XCTAssertEqual(factory.requestCount, 2)
        let duplicateAuthorizationEpoch = await harness.snapshot().transportAuthorizationEpoch
        XCTAssertEqual(
            duplicateAuthorizationEpoch,
            2,
            "Duplicate healthy callbacks must not mint another authorization epoch."
        )
    }

    func testRemovalReinstallAndStaleRuntimeFailureAffectOnlyExactOutput()
        async {
        let first = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let second = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let runtimeReplacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [first, second, runtimeReplacement]
        )
        let harness = DriverTestHarness(factory: factory)
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        let originalTrackGeneration =
            await harness.snapshot().trackGeneration
        XCTAssertTrue(track.isEnabled)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: false
            )
        )
        let removed = await harness.snapshot()
        XCTAssertFalse(track.isEnabled)
        XCTAssertNil(removed.currentKey)
        XCTAssertEqual(
            removed.trackGeneration,
            originalTrackGeneration,
            "Device disappearance preserves the current remote track generation."
        )
        XCTAssertGreaterThanOrEqual(first.stopCount, 1)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 3,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(second.stopCount, 0)

        let staleRuntimeFailureHandled = await harness.handleRuntimeFailure(
            first,
            category: .runtimeProgressStalled
        )
        XCTAssertFalse(
            staleRuntimeFailureHandled
        )
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(second.stopCount, 0)
        let forwardingHealthyPhase = await harness.snapshot().phase
        XCTAssertEqual(
            forwardingHealthyPhase,
            .forwardingHealthy
        )

        let activeRuntimeFailureHandled = await harness.handleRuntimeFailure(second)
        XCTAssertTrue(
            activeRuntimeFailureHandled
        )
        XCTAssertEqual(second.stopCount, 1)
        XCTAssertEqual(factory.requestCount, 3)
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(runtimeReplacement.stopCount, 0)
        let recoveredPhase = await harness.snapshot().phase
        XCTAssertEqual(
            recoveredPhase,
            .forwardingHealthy
        )
        let repeatedRuntimeFailureHandled = await harness.handleRuntimeFailure(second)
        XCTAssertFalse(
            repeatedRuntimeFailureHandled
        )
        XCTAssertEqual(second.stopCount, 1)
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(runtimeReplacement.stopCount, 0)
    }

    func testProgressStallRuntimeFailureUsesBoundedRetryBudget()
        async {
        let first = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let second = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let third = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [first, second, third]
        )
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 3
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )

        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertTrue(track.isEnabled)

        let firstHandled = await harness.handleRuntimeFailure(
            first,
            category: .runtimeProgressStalled
        )
        XCTAssertTrue(firstHandled)
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertTrue(track.isEnabled)

        let secondHandled = await harness.handleRuntimeFailure(
            second,
            category: .runtimeProgressStalled
        )
        XCTAssertTrue(secondHandled)
        XCTAssertEqual(factory.requestCount, 3)
        XCTAssertTrue(track.isEnabled)

        let thirdHandled = await harness.handleRuntimeFailure(
            third,
            category: .runtimeProgressStalled
        )
        XCTAssertTrue(thirdHandled)
        let terminal = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 3)
        XCTAssertFalse(track.isEnabled)
        XCTAssertEqual(terminal.phase, .runtimeFailed)
        XCTAssertEqual(
            terminal.lastFailureCategory,
            .runtimeProgressStalled
        )

        let repeated = await harness.handleRuntimeFailure(
            third,
            category: .runtimeProgressStalled
        )
        XCTAssertFalse(repeated)
        XCTAssertEqual(factory.requestCount, 3)
    }

    func testSharedClockRuntimeFailureDoesNotRetryExactKey()
        async {
        let active = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [active, replacement]
        )
        let harness = DriverTestHarness(factory: factory)
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertTrue(track.isEnabled)

        let handled = await harness.handleRuntimeFailure(
            active,
            category: .sharedClockUnsafe
        )
        XCTAssertTrue(handled)
        let terminal = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertEqual(active.stopCount, 1)
        XCTAssertFalse(track.isEnabled)
        XCTAssertEqual(terminal.phase, .sharedClockUnsafe)
        XCTAssertEqual(
            terminal.lastFailureCategory,
            .sharedClockUnsafe
        )

        await harness.invalidateTransport(
            preservingSharedClockUnsafeFailure: true
        )
        let routeRevoked = await harness.snapshot()
        XCTAssertFalse(routeRevoked.transportAuthorized)
        XCTAssertEqual(routeRevoked.phase, .sharedClockUnsafe)
        XCTAssertEqual(
            routeRevoked.lastFailureCategory,
            .sharedClockUnsafe
        )

        let replacementTrack = DriverTestTrack()
        await harness.installTrack(replacementTrack)
        let afterTrackChurn = await harness.snapshot()
        XCTAssertEqual(afterTrackChurn.trackGeneration, 2)
        XCTAssertEqual(afterTrackChurn.phase, .sharedClockUnsafe)
        XCTAssertEqual(factory.requestCount, 1)

        await harness.authorize(peer: peer, generation: 1)
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertTrue(replacementTrack.isEnabled)
        let recovered = await harness.snapshot()
        XCTAssertEqual(recovered.deviceGeneration, 1)
        XCTAssertEqual(
            recovered.currentKey?.transportAuthorizationEpoch,
            2,
            "Recovery must mint a new transport key without pretending the endpoint pair changed."
        )

        await harness.invalidateTransport()
        let invalidatedAfterRecovery = await harness.snapshot()
        XCTAssertEqual(
            invalidatedAfterRecovery.phase,
            .waitingForTransport,
            "A replacement that passed startup clock proof must clear the stale shared-clock presentation fence."
        )
    }

    func testRuntimeFailureTreatsDisposeReturnAsTerminalBeforeReplacementQueueCreation()
        async throws {
        let disposalFailure = OSStatus(-66_701)
        let operations =
            DistinctRuntimeAudioQueueOperations(
                disposeStatuses: [
                    disposalFailure,
                    noErr,
                ]
            )
        let factory =
            RuntimeDisposalOutputFactory(
                operations: operations
            )
        let harness =
            RuntimeDisposalDriverHarness(
                factory: factory,
                operations: operations
            )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await harness.beginMonitoring(epoch)
        await harness.replacePeer(
            peer,
            generation: 1
        )
        await harness.installTrack(track)
        await harness.authorize(
            peer: peer,
            generation: 1
        )
        await harness.updateDevice(
            BlackHoleDeviceAvailabilitySnapshot(
                monitorEpoch: epoch,
                deviceGeneration: 1,
                defaultInputEndpoint: .init(
                    deviceID: 79,
                    deviceUID: "com.elamin.opensteamer.virtual-microphone.input"
                ),
                hiddenMirrorSinkEndpoint: .init(
                    deviceID: 89,
                    deviceUID: "com.elamin.opensteamer.virtual-microphone.writer"
                )
            )
        )

        let original = try XCTUnwrap(
            factory.output(at: 0)
        )
        XCTAssertEqual(
            operations.createdQueueIdentities.count,
            1
        )

        let runtimeFailureHandled =
            await harness.handleRuntimeFailure(
                original
            )
        XCTAssertTrue(runtimeFailureHandled)

        let queueIdentities =
            operations.createdQueueIdentities
        XCTAssertEqual(
            queueIdentities.count,
            2,
            "Only the original queue and one replacement queue may be created."
        )
        XCTAssertNotEqual(
            queueIdentities[0],
            queueIdentities[1],
            "The integration fake must expose distinct old/new AudioQueue identities."
        )
        let events = operations.events
        let oldDisposeReturned =
            try XCTUnwrap(
                events.firstIndex(
                    of:
                        "dispose:\(queueIdentities[0]):\(disposalFailure)"
                )
            )
        let replacementCreated =
            try XCTUnwrap(
                events.firstIndex(
                    of:
                        "create:\(queueIdentities[1])"
                )
            )
        XCTAssertLessThan(
            oldDisposeReturned,
            replacementCreated,
            "The old exact queue/context must finish its one terminal AudioQueueDispose call before replacement queue creation."
        )

        let snapshot = await harness.snapshot()
        XCTAssertEqual(
            snapshot.phase,
            .forwardingHealthy
        )
        XCTAssertTrue(track.isEnabled)

        await harness.shutdown()
        XCTAssertEqual(
            operations.activeAllocationCount,
            0
        )
    }

    func testAdmissionFailureDisablesExactTrackAndRetiresOutput()
        async {
        let peer = DriverTestPeer(healthy: false)
        let output = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(outputs: [output])
        let harness = DriverTestHarness(factory: factory)
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )

        XCTAssertFalse(track.isEnabled)
        XCTAssertEqual(output.stopCount, 1)
        let result = await harness.snapshot()
        XCTAssertEqual(result.phase, .admissionFailed)
        XCTAssertEqual(
            result.lastFailureCategory,
            .admissionFailed
        )
    }

    func testFrozenRTPWithSuccessfulZeroFilledPullsRetiresOnlyExactAttempt()
        async {
        var frozenSourceProgress:
            [BlackHoleMicrophoneOutputProgressSnapshot] = []
        for index in 1...12 {
            let count = UInt64(index)
            let frames = count * 480
            frozenSourceProgress.append(
                progress(
                    callbacks: count,
                    requestedFrames: frames,
                    successfulPulls: count,
                    successfulFrames: frames,
                    silenceFallbacks: 0,
                    silenceFrames: 0
                )
            )
        }
        let first = DriverTestOutput(
            progressSnapshots: frozenSourceProgress
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [first, replacement]
        )
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 2,
            maximumStaleInboundMediaSamples: 3,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        let firstAttemptID = await harness.snapshot().currentAttemptID
        XCTAssertNotNil(firstAttemptID)

        await harness.publishInboundMedia(
            packets: 38_626,
            bytes: 2_634_060,
            jitterBufferEmittedCount: 20_000,
            totalSamplesReceived: 36_698_880
        )
        await harness.publishInboundMedia(
            packets: 38_627,
            bytes: 2_634_128,
            jitterBufferEmittedCount: 20_001,
            totalSamplesReceived: 36_699_360
        )
        let initiallyHealthy = await harness.snapshot()
        XCTAssertEqual(initiallyHealthy.phase, .forwardingHealthy)

        for _ in 0..<3 {
            await harness.publishInboundMedia(
                packets: 38_627,
                bytes: 2_634_128,
                jitterBufferEmittedCount: 20_001,
                totalSamplesReceived: 36_699_360
            )
        }

        let retried = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(replacement.stopCount, 0)
        XCTAssertNotEqual(retried.currentAttemptID, firstAttemptID)
        XCTAssertEqual(retried.lastFailureCategory, .sourceMediaStalled)
        XCTAssertEqual(retried.phase, .awaitingFrames)
        XCTAssertEqual(retried.inboundMediaAdvancementCount, 0)
        XCTAssertTrue(track.isEnabled)
    }

    func testQuietButAdvancingRTPIsHealthyWithoutAmplitudeOrEnergyEvidence()
        async {
        let output = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(outputs: [output])
        let harness = DriverTestHarness(
            factory: factory,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        await harness.publishInboundMedia(
            packets: 100,
            bytes: 8_000,
            jitterBufferEmittedCount: 50,
            totalSamplesReceived: 48_000
        )
        await harness.publishInboundMedia(
            packets: 101,
            bytes: 8_080
        )

        let healthy = await harness.snapshot()
        XCTAssertEqual(healthy.phase, .forwardingHealthy)
        XCTAssertTrue(healthy.inboundMediaFresh)
        XCTAssertEqual(healthy.inboundMediaAdvancementCount, 1)
        XCTAssertEqual(healthy.consecutiveStaleInboundMediaSamples, 0)
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(output.stopCount, 0)
    }

    func testHealthyMediaExpiresWhenStatisticsStopCompletely()
        async {
        let watchdog = DriverTestMediaFreshnessWatchdog(now: 10)
        let output = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(outputs: [output])
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 1,
            mediaFreshnessTimeoutNanoseconds: 100,
            mediaFreshnessWatchdog: watchdog,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        await harness.publishInboundMedia(
            packets: 700,
            bytes: 56_000
        )
        await harness.publishInboundMedia(
            packets: 701,
            bytes: 56_080
        )

        let healthy = await harness.snapshot()
        XCTAssertEqual(healthy.phase, .forwardingHealthy)
        let deadlineWasScheduled = await eventually {
            watchdog.scheduleCount == 1
        }
        XCTAssertTrue(deadlineWasScheduled)

        // No further statistics sample is delivered. Freshness must expire
        // synchronously from monotonic time even before the scheduled wake-up
        // is delivered, and that wake-up must then retire the exact attempt.
        watchdog.setNowWithoutDelivering(to: 110)
        let pastDeadline = await harness.snapshot()
        XCTAssertEqual(pastDeadline.phase, .awaitingFrames)
        XCTAssertFalse(pastDeadline.inboundMediaFresh)
        XCTAssertNotNil(pastDeadline.currentAttemptID)
        watchdog.deliverDueDeadlines()
        let didExpire = await eventually {
            await harness.snapshot().phase == .sourceMediaStalled
        }
        XCTAssertTrue(didExpire)
        let expired = await harness.snapshot()
        XCTAssertNil(expired.currentAttemptID)
        XCTAssertFalse(expired.inboundMediaFresh)
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertEqual(output.stopCount, 1)
        XCTAssertFalse(track.isEnabled)
    }

    func testRecoveryDeadlinesExhaustBudgetWhenStatisticsStayStopped()
        async {
        let watchdog = DriverTestMediaFreshnessWatchdog()
        let outputs = (0..<3).map { _ in
            DriverTestOutput(
                progressSnapshots: readyProgressSnapshots()
            )
        }
        let factory = DriverTestOutputFactory(outputs: outputs)
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 3,
            mediaFreshnessTimeoutNanoseconds: 100,
            mediaFreshnessWatchdog: watchdog,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        await harness.publishInboundMedia(packets: 750, bytes: 60_000)
        await harness.publishInboundMedia(packets: 751, bytes: 60_080)

        let firstDeadlineReady = await eventually {
            watchdog.scheduleCount >= 1
        }
        XCTAssertTrue(firstDeadlineReady)

        for (deadline, expectedAttemptCount) in [
            (UInt64(100), 2),
            (UInt64(200), 3),
        ] {
            watchdog.advance(to: deadline)
            let replacementReady = await eventually {
                factory.requestCount == expectedAttemptCount
                    && watchdog.scheduleCount >= expectedAttemptCount
            }
            XCTAssertTrue(replacementReady)
        }

        watchdog.advance(to: 300)
        let exhausted = await eventually {
            let snapshot = await harness.snapshot()
            return snapshot.phase == .sourceMediaStalled
                && snapshot.currentAttemptID == nil
        }
        XCTAssertTrue(exhausted)
        XCTAssertEqual(factory.requestCount, 3)
        XCTAssertEqual(outputs.map(\.stopCount), [1, 1, 1])
        XCTAssertFalse(track.isEnabled)
    }

    func testFrozenRTPWithAdvancingConcealmentCountersExhaustsRetryBudget()
        async {
        let watchdog = DriverTestMediaFreshnessWatchdog()
        let outputs = (0..<3).map { _ in
            DriverTestOutput(
                progressSnapshots: readyProgressSnapshots()
            )
        }
        let factory = DriverTestOutputFactory(outputs: outputs)
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 3,
            maximumStaleInboundMediaSamples: 1,
            mediaFreshnessTimeoutNanoseconds: 1_000,
            mediaFreshnessWatchdog: watchdog,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        await harness.publishInboundMedia(
            packets: 800,
            bytes: 64_000,
            jitterBufferEmittedCount: 400,
            totalSamplesReceived: 384_000
        )
        await harness.publishInboundMedia(
            packets: 801,
            bytes: 64_080,
            jitterBufferEmittedCount: 401,
            totalSamplesReceived: 384_480
        )
        let healthy = await harness.snapshot()
        XCTAssertEqual(healthy.phase, .forwardingHealthy)

        for increment in UInt64(1)...UInt64(3) {
            await harness.publishInboundMedia(
                packets: 801,
                bytes: 64_080,
                jitterBufferEmittedCount: 401 + increment,
                totalSamplesReceived: 384_480 + increment * 480
            )
        }

        let exhausted = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 3)
        XCTAssertNil(exhausted.currentAttemptID)
        XCTAssertEqual(exhausted.phase, .sourceMediaStalled)
        XCTAssertEqual(
            exhausted.lastFailureCategory,
            .sourceMediaStalled
        )
        XCTAssertFalse(exhausted.inboundMediaFresh)
        XCTAssertFalse(track.isEnabled)
        XCTAssertEqual(outputs.map(\.stopCount), [1, 1, 1])
        watchdog.advance(to: UInt64.max)
    }

    func testCancelledAttemptDeadlineCannotRetireHealthyReplacement()
        async {
        let watchdog = DriverTestMediaFreshnessWatchdog()
        let first = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [first, replacement]
        )
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 2,
            mediaFreshnessTimeoutNanoseconds: 100,
            mediaFreshnessWatchdog: watchdog,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        await harness.publishInboundMedia(packets: 900, bytes: 72_000)
        await harness.publishInboundMedia(packets: 901, bytes: 72_080)
        let firstAttemptID = await harness.snapshot().currentAttemptID
        XCTAssertNotNil(firstAttemptID)

        let failureWasHandled =
            await harness.handleRuntimeFailure(first)
        XCTAssertTrue(failureWasHandled)
        watchdog.advance(to: 50)
        await harness.publishInboundMedia(packets: 902, bytes: 72_160)
        let healthyReplacement = await harness.snapshot()
        XCTAssertNotEqual(
            healthyReplacement.currentAttemptID,
            firstAttemptID
        )
        XCTAssertEqual(healthyReplacement.phase, .forwardingHealthy)

        // This releases the old attempt's deadline but not the replacement's
        // refreshed deadline at 150. Exact attempt and watchdog-generation
        // fences must make the old wake-up inert.
        watchdog.advance(to: 100)
        try? await Task.sleep(for: .milliseconds(10))
        let afterStaleWake = await harness.snapshot()
        XCTAssertEqual(
            afterStaleWake.currentAttemptID,
            healthyReplacement.currentAttemptID
        )
        XCTAssertEqual(afterStaleWake.phase, .forwardingHealthy)
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(replacement.stopCount, 0)
        watchdog.advance(to: UInt64.max)
    }

    func testStaleSamplesBeforeFirstInboundAdvanceRedriveTheReceiver()
        async {
        let first = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let replacement = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [first, replacement]
        )
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 2,
            maximumStaleInboundMediaSamples: 2,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        let firstAttemptID = await harness.snapshot().currentAttemptID

        for _ in 0..<2 {
            await harness.publishInboundMedia(
                packets: 400,
                bytes: 32_000
            )
        }

        let redriven = await harness.snapshot()
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertNotEqual(redriven.currentAttemptID, firstAttemptID)
        XCTAssertEqual(redriven.phase, .awaitingFrames)
        XCTAssertEqual(redriven.inboundMediaAdvancementCount, 0)
        XCTAssertEqual(redriven.consecutiveStaleInboundMediaSamples, 0)
        XCTAssertFalse(redriven.inboundMediaFresh)
        XCTAssertEqual(redriven.lastFailureCategory, .sourceMediaStalled)
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(replacement.stopCount, 0)
    }

    func testFirstInboundMediaDeadlineExhaustsWhenNoStatisticsEverArrive()
        async {
        let watchdog = DriverTestMediaFreshnessWatchdog()
        let outputs = (0..<3).map { _ in
            DriverTestOutput(
                progressSnapshots: readyProgressSnapshots()
            )
        }
        let factory = DriverTestOutputFactory(outputs: outputs)
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 3,
            mediaFreshnessTimeoutNanoseconds: 100,
            mediaFreshnessWatchdog: watchdog,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )

        let firstDeadlineReady = await eventually {
            watchdog.scheduleCount >= 1
        }
        XCTAssertTrue(firstDeadlineReady)

        for (deadline, expectedAttemptCount) in [
            (UInt64(100), 2),
            (UInt64(200), 3),
        ] {
            watchdog.advance(to: deadline)
            let replacementReady = await eventually {
                factory.requestCount == expectedAttemptCount
                    && watchdog.scheduleCount >= expectedAttemptCount
            }
            XCTAssertTrue(replacementReady)
        }

        watchdog.advance(to: 300)
        let exhausted = await eventually {
            let snapshot = await harness.snapshot()
            return snapshot.phase == .sourceMediaStalled
                && snapshot.currentAttemptID == nil
        }
        XCTAssertTrue(exhausted)
        XCTAssertEqual(factory.requestCount, 3)
        XCTAssertEqual(outputs.map(\.stopCount), [1, 1, 1])
        XCTAssertFalse(track.isEnabled)
    }

    func testFreshInboundMediaRevivesAnExhaustedSourceWithoutAReconnect()
        async {
        let watchdog = DriverTestMediaFreshnessWatchdog()
        let outputs = (0..<4).map { _ in
            DriverTestOutput(
                progressSnapshots: readyProgressSnapshots()
            )
        }
        let factory = DriverTestOutputFactory(outputs: outputs)
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 3,
            mediaFreshnessTimeoutNanoseconds: 100,
            mediaFreshnessWatchdog: watchdog,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )

        let firstDeadlineReady = await eventually {
            watchdog.scheduleCount >= 1
        }
        XCTAssertTrue(firstDeadlineReady)

        for (deadline, expectedAttemptCount) in [
            (UInt64(100), 2),
            (UInt64(200), 3),
        ] {
            watchdog.advance(to: deadline)
            let replacementReady = await eventually {
                factory.requestCount == expectedAttemptCount
                    && watchdog.scheduleCount
                        >= expectedAttemptCount
            }
            XCTAssertTrue(replacementReady)
        }

        watchdog.advance(to: 300)
        let exhausted = await eventually {
            let snapshot = await harness.snapshot()
            return snapshot.phase == .sourceMediaStalled
                && snapshot.currentAttemptID == nil
        }
        XCTAssertTrue(exhausted)
        XCTAssertFalse(track.isEnabled)

        await harness.publishInboundMedia(
            packets: 10,
            bytes: 800
        )
        XCTAssertEqual(factory.requestCount, 3)
        await harness.publishInboundMedia(
            packets: 11,
            bytes: 880
        )

        let revived = await eventually {
            let snapshot = await harness.snapshot()
            return factory.requestCount == 4
                && snapshot.currentAttemptID != nil
                && snapshot.exactTrackAdmitted
        }
        XCTAssertTrue(revived)
        XCTAssertTrue(track.isEnabled)
        XCTAssertEqual(
            outputs[0..<3].map(\.stopCount),
            [1, 1, 1]
        )
        XCTAssertEqual(outputs[3].stopCount, 0)

        await harness.publishInboundMedia(
            packets: 12,
            bytes: 960
        )
        let healthy = await harness.snapshot()
        XCTAssertEqual(healthy.phase, .forwardingHealthy)
        XCTAssertEqual(healthy.inboundMediaAdvancementCount, 1)
        XCTAssertTrue(healthy.inboundMediaFresh)
    }

    func testAttemptGenerationDistinguishesSameKeyRestallAfterFreshMediaRevival()
        async throws {
        let watchdog = DriverTestMediaFreshnessWatchdog()
        let outputs = (0..<2).map { _ in
            DriverTestOutput(
                progressSnapshots: readyProgressSnapshots()
            )
        }
        let factory = DriverTestOutputFactory(outputs: outputs)
        let harness = DriverTestHarness(
            factory: factory,
            maximumAttemptCountPerKey: 1,
            mediaFreshnessTimeoutNanoseconds: 100,
            mediaFreshnessWatchdog: watchdog,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )

        let firstDeadlineReady = await eventually {
            watchdog.scheduleCount >= 1
        }
        XCTAssertTrue(firstDeadlineReady)
        await harness.publishInboundMedia(
            packets: 10,
            bytes: 800
        )
        await harness.publishInboundMedia(
            packets: 11,
            bytes: 880
        )
        let initiallyHealthy = await harness.snapshot()
        XCTAssertEqual(initiallyHealthy.phase, .forwardingHealthy)

        watchdog.advance(to: 100)
        let firstQuiescentReady = await eventually {
            let snapshot = await harness.snapshot()
            return snapshot.phase == .sourceMediaStalled
                && snapshot.currentAttemptID == nil
        }
        XCTAssertTrue(firstQuiescentReady)
        let firstQuiescent = await harness.snapshot()
        let forwardingKey = try XCTUnwrap(
            firstQuiescent.lastAttemptedKey
        )
        let firstAttemptID = try XCTUnwrap(
            firstQuiescent.lastAttemptID
        )
        XCTAssertEqual(firstQuiescent.attemptGeneration, 1)
        XCTAssertNil(firstQuiescent.currentKey)
        XCTAssertEqual(firstQuiescent.progress, .zero)
        XCTAssertEqual(firstQuiescent.inboundMediaAdvancementCount, 0)
        XCTAssertEqual(firstQuiescent.consecutiveStaleInboundMediaSamples, 0)
        XCTAssertFalse(firstQuiescent.inboundMediaFresh)
        XCTAssertGreaterThan(firstQuiescent.inboundMediaSampleSequence, 0)

        await harness.publishInboundMedia(
            packets: 12,
            bytes: 960
        )
        let revived = await eventually {
            let snapshot = await harness.snapshot()
            return factory.requestCount == 2
                && snapshot.currentAttemptID != nil
                && snapshot.exactTrackAdmitted
        }
        XCTAssertTrue(revived)
        let revivedSnapshot = await harness.snapshot()
        XCTAssertEqual(revivedSnapshot.currentKey, forwardingKey)
        XCTAssertEqual(revivedSnapshot.lastAttemptedKey, forwardingKey)
        XCTAssertNotEqual(revivedSnapshot.lastAttemptID, firstAttemptID)
        XCTAssertEqual(revivedSnapshot.attemptGeneration, 2)

        await harness.publishInboundMedia(
            packets: 13,
            bytes: 1_040
        )
        let healthy = await harness.snapshot()
        XCTAssertEqual(healthy.phase, .forwardingHealthy)
        XCTAssertTrue(healthy.inboundMediaFresh)

        watchdog.advance(to: 200)
        let secondQuiescentReady = await eventually {
            let snapshot = await harness.snapshot()
            return snapshot.phase == .sourceMediaStalled
                && snapshot.currentAttemptID == nil
        }
        XCTAssertTrue(secondQuiescentReady)
        let secondQuiescent = await harness.snapshot()
        XCTAssertEqual(secondQuiescent.lastAttemptedKey, forwardingKey)
        XCTAssertEqual(
            secondQuiescent.monitorEpoch,
            firstQuiescent.monitorEpoch
        )
        XCTAssertEqual(
            secondQuiescent.deviceGeneration,
            firstQuiescent.deviceGeneration
        )
        XCTAssertEqual(
            secondQuiescent.peerGeneration,
            firstQuiescent.peerGeneration
        )
        XCTAssertEqual(
            secondQuiescent.transportAuthorizationEpoch,
            firstQuiescent.transportAuthorizationEpoch
        )
        XCTAssertEqual(
            secondQuiescent.trackGeneration,
            firstQuiescent.trackGeneration
        )
        XCTAssertNotEqual(secondQuiescent.lastAttemptID, firstAttemptID)
        XCTAssertEqual(
            secondQuiescent.attemptGeneration,
            firstQuiescent.attemptGeneration + 1
        )
        XCTAssertNil(secondQuiescent.currentKey)
        XCTAssertEqual(secondQuiescent.progress, .zero)
        XCTAssertEqual(secondQuiescent.inboundMediaAdvancementCount, 0)
        XCTAssertEqual(secondQuiescent.consecutiveStaleInboundMediaSamples, 0)
        XCTAssertFalse(secondQuiescent.inboundMediaFresh)
        XCTAssertGreaterThan(
            secondQuiescent.inboundMediaSampleSequence,
            firstQuiescent.inboundMediaSampleSequence
        )
        XCTAssertEqual(outputs.map(\.stopCount), [1, 1])
        XCTAssertFalse(track.isEnabled)

        let message = WorldwideScreenService
            .iPhoneMicrophoneForwardingLogMessage(secondQuiescent)
        XCTAssertTrue(message.contains("attemptGeneration=2 "))
        XCTAssertTrue(
            message.contains("lastAttemptedKeyMatchesSnapshot=true ")
        )
        XCTAssertFalse(message.contains("attemptID="))
        XCTAssertFalse(
            message.localizedCaseInsensitiveContains(
                firstAttemptID.uuidString
            )
        )
        if let secondAttemptID = secondQuiescent.lastAttemptID {
            XCTAssertFalse(
                message.localizedCaseInsensitiveContains(
                    secondAttemptID.uuidString
                )
            )
        }
    }

    func testAdvancingSilentQueueAwaitsDelayedFirstPCMWithoutRetiringAttempt()
        async {
        let silentOne = progress(
            callbacks: 1,
            requestedFrames: 480,
            successfulPulls: 0,
            successfulFrames: 0,
            silenceFallbacks: 1,
            silenceFrames: 480
        )
        let silentTwo = progress(
            callbacks: 2,
            requestedFrames: 960,
            successfulPulls: 0,
            successfulFrames: 0,
            silenceFallbacks: 2,
            silenceFrames: 960
        )
        let firstReady = progress(
            callbacks: 3,
            requestedFrames: 1_440,
            successfulPulls: 1,
            successfulFrames: 480,
            silenceFallbacks: 2,
            silenceFrames: 960
        )
        let continuingReady = progress(
            callbacks: 4,
            requestedFrames: 1_920,
            successfulPulls: 2,
            successfulFrames: 960,
            silenceFallbacks: 2,
            silenceFrames: 960
        )
        let output = DriverTestOutput(
            progressSnapshots: [
                silentOne,
                silentTwo,
                firstReady,
                firstReady,
                firstReady,
                continuingReady,
            ]
        )
        let factory = DriverTestOutputFactory(outputs: [output])
        let harness = DriverTestHarness(
            factory: factory,
            automaticallyAdvanceInboundMedia: false
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertEqual(output.stopCount, 0)
        XCTAssertTrue(track.isEnabled)

        await harness.publishInboundMedia(packets: 700, bytes: 56_000)
        await harness.publishInboundMedia(packets: 701, bytes: 56_080)

        let oneSinkWatermark = await harness.snapshot()
        XCTAssertEqual(oneSinkWatermark.phase, .forwardingReady)
        XCTAssertEqual(oneSinkWatermark.inboundMediaAdvancementCount, 1)
        XCTAssertFalse(oneSinkWatermark.inboundMediaFresh)
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertEqual(output.stopCount, 0)

        let endToEndHealthy = await harness.snapshot()
        XCTAssertEqual(endToEndHealthy.phase, .forwardingHealthy)
        XCTAssertTrue(endToEndHealthy.inboundMediaFresh)
        XCTAssertTrue(track.isEnabled)
    }

    func testStaleFreshnessCannotCrossAttemptOrPeerRollover()
        async {
        let first = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let second = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let third = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [first, second, third]
        )
        let harness = DriverTestHarness(
            factory: factory,
            automaticallyAdvanceInboundMedia: false
        )
        let firstPeer = DriverTestPeer()
        let firstTrack = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: firstPeer,
            track: firstTrack
        )
        await harness.authorize(peer: firstPeer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        await harness.publishInboundMedia(packets: 10, bytes: 800)
        await harness.publishInboundMedia(packets: 11, bytes: 880)
        let firstAttemptHealthy = await harness.snapshot()
        XCTAssertEqual(firstAttemptHealthy.phase, .forwardingHealthy)

        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 2,
                available: true
            )
        )
        let deviceRollover = await harness.snapshot()
        XCTAssertEqual(deviceRollover.phase, .awaitingFrames)
        XCTAssertEqual(deviceRollover.inboundMediaAdvancementCount, 0)
        await harness.publishInboundMedia(packets: 11, bytes: 880)
        let unchangedWatermark = await harness.snapshot()
        XCTAssertEqual(unchangedWatermark.phase, .awaitingFrames)
        await harness.publishInboundMedia(packets: 12, bytes: 960)
        let advancedWatermark = await harness.snapshot()
        XCTAssertEqual(advancedWatermark.phase, .forwardingHealthy)

        let secondPeer = DriverTestPeer()
        let secondTrack = DriverTestTrack()
        await harness.replacePeer(secondPeer, generation: 2)
        await harness.installTrack(secondTrack)
        await harness.authorize(peer: secondPeer, generation: 2)

        await harness.publishInboundMedia(
            packets: 13,
            bytes: 1_040,
            peer: firstPeer,
            generation: 1
        )
        let rejectedOldPeer = await harness.snapshot()
        XCTAssertEqual(rejectedOldPeer.phase, .awaitingFrames)
        XCTAssertEqual(rejectedOldPeer.inboundMediaAdvancementCount, 0)

        await harness.publishInboundMedia(
            packets: 500,
            bytes: 40_000,
            peer: secondPeer,
            generation: 2
        )
        let secondPeerBaseline = await harness.snapshot()
        XCTAssertEqual(secondPeerBaseline.phase, .awaitingFrames)
        await harness.publishInboundMedia(
            packets: 501,
            bytes: 40_080,
            peer: secondPeer,
            generation: 2
        )
        let healthySecondPeer = await harness.snapshot()
        XCTAssertEqual(healthySecondPeer.phase, .forwardingHealthy)
        XCTAssertTrue(healthySecondPeer.inboundMediaFresh)
        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(second.stopCount, 1)
        XCTAssertEqual(third.stopCount, 0)
    }

    func testTransientReadinessFailureRetriesSameGeneration()
        async {
        let notReady = DriverTestOutput(
            progressSnapshots: [.zero, .zero]
        )
        let ready = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(
            outputs: [notReady, ready]
        )
        let harness = DriverTestHarness(factory: factory)
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await prepare(
            harness: harness,
            epoch: epoch,
            peer: peer,
            track: track
        )
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )

        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertEqual(notReady.stopCount, 1)
        XCTAssertEqual(ready.stopCount, 0)
        XCTAssertTrue(track.isEnabled)
        let recoveredPhase = await harness.snapshot().phase
        XCTAssertEqual(
            recoveredPhase,
            .forwardingHealthy
        )
    }

    func testLANCoexistencePolicySuppressesEveryHealthyInput()
        async {
        let output = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(outputs: [output])
        let harness = DriverTestHarness(
            policy: .suppressedForLANCoexistence,
            factory: factory
        )
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()

        await harness.beginMonitoring(epoch)
        await harness.replacePeer(peer, generation: 1)
        await harness.installTrack(track)
        await harness.updateDevice(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        await harness.authorize(peer: peer, generation: 1)

        XCTAssertEqual(factory.requestCount, 0)
        XCTAssertFalse(track.isEnabled)
        let result = await harness.snapshot()
        XCTAssertEqual(
            result.policy,
            .suppressedForLANCoexistence
        )
        XCTAssertEqual(
            result.phase,
            .suppressedForLANCoexistence
        )
        XCTAssertEqual(
            result.transportAuthorizationEpoch,
            0
        )
    }

    func testRustEvidenceHealthyDriverRetainsActualAttemptAndOutput() async {
        await exerciseRustEvidenceDriver(.none)
    }

    func testRustReadinessRefusalRetiresOwnedOutputAndSurvivesChurn() async {
        let faults: [DriverTestEvidenceFault] = [
            .readinessWrongVote, .readinessStatusZero,
        ]
        for fault in faults {
            await exerciseRustEvidenceDriver(fault)
        }
    }

    func testRustWatermarkRefusalRetiresOwnedOutputAndSurvivesChurn() async {
        let faults: [DriverTestEvidenceFault] = [
            .watermarkWrongAdvance, .watermarkStatusZero,
        ]
        for fault in faults {
            await exerciseRustEvidenceDriver(fault)
        }
    }

    func testRustFreshnessRefusalRetiresOwnedOutputWithoutExtraClockRead() async {
        let faults: [DriverTestEvidenceFault] = [
            .freshnessPlanWrongVote, .freshnessPlanStatusZero,
            .freshnessDecisionWrongVote, .freshnessDecisionStatusZero,
        ]
        for fault in faults {
            await exerciseRustEvidenceDriver(fault)
        }
    }

    func testRustEvidenceRefusalCleanupReentryPreservesTerminalShutdown() async {
        let cuts: [DriverTestEvidenceCleanup] = [.trackDisable, .outputStop]
        for cut in cuts {
            await exerciseRustEvidenceDriver(.watermarkStatusZero, cleanup: cut)
        }
    }

    func testRustEvidenceFrameRejectsNestedSnapshotAndNativeGetterSupersession() async {
        let cuts: [DriverTestEvidenceReentry] = [
            .nestedWatermarkSnapshot, .progressShutdown, .freshnessClockShutdown,
        ]
        for cut in cuts {
            let output = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
            let unusedOutput = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
            let factory = DriverTestOutputFactory(outputs: [output, unusedOutput])
            let watchdog = DriverTestMediaFreshnessWatchdog(now: 10)
            let harness = DriverTestHarness(
                factory: factory,
                mediaFreshnessTimeoutNanoseconds: 100,
                mediaFreshnessWatchdog: watchdog,
                automaticallyAdvanceInboundMedia: false
            )
            await harness.configureEvidenceObservation(cut, output: output, watchdog: watchdog)
            let peer = DriverTestPeer()
            let track = DriverTestTrack()
            let epoch = UUID()
            await prepare(harness: harness, epoch: epoch, peer: peer, track: track)
            await harness.authorize(peer: peer, generation: 1)
            await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
            let initialSleep = await eventually { watchdog.scheduleCount > 0 }
            XCTAssertTrue(initialSleep)
            await harness.publishInboundMedia(packets: 10, bytes: 800)
            let priorSchedules = watchdog.scheduleCount
            await harness.publishInboundMedia(packets: 11, bytes: 880)
            let renewedSleep = await eventually { watchdog.scheduleCount > priorSchedules }
            XCTAssertTrue(renewedSleep)
            let healthy = await harness.snapshot()
            XCTAssertEqual(healthy.phase, .forwardingHealthy)
            XCTAssertNotNil(healthy.currentAttemptID)
            XCTAssertNotNil(healthy.currentKey)
            XCTAssertTrue(healthy.exactTrackAdmitted)
            XCTAssertTrue(healthy.inboundMediaFresh)
            XCTAssertTrue(track.isEnabled)
            XCTAssertEqual(output.stopCount, 0)
            XCTAssertEqual(output.evidenceCorruptionCounts, [0, 0, 0])

            let progressBefore = output.progressReadCount
            let clockBefore = watchdog.nowReadCount
            let disablesBefore = track.disableCount
            let callsBefore = output.evidenceCallCounts
            let votesBefore = output.freshnessVotes.count
            await harness.armEvidenceReentry(cut, output: output, watchdog: watchdog)
            let observed: WorldwideIPhoneMicrophoneForwardingHostSnapshot
            if cut == .nestedWatermarkSnapshot {
                await harness.publishInboundMedia(packets: 12, bytes: 960)
                observed = await harness.snapshot()
            } else {
                observed = await harness.snapshot()
            }
            XCTAssertNil(observed.currentAttemptID)
            XCTAssertNil(observed.currentKey)
            XCTAssertFalse(observed.exactTrackAdmitted)
            XCTAssertFalse(observed.queueRunning)
            XCTAssertEqual(observed.progress, .zero)
            XCTAssertFalse(observed.inboundMediaFresh)
            XCTAssertEqual(observed.inboundMediaAdvancementCount, 0)
            XCTAssertEqual(observed.attemptGeneration, 1)
            XCTAssertEqual(output.startCount, 1)
            XCTAssertEqual(output.stopCount, 1)
            XCTAssertFalse(track.isEnabled)
            XCTAssertEqual(factory.requestCount, 1)
            XCTAssertEqual(output.progressReadCount - progressBefore, 1)
            XCTAssertEqual(output.evidenceCorruptionCounts, [0, 0, 0])
            let actualCallDelta = zip(output.evidenceCallCounts, callsBefore).map { pair in pair.0 - pair.1 }
            switch cut {
            case .nestedWatermarkSnapshot:
                XCTAssertEqual(observed.phase, .runtimeFailed)
                XCTAssertEqual(observed.lastFailureCategory, .evidenceBridgeRefused)
                XCTAssertEqual(track.disableCount - disablesBefore, 1)
                XCTAssertEqual(actualCallDelta, [0, 1, 2])
                XCTAssertEqual(watchdog.nowReadCount - clockBefore, 1)
                let nested = output.nestedObservation
                XCTAssertNotNil(nested)
                XCTAssertEqual(nested?.phase, .runtimeFailed)
                XCTAssertEqual(nested?.queueRunning, false)
                XCTAssertEqual(nested?.inboundMediaFresh, false)
                XCTAssertEqual(nested?.progressReadDelta, 0)
                XCTAssertEqual(nested?.clockReadDelta, 0)
                XCTAssertEqual(nested?.producerDelta, [0, 0, 0])
                XCTAssertEqual(output.nestedSnapshotCount, 1)
                XCTAssertEqual(output.progressHookCount, 0)
                XCTAssertEqual(watchdog.nowHookCount, 0)
            case .progressShutdown:
                XCTAssertEqual(observed.phase, .stopped)
                XCTAssertNil(observed.lastFailureCategory)
                XCTAssertFalse(observed.transportAuthorized)
                XCTAssertEqual(track.disableCount - disablesBefore, 2)
                XCTAssertEqual(actualCallDelta, [0, 0, 0])
                XCTAssertEqual(watchdog.nowReadCount - clockBefore, 0)
                XCTAssertEqual(output.progressHookCount, 1)
                XCTAssertEqual(watchdog.nowHookCount, 0)
                XCTAssertEqual(output.nestedSnapshotCount, 0)
            case .freshnessClockShutdown:
                XCTAssertEqual(observed.phase, .stopped)
                XCTAssertNil(observed.lastFailureCategory)
                XCTAssertFalse(observed.transportAuthorized)
                XCTAssertEqual(track.disableCount - disablesBefore, 2)
                XCTAssertEqual(actualCallDelta, [0, 0, 1])
                XCTAssertEqual(watchdog.nowReadCount - clockBefore, 1)
                XCTAssertEqual(Array(output.freshnessVotes.dropFirst(votesBefore)), [[0, 2]])
                XCTAssertEqual(watchdog.nowHookCount, 1)
                XCTAssertEqual(output.progressHookCount, 0)
                XCTAssertEqual(output.nestedSnapshotCount, 0)
            }

            let settledCalls = output.evidenceCallCounts
            let settledProgress = output.progressReadCount
            let settledClock = watchdog.nowReadCount
            await harness.invalidateTransport()
            let replacementPeer = DriverTestPeer()
            let replacementTrack = DriverTestTrack()
            await harness.replacePeer(replacementPeer, generation: 2)
            await harness.installTrack(replacementTrack)
            await harness.updateDevice(snapshot(epoch: epoch, generation: 2, available: true))
            await harness.authorize(peer: replacementPeer, generation: 2)
            await harness.publishInboundMedia(packets: 100, bytes: 8_000)
            let again = await harness.snapshot()
            XCTAssertEqual(again.phase, observed.phase)
            XCTAssertEqual(again.lastFailureCategory, observed.lastFailureCategory)
            XCTAssertNil(again.currentAttemptID)
            XCTAssertNil(again.currentKey)
            XCTAssertFalse(again.exactTrackAdmitted)
            XCTAssertFalse(again.inboundMediaFresh)
            XCTAssertFalse(replacementTrack.isEnabled)
            XCTAssertEqual(factory.requestCount, 1)
            XCTAssertEqual(replacementPeer.admissionCount, 0)
            XCTAssertEqual(unusedOutput.startCount, 0)
            XCTAssertEqual(unusedOutput.stopCount, 0)
            XCTAssertEqual(output.stopCount, 1)
            XCTAssertEqual(output.evidenceCallCounts, settledCalls)
            XCTAssertEqual(output.progressReadCount, settledProgress)
            XCTAssertEqual(watchdog.nowReadCount, settledClock)
            await harness.shutdown()
            watchdog.advance(to: UInt64.max)
            XCTAssertEqual(output.stopCount, 1)
        }
    }

    func testRustRetryAllFourOperationsRejectStatusAndCoherentCorruption() async {
        for operation in UInt32(1)...4 {
            for fault in [DriverTestRetryFault.statusZero, .coherentCorruption] {
                await exerciseRustRetryRefusal(operation: operation, fault: fault)
            }
        }
    }

    func testRustRetryNestedSnapshotPoisonsEveryOperationWithoutRecursiveProducer() async {
        for operation in UInt32(1)...4 {
            await exerciseRustRetryRefusal(operation: operation, fault: .nestedSnapshot)
        }
    }

    func testRustRetryShutdownAtNativeCleanupPreservesStoppedAndSkipsRetry() async {
        for cut in [DriverTestEvidenceCleanup.trackDisable, .outputStop] {
            let output = DriverTestOutput(startError: DriverTestError.start)
            let unused = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
            let factory = DriverTestOutputFactory(outputs: [output, unused])
            let harness = DriverTestHarness(factory: factory, automaticallyAdvanceInboundMedia: false)
            let peer = DriverTestPeer(), track = DriverTestTrack(), epoch = UUID()
            await harness.configureRetryEvidence(factory: factory, track: track)
            await prepare(harness: harness, epoch: epoch, peer: peer, track: track)
            await harness.authorize(peer: peer, generation: 1)
            let disableBaseline = track.disableCount
            await harness.armCleanupShutdown(cut, output: output, track: track)
            await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
            let observed = await harness.snapshot()
            let key = retryKey(epoch: epoch, snapshot: observed)
            let row = await harness.retryObservation(key)
            XCTAssertEqual(observed.phase, .stopped)
            XCTAssertNil(observed.currentAttemptID)
            XCTAssertFalse(observed.transportAuthorized)
            XCTAssertEqual(observed.attemptGeneration, 1)
            XCTAssertEqual(row.count, 1)
            XCTAssertEqual(row.mayRetry, false)
            XCTAssertFalse(row.bridgeFaulted)
            XCTAssertEqual(row.faultExhaustCalls, 0)
            XCTAssertEqual(factory.retryCalls.map(\.opcode), [1, 2])
            XCTAssertEqual(factory.attemptIDCount, 1)
            XCTAssertEqual(factory.requestCount, 1)
            XCTAssertEqual(output.startCount, 1)
            XCTAssertEqual(output.stopCount, 1)
            XCTAssertEqual(track.disableCount - disableBaseline, 2)
            XCTAssertFalse(track.isEnabled)
            XCTAssertEqual(track.cleanupHookCount, cut == .trackDisable ? 1 : 0)
            XCTAssertEqual(output.cleanupHookCount, cut == .outputStop ? 1 : 0)
            await harness.shutdown()
            XCTAssertEqual(output.stopCount, 1)
            XCTAssertEqual(unused.startCount, 0)
        }
    }

    func testRustRetryStrictBudgetAndLazyNonretryableFailureKeepExactHistory() async {
        for maximum in [1, 3] {
            let outputs = (0..<maximum).map { _ in DriverTestOutput(startError: DriverTestError.start) }
            let unused = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
            let factory = DriverTestOutputFactory(outputs: outputs + [unused])
            let harness = DriverTestHarness(factory: factory, maximumAttemptCountPerKey: maximum,
                                            automaticallyAdvanceInboundMedia: false)
            let peer = DriverTestPeer(), track = DriverTestTrack(), epoch = UUID()
            await harness.configureRetryEvidence(factory: factory, track: track)
            await prepare(harness: harness, epoch: epoch, peer: peer, track: track)
            await harness.authorize(peer: peer, generation: 1)
            await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
            let observed = await harness.snapshot()
            let key = retryKey(epoch: epoch, snapshot: observed)
            let row = await harness.retryObservation(key)
            XCTAssertEqual(observed.phase, .startFailed)
            XCTAssertEqual(observed.attemptGeneration, UInt64(maximum))
            XCTAssertNil(observed.currentAttemptID)
            XCTAssertEqual(row.count, maximum)
            XCTAssertEqual(row.mayRetry, false)
            XCTAssertFalse(row.bridgeFaulted)
            XCTAssertFalse(row.redrive)
            XCTAssertEqual(row.retainedKeys, [key])
            XCTAssertEqual(factory.attemptIDCount, maximum)
            XCTAssertEqual(factory.requestCount, maximum)
            XCTAssertEqual(outputs.map(\.startCount), Array(repeating: 1, count: maximum))
            XCTAssertEqual(outputs.map(\.stopCount), Array(repeating: 1, count: maximum))
            let records = factory.retryCalls.filter { $0.opcode == 2 }
            XCTAssertEqual(records.map(\.beforeCount), (0..<maximum).map(Int64.init))
            XCTAssertEqual(records.map(\.beforePresent), [0] + Array(repeating: 1, count: maximum - 1))
            XCTAssertEqual(records.map(\.afterCount), (1...maximum).map(Int64.init))
            XCTAssertEqual(records.map(\.afterMayRetry), Array(repeating: 0, count: maximum))
            let failures = factory.retryCalls.filter { $0.opcode == 3 }
            XCTAssertEqual(failures.map(\.beforeCount), (1...maximum).map(Int64.init))
            XCTAssertEqual(failures.map(\.decision), Array(repeating: 1, count: maximum - 1) + [0])
            XCTAssertEqual(failures.map(\.redrive), Array(repeating: 2, count: maximum - 1) + [1])
            XCTAssertTrue(failures.allSatisfy { $0.nativeStopCount == 1 && $0.nativeTrackEnabled == false })
            XCTAssertEqual(unused.startCount, 0)
            await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
            XCTAssertEqual(factory.requestCount, maximum)
            await harness.shutdown()
        }

        // This original typed output error uses allowRetry:false: operation three
        // must not run, rather than a Swift false vote or a Rust category fallback.
        let output = DriverTestOutput(startError:
            BlackHoleMicrophoneOutputError.sharedClockUnsafe(capturedSharedClockRejection()))
        let factory = DriverTestOutputFactory(outputs: [output])
        let harness = DriverTestHarness(factory: factory, automaticallyAdvanceInboundMedia: false)
        let peer = DriverTestPeer(), track = DriverTestTrack(), epoch = UUID()
        await harness.configureRetryEvidence(factory: factory, track: track)
        await prepare(harness: harness, epoch: epoch, peer: peer, track: track)
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
        let observed = await harness.snapshot()
        let row = await harness.retryObservation(retryKey(epoch: epoch, snapshot: observed))
        XCTAssertEqual(observed.phase, .sharedClockUnsafe)
        XCTAssertEqual(observed.lastFailureCategory, .sharedClockUnsafe)
        XCTAssertEqual(factory.retryCalls.filter { $0.opcode == 3 }.count, 0)
        XCTAssertEqual(row.count, 1)
        XCTAssertEqual(row.mayRetry, false)
        XCTAssertFalse(row.bridgeFaulted)
        XCTAssertEqual(row.faultExhaustCalls, 0)
        XCTAssertEqual(output.stopCount, 1)
        XCTAssertFalse(track.isEnabled)
        await harness.shutdown()

        // A genuine admission failure invokes op3 and receives accepted false;
        // it must retain the present, already-consumed row rather than refuse.
        let deniedOutput = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
        let deniedFactory = DriverTestOutputFactory(outputs: [deniedOutput])
        let deniedHarness = DriverTestHarness(factory: deniedFactory, automaticallyAdvanceInboundMedia: false)
        let deniedPeer = DriverTestPeer(healthy: false), deniedTrack = DriverTestTrack(), deniedEpoch = UUID()
        await deniedHarness.configureRetryEvidence(factory: deniedFactory, track: deniedTrack)
        await prepare(harness: deniedHarness, epoch: deniedEpoch, peer: deniedPeer, track: deniedTrack)
        await deniedHarness.authorize(peer: deniedPeer, generation: 1)
        await deniedHarness.updateDevice(snapshot(epoch: deniedEpoch, generation: 1, available: true))
        let denied = await deniedHarness.snapshot()
        let deniedRow = await deniedHarness.retryObservation(retryKey(epoch: deniedEpoch, snapshot: denied))
        let falseVotes = deniedFactory.retryCalls.filter { $0.opcode == 3 }
        XCTAssertEqual(falseVotes.count, 1)
        XCTAssertEqual(falseVotes.first?.status, 1)
        XCTAssertEqual(falseVotes.first?.category, 4)
        XCTAssertEqual(falseVotes.first?.decision, 0)
        XCTAssertEqual(falseVotes.first?.beforeMayRetry, 0)
        XCTAssertEqual(falseVotes.first?.afterMayRetry, 0)
        XCTAssertEqual(falseVotes.first?.redrive, 1)
        XCTAssertEqual(denied.phase, .admissionFailed)
        XCTAssertEqual(deniedRow.count, 1)
        XCTAssertEqual(deniedRow.mayRetry, false)
        XCTAssertFalse(deniedRow.bridgeFaulted)
        XCTAssertEqual(deniedFactory.requestCount, 1)
        XCTAssertEqual(deniedOutput.stopCount, 1)
        XCTAssertFalse(deniedTrack.isEnabled)
        await deniedHarness.shutdown()
    }

    func testRustRetryValidResultCannotPublishAcrossShutdownOrPeerReplacement() async {
        for operation in UInt32(1)...4 {
            for fault in [DriverTestRetryFault.shutdown, .replacePeer] {
                let first = DriverTestOutput(startError: operation >= 3 ? DriverTestError.start : nil,
                                             progressSnapshots: readyProgressSnapshots())
                let successor = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
                let factory = DriverTestOutputFactory(outputs: [first, successor])
                let watchdog = DriverTestMediaFreshnessWatchdog(now: 10)
                let harness = DriverTestHarness(factory: factory, retrySleepThrowsAfterGate: operation == 4,
                                                mediaFreshnessWatchdog: watchdog,
                                                automaticallyAdvanceInboundMedia: false)
                let peer = DriverTestPeer(), replacementPeer = DriverTestPeer()
                let track = DriverTestTrack(), replacementTrack = DriverTestTrack(), epoch = UUID()
                await prepare(harness: harness, epoch: epoch, peer: peer, track: track)
                await harness.authorize(peer: peer, generation: 1)
                let originalState = await harness.snapshot()
                let originalKey = retryKey(epoch: epoch, snapshot: originalState)
                await harness.configureRetryEvidence(factory: factory, target: operation, fault: fault,
                    output: first, track: track, replacementPeer: replacementPeer, observationKey: originalKey)
                factory.armRetryFault()
                await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
                let observed = await harness.snapshot()
                let row = await harness.retryObservation(originalKey)
                XCTAssertNil(observed.currentAttemptID)
                XCTAssertFalse(row.bridgeFaulted)
                XCTAssertEqual(row.faultExhaustCalls, 0)
                XCTAssertEqual(row.count, operation >= 3 ? 1 : nil)
                XCTAssertEqual(row.mayRetry, operation >= 3 ? (operation == 4) : nil)
                XCTAssertEqual(factory.retryMutationCount, 1)
                XCTAssertEqual(factory.requestCount, operation >= 3 ? 1 : 0)
                XCTAssertEqual(factory.attemptIDCount, operation >= 3 ? 1 : 0)
                XCTAssertEqual(first.stopCount, operation >= 3 ? 1 : 0)
                XCTAssertEqual(factory.retryCalls.filter { $0.opcode == operation }.count, 1)
                XCTAssertEqual(factory.retryCalls.filter { $0.opcode == operation }.first?.status, 1)
                XCTAssertFalse(track.isEnabled)
                if fault == .shutdown {
                    XCTAssertEqual(observed.phase, .stopped)
                    XCTAssertFalse(observed.transportAuthorized)
                    let calls = factory.retryCalls
                    await harness.replacePeer(replacementPeer, generation: 2)
                    await harness.installTrack(replacementTrack)
                    await harness.authorize(peer: replacementPeer, generation: 2)
                    XCTAssertEqual(factory.retryCalls, calls)
                    XCTAssertEqual(replacementPeer.admissionCount, 0)
                    XCTAssertEqual(successor.startCount, 0)
                } else {
                    XCTAssertEqual(observed.peerGeneration, 2)
                    XCTAssertFalse(observed.transportAuthorized)
                    // Use the genuine replacement's own public lifecycle, not the
                    // old entry or a whole-state setter, to form its new candidate.
                    await harness.replacePeer(replacementPeer, generation: 2)
                    await harness.installTrack(replacementTrack)
                    await harness.authorize(peer: replacementPeer, generation: 2)
                    let replacement = await harness.snapshot()
                    XCTAssertNotNil(replacement.currentAttemptID)
                    XCTAssertEqual(replacement.currentKey?.peerGeneration, 2)
                    XCTAssertTrue(replacement.exactTrackAdmitted)
                    XCTAssertTrue(replacementTrack.isEnabled)
                    XCTAssertEqual(replacementPeer.admissionCount, 1)
                    XCTAssertEqual(factory.requestCount, operation >= 3 ? 2 : 1)
                    XCTAssertEqual(factory.attemptIDCount, operation >= 3 ? 2 : 1)
                    let retainedOld = await harness.retryObservation(originalKey)
                    XCTAssertEqual(retainedOld.count, row.count)
                    XCTAssertEqual(retainedOld.mayRetry, row.mayRetry)
                    XCTAssertFalse(retainedOld.bridgeFaulted)
                    let newRecord = factory.retryCalls.filter { $0.opcode == 2 }.last
                    XCTAssertEqual(newRecord?.beforePresent, 0)
                    XCTAssertEqual(newRecord?.afterCount, 1)
                    XCTAssertEqual(newRecord?.afterMayRetry, 0)
                }
                await harness.shutdown()
                watchdog.advance(to: UInt64.max)
            }
        }
    }

    func testRustRetryAwaitResumptionUsesFreshGenerationAndRevivedAbsentHistory() async {
        // A generation replacement during the original suspended retry cannot
        // Record the captured old row or apply Exhaust to the newer key.
        do {
            let first = DriverTestOutput(startError: DriverTestError.start)
            let successor = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
            let factory = DriverTestOutputFactory(outputs: [first, successor])
            let gate = DriverSuspensionGate()
            let watchdog = DriverTestMediaFreshnessWatchdog(now: 10)
            let harness = DriverTestHarness(factory: factory, retryGate: gate,
                mediaFreshnessWatchdog: watchdog, automaticallyAdvanceInboundMedia: false)
            let peer = DriverTestPeer(), track = DriverTestTrack(), epoch = UUID()
            await prepare(harness: harness, epoch: epoch, peer: peer, track: track)
            await harness.authorize(peer: peer, generation: 1)
            let before = await harness.snapshot()
            let oldKey = retryKey(epoch: epoch, snapshot: before)
            await harness.configureRetryEvidence(factory: factory, track: track, observationKey: oldKey)
            let initialDevice = snapshot(epoch: epoch, generation: 1, available: true)
            let pending = Task { await harness.updateDevice(initialDevice) }
            let sleeping = await eventually { await gate.hasEntered() }
            XCTAssertTrue(sleeping)
            let oldRow = await harness.retryObservation(oldKey)
            XCTAssertEqual(oldRow.count, 1)
            XCTAssertEqual(oldRow.mayRetry, true)
            await harness.updateDevice(snapshot(epoch: epoch, generation: 2, available: true))
            await gate.open()
            await pending.value
            let current = await harness.snapshot()
            let newKey = retryKey(epoch: epoch, snapshot: current, deviceGeneration: 2)
            XCTAssertEqual(current.currentKey, newKey)
            XCTAssertEqual(current.attemptGeneration, 2)
            XCTAssertTrue(current.exactTrackAdmitted)
            let retainedOld = await harness.retryObservation(oldKey)
            let newRow = await harness.retryObservation(newKey)
            XCTAssertEqual(retainedOld.count, 1)
            XCTAssertEqual(retainedOld.mayRetry, true)
            XCTAssertEqual(newRow.count, 1)
            XCTAssertEqual(newRow.mayRetry, false)
            XCTAssertEqual(newRow.retainedKeys, [oldKey, newKey])
            let records = factory.retryCalls.filter { $0.opcode == 2 }
            XCTAssertEqual(records.count, 2)
            XCTAssertEqual(records.map(\.beforePresent), [0, 0])
            XCTAssertEqual(records.map(\.beforeCount), [0, 0])
            XCTAssertEqual(records.map(\.afterCount), [1, 1])
            XCTAssertEqual(factory.retryCalls.filter { $0.opcode == 4 }.count, 0)
            XCTAssertEqual(factory.attemptIDCount, 2)
            XCTAssertEqual(factory.requestCount, 2)
            XCTAssertEqual(first.stopCount, 1)
            XCTAssertEqual(successor.stopCount, 0)
            await harness.shutdown()
            watchdog.advance(to: UInt64.max)
            XCTAssertEqual(successor.stopCount, 1)
        }

        // Actual RTP revival removes the same key while retrySleep is suspended.
        // The cancelled original sleep then observes whole absence in op4 and
        // Retain, rather than replaying the pre-await present row.
        do {
            let first = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
            let successor = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
            let factory = DriverTestOutputFactory(outputs: [first, successor])
            let gate = DriverSuspensionGate()
            let watchdog = DriverTestMediaFreshnessWatchdog(now: 10)
            let harness = DriverTestHarness(factory: factory, retryGate: gate, retrySleepThrowsAfterGate: true,
                mediaFreshnessWatchdog: watchdog, automaticallyAdvanceInboundMedia: false)
            let peer = DriverTestPeer(), track = DriverTestTrack(), epoch = UUID()
            await prepare(harness: harness, epoch: epoch, peer: peer, track: track)
            await harness.authorize(peer: peer, generation: 1)
            let before = await harness.snapshot()
            let key = retryKey(epoch: epoch, snapshot: before)
            await harness.configureRetryEvidence(factory: factory, track: track, observationKey: key)
            await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
            await harness.publishInboundMedia(packets: 10, bytes: 800)
            await harness.publishInboundMedia(packets: 11, bytes: 880)
            let healthy = await harness.snapshot()
            XCTAssertEqual(healthy.phase, .forwardingHealthy)
            XCTAssertEqual(healthy.currentKey, key)
            let pending = Task { await harness.handleRuntimeFailure(first, category: .sourceMediaStalled) }
            let sleeping = await eventually { await gate.hasEntered() }
            XCTAssertTrue(sleeping)
            let permitted = await harness.retryObservation(key)
            XCTAssertEqual(permitted.count, 1)
            XCTAssertEqual(permitted.mayRetry, true)
            XCTAssertEqual(first.stopCount, 1)
            await harness.publishInboundMedia(packets: 12, bytes: 960)
            let removed = await harness.retryObservation(key)
            XCTAssertNil(removed.count)
            XCTAssertNil(removed.mayRetry)
            XCTAssertEqual(removed.retainedKeys, [])
            XCTAssertTrue(removed.redrive)
            await gate.open()
            let handled = await pending.value
            XCTAssertTrue(handled)
            let current = await harness.snapshot()
            XCTAssertEqual(current.currentKey, key)
            XCTAssertEqual(current.attemptGeneration, 2)
            XCTAssertTrue(current.exactTrackAdmitted)
            let row = await harness.retryObservation(key)
            XCTAssertEqual(row.count, 1)
            XCTAssertEqual(row.mayRetry, false)
            XCTAssertEqual(row.retainedKeys, [key])
            XCTAssertFalse(row.bridgeFaulted)
            XCTAssertEqual(row.faultExhaustCalls, 0)
            let exhaustion = factory.retryCalls.filter { $0.opcode == 4 }
            XCTAssertEqual(exhaustion.count, 1)
            XCTAssertEqual(exhaustion.first?.beforePresent, 0)
            XCTAssertEqual(exhaustion.first?.beforeCount, 0)
            XCTAssertEqual(exhaustion.first?.beforeMayRetry, 0)
            XCTAssertEqual(exhaustion.first?.afterPresent, 0)
            XCTAssertEqual(exhaustion.first?.afterCount, 0)
            XCTAssertEqual(exhaustion.first?.decision, 0)
            XCTAssertEqual(exhaustion.first?.redrive, 0)
            XCTAssertEqual(exhaustion.first?.nativeRedrive, true)
            let records = factory.retryCalls.filter { $0.opcode == 2 }
            XCTAssertEqual(records.count, 2)
            XCTAssertEqual(records.map(\.beforePresent), [0, 0])
            XCTAssertEqual(records.map(\.afterCount), [1, 1])
            XCTAssertEqual(factory.attemptIDCount, 2)
            XCTAssertEqual(factory.requestCount, 2)
            XCTAssertEqual(first.stopCount, 1)
            XCTAssertEqual(successor.stopCount, 0)
            await harness.shutdown()
            watchdog.advance(to: UInt64.max)
            XCTAssertEqual(successor.stopCount, 1)
        }
    }

    private func exerciseRustRetryRefusal(operation: UInt32, fault: DriverTestRetryFault) async {
        let output = DriverTestOutput(startError: operation >= 3 ? DriverTestError.start : nil,
                                      progressSnapshots: readyProgressSnapshots())
        let unused = DriverTestOutput(progressSnapshots: readyProgressSnapshots())
        let factory = DriverTestOutputFactory(outputs: [output, unused])
        let watchdog = DriverTestMediaFreshnessWatchdog(now: 10)
        let harness = DriverTestHarness(factory: factory,
            retrySleepThrowsAfterGate: operation == 4,
            mediaFreshnessWatchdog: watchdog, automaticallyAdvanceInboundMedia: false)
        let peer = DriverTestPeer(), track = DriverTestTrack(), epoch = UUID()
        await harness.configureRetryEvidence(factory: factory, target: operation, fault: fault,
                                             output: output, track: track)
        factory.armRetryFault()
        await prepare(harness: harness, epoch: epoch, peer: peer, track: track)
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
        let observed = await harness.snapshot()
        let key = retryKey(epoch: epoch, snapshot: observed)
        let row = await harness.retryObservation(key)
        XCTAssertEqual(observed.phase, .runtimeFailed)
        XCTAssertEqual(observed.lastFailureCategory, .evidenceBridgeRefused)
        XCTAssertNil(observed.currentAttemptID)
        XCTAssertNil(observed.currentKey)
        XCTAssertFalse(track.isEnabled)
        XCTAssertEqual(factory.retryMutationCount, 1)
        XCTAssertTrue(row.bridgeFaulted)
        XCTAssertFalse(row.redrive)
        XCTAssertEqual(factory.attemptIDCount, operation >= 3 ? 1 : 0)
        XCTAssertEqual(factory.requestCount, operation >= 3 ? 1 : 0)
        XCTAssertEqual(observed.attemptGeneration, operation >= 3 ? 1 : 0)
        XCTAssertEqual(output.startCount, operation >= 3 ? 1 : 0)
        XCTAssertEqual(output.stopCount, operation >= 3 ? 1 : 0)
        XCTAssertEqual(row.count, operation >= 3 ? 1 : nil)
        XCTAssertEqual(row.mayRetry, operation >= 3 ? (operation == 4) : nil)
        XCTAssertEqual(row.retainedKeys, operation >= 3 ? [key] : [])
        XCTAssertEqual(row.faultExhaustCalls, operation == 3 ? 1 : 0)
        let targeted = factory.retryCalls.filter { $0.opcode == operation }
        XCTAssertEqual(targeted.count, 1)
        XCTAssertEqual(targeted.first?.status, 1)
        if operation >= 3 {
            XCTAssertEqual(targeted.first?.nativeStopCount, 1)
            XCTAssertEqual(targeted.first?.nativeTrackEnabled, false)
        }
        if fault == .nestedSnapshot {
            XCTAssertEqual(factory.retryNestedSnapshotCount, 1)
            XCTAssertEqual(factory.retryNestedPhase, .runtimeFailed)
        }
        XCTAssertEqual(output.progressReadCount, 0)
        let frozenCalls = factory.retryCalls
        let frozenClocks = watchdog.nowReadCount
        // The whole-driver latch, not a history rewrite, prevents a successor.
        await harness.invalidateTransport()
        let replacementPeer = DriverTestPeer(), replacementTrack = DriverTestTrack()
        await harness.replacePeer(replacementPeer, generation: 2)
        await harness.installTrack(replacementTrack)
        await harness.updateDevice(snapshot(epoch: epoch, generation: 2, available: true))
        await harness.authorize(peer: replacementPeer, generation: 2)
        await harness.publishInboundMedia(packets: 100, bytes: 8_000)
        let stillRefused = await harness.snapshot()
        XCTAssertEqual(stillRefused.phase, .runtimeFailed)
        XCTAssertNil(stillRefused.currentAttemptID)
        XCTAssertEqual(factory.retryCalls, frozenCalls)
        XCTAssertEqual(factory.requestCount, operation >= 3 ? 1 : 0)
        XCTAssertEqual(factory.attemptIDCount, operation >= 3 ? 1 : 0)
        XCTAssertEqual(watchdog.nowReadCount, frozenClocks)
        XCTAssertEqual(unused.startCount, 0)
        XCTAssertEqual(replacementPeer.admissionCount, 0)
        let again = await harness.retryObservation(key)
        XCTAssertEqual(again.count, row.count)
        XCTAssertEqual(again.mayRetry, row.mayRetry)
        XCTAssertEqual(again.faultExhaustCalls, row.faultExhaustCalls)
        await harness.shutdown()
        watchdog.advance(to: UInt64.max)
        XCTAssertEqual(output.stopCount, operation >= 3 ? 1 : 0)
    }

    private func retryKey(epoch: UUID, snapshot: WorldwideIPhoneMicrophoneForwardingHostSnapshot,
                          deviceGeneration: UInt64 = 1) -> WorldwideIPhoneMicrophoneForwardingKey {
        .init(monitorEpoch: epoch, deviceGeneration: deviceGeneration,
              peerGeneration: snapshot.peerGeneration,
              transportAuthorizationEpoch: snapshot.transportAuthorizationEpoch,
              trackGeneration: snapshot.trackGeneration)
    }

    private func exerciseRustEvidenceDriver(
        _ fault: DriverTestEvidenceFault,
        cleanup: DriverTestEvidenceCleanup? = nil
    ) async {
        let output = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let unusedOutput = DriverTestOutput(
            progressSnapshots: readyProgressSnapshots()
        )
        let factory = DriverTestOutputFactory(outputs: [output, unusedOutput])
        let watchdog = DriverTestMediaFreshnessWatchdog(now: 10)
        let harness = DriverTestHarness(
            factory: factory,
            mediaFreshnessTimeoutNanoseconds: 100,
            mediaFreshnessWatchdog: watchdog,
            automaticallyAdvanceInboundMedia: false
        )
        await harness.configureEvidenceFault(fault, output: output)
        if fault.family == 0 {
            output.armEvidenceFault()
        }
        let peer = DriverTestPeer()
        let track = DriverTestTrack()
        let epoch = UUID()
        await prepare(harness: harness, epoch: epoch, peer: peer, track: track)
        await harness.authorize(peer: peer, generation: 1)
        await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
        let disablesBeforeCleanup = track.disableCount

        if fault.family != 0 {
            let initialSleep = await eventually { watchdog.scheduleCount > 0 }
            XCTAssertTrue(initialSleep, "The original admitted watchdog must settle before read accounting.")
            await harness.publishInboundMedia(packets: 10, bytes: 800)
            let secondSchedules = watchdog.scheduleCount
            await harness.publishInboundMedia(packets: 11, bytes: 880)
            let secondSleep = await eventually { watchdog.scheduleCount > secondSchedules }
            XCTAssertTrue(secondSleep)
            let healthy = await harness.snapshot()
            XCTAssertEqual(healthy.phase, .forwardingHealthy)
            XCTAssertNil(healthy.lastFailureCategory)
            XCTAssertNotNil(healthy.currentAttemptID)
            XCTAssertNotNil(healthy.currentKey)
            XCTAssertTrue(healthy.exactTrackAdmitted)
            XCTAssertTrue(healthy.queueRunning)
            XCTAssertTrue(healthy.inboundMediaFresh)
            XCTAssertEqual(healthy.inboundMediaAdvancementCount, 1)
            XCTAssertEqual(healthy.consecutiveStaleInboundMediaSamples, 0)
            XCTAssertEqual(healthy.attemptGeneration, 1)
            XCTAssertEqual(output.startCount, 1)
            XCTAssertEqual(output.stopCount, 0)
            XCTAssertTrue(track.isEnabled)
            XCTAssertEqual(factory.requestCount, 1)
            XCTAssertEqual(factory.requestedDeviceIDs, [89])
            XCTAssertEqual(factory.requestedUIDs, ["com.elamin.opensteamer.virtual-microphone.writer"])
            XCTAssertGreaterThanOrEqual(output.evidenceCallCounts[0], 2)
            XCTAssertEqual(output.evidenceCallCounts[1], 2)
            XCTAssertGreaterThan(output.evidenceCallCounts[2], 0)
            XCTAssertEqual(output.evidenceCorruptionCounts, [0, 0, 0])

            if fault == .none {
                let again = await harness.snapshot()
                XCTAssertEqual(again.phase, .forwardingHealthy)
                XCTAssertEqual(again.currentAttemptID, healthy.currentAttemptID)
                XCTAssertEqual(again.currentKey, healthy.currentKey)
                XCTAssertEqual(again.inboundMediaAdvancementCount, 1)
                XCTAssertTrue(again.inboundMediaFresh)
                XCTAssertEqual(output.stopCount, 0)
                XCTAssertTrue(track.isEnabled)
                await harness.shutdown()
                watchdog.advance(to: UInt64.max)
                XCTAssertEqual(output.stopCount, 1)
                XCTAssertFalse(track.isEnabled)
                return
            }
            if let cleanup {
                await harness.armCleanupShutdown(cleanup, output: output, track: track)
            }
            output.armEvidenceFault()
            let nowReads = watchdog.nowReadCount
            if fault.family == 1 {
                await harness.publishInboundMedia(packets: 12, bytes: 960)
            } else {
                _ = await harness.snapshot()
                XCTAssertEqual(
                    watchdog.nowReadCount - nowReads,
                    fault.isFreshnessDecision ? 1 : 0,
                    "Rejected plan must not read Now; rejected final result may read only its one original Now."
                )
            }
        }

        if let cleanup {
            let stopped = await harness.snapshot()
            XCTAssertEqual(stopped.phase, .stopped)
            XCTAssertNil(stopped.currentAttemptID)
            XCTAssertNil(stopped.currentKey)
            XCTAssertFalse(stopped.transportAuthorized)
            XCTAssertFalse(stopped.exactTrackAdmitted)
            XCTAssertFalse(stopped.queueRunning)
            XCTAssertFalse(stopped.inboundMediaFresh)
            XCTAssertEqual(stopped.attemptGeneration, 1)
            XCTAssertEqual(output.startCount, 1)
            XCTAssertEqual(output.stopCount, 1)
            XCTAssertFalse(track.isEnabled)
            XCTAssertEqual(track.disableCount, disablesBeforeCleanup + 2)
            XCTAssertEqual(factory.requestCount, 1)
            XCTAssertEqual(output.evidenceCorruptionCounts, [0, 1, 0])
            XCTAssertEqual(track.cleanupHookCount, cleanup == .trackDisable ? 1 : 0)
            XCTAssertEqual(output.cleanupHookCount, cleanup == .outputStop ? 1 : 0)
            let callsAfterShutdown = output.evidenceCallCounts
            let clockAfterShutdown = watchdog.nowReadCount

            // Returning through the outer refusal must not relabel shutdown,
            // resurrect an attempt, stop an unused successor or read evidence.
            await harness.invalidateTransport()
            let replacementPeer = DriverTestPeer()
            let replacementTrack = DriverTestTrack()
            await harness.replacePeer(replacementPeer, generation: 2)
            await harness.installTrack(replacementTrack)
            await harness.updateDevice(snapshot(epoch: epoch, generation: 2, available: true))
            await harness.authorize(peer: replacementPeer, generation: 2)
            await harness.publishInboundMedia(packets: 100, bytes: 8_000)
            let stillStopped = await harness.snapshot()
            XCTAssertEqual(stillStopped.phase, .stopped)
            XCTAssertNil(stillStopped.currentAttemptID)
            XCTAssertNil(stillStopped.currentKey)
            XCTAssertFalse(stillStopped.transportAuthorized)
            XCTAssertFalse(replacementTrack.isEnabled)
            XCTAssertEqual(replacementPeer.admissionCount, 0)
            XCTAssertEqual(factory.requestCount, 1)
            XCTAssertEqual(output.stopCount, 1)
            XCTAssertEqual(track.disableCount, disablesBeforeCleanup + 2)
            XCTAssertEqual(unusedOutput.startCount, 0)
            XCTAssertEqual(unusedOutput.stopCount, 0)
            XCTAssertEqual(output.evidenceCallCounts, callsAfterShutdown)
            XCTAssertEqual(watchdog.nowReadCount, clockAfterShutdown)
            await harness.shutdown()
            watchdog.advance(to: UInt64.max)
            XCTAssertEqual(output.stopCount, 1)
            XCTAssertEqual(track.cleanupHookCount, cleanup == .trackDisable ? 1 : 0)
            XCTAssertEqual(output.cleanupHookCount, cleanup == .outputStop ? 1 : 0)
            return
        }

        let refused = await harness.snapshot()
        XCTAssertEqual(refused.phase, .runtimeFailed)
        XCTAssertEqual(refused.lastFailureCategory, .evidenceBridgeRefused)
        XCTAssertNil(refused.currentAttemptID)
        XCTAssertNil(refused.currentKey)
        XCTAssertFalse(refused.exactTrackAdmitted)
        XCTAssertFalse(refused.inboundMediaFresh)
        XCTAssertEqual(refused.inboundMediaAdvancementCount, 0)
        XCTAssertEqual(refused.attemptGeneration, 1)
        XCTAssertEqual(output.startCount, 1)
        XCTAssertEqual(output.stopCount, 1)
        XCTAssertFalse(track.isEnabled)
        XCTAssertEqual(factory.requestCount, 1)
        var expectedCorruptions = [0, 0, 0]
        expectedCorruptions[fault.family] = 1
        XCTAssertEqual(output.evidenceCorruptionCounts, expectedCorruptions)
        let callsAfterRefusal = output.evidenceCallCounts

        // Real lifecycle methods retain privacy teardown while the whole-driver
        // refusal latch must prevent another output or evidence borrow.
        await harness.updateDevice(snapshot(epoch: epoch, generation: 1, available: true))
        await harness.invalidateTransport()
        await harness.authorize(peer: peer, generation: 1)
        let replacementPeer = DriverTestPeer()
        let replacementTrack = DriverTestTrack()
        await harness.replacePeer(replacementPeer, generation: 2)
        await harness.installTrack(replacementTrack)
        await harness.updateDevice(snapshot(epoch: epoch, generation: 2, available: true))
        await harness.authorize(peer: replacementPeer, generation: 2)
        await harness.publishInboundMedia(packets: 100, bytes: 8_000)
        await harness.publishInboundMedia(packets: 101, bytes: 8_080)
        let stillRefused = await harness.snapshot()
        XCTAssertEqual(stillRefused.phase, .runtimeFailed)
        XCTAssertEqual(stillRefused.lastFailureCategory, .evidenceBridgeRefused)
        XCTAssertNil(stillRefused.currentAttemptID)
        XCTAssertNil(stillRefused.currentKey)
        XCTAssertFalse(stillRefused.exactTrackAdmitted)
        XCTAssertFalse(stillRefused.inboundMediaFresh)
        XCTAssertEqual(stillRefused.attemptGeneration, 1)
        XCTAssertEqual(factory.requestCount, 1)
        XCTAssertEqual(output.stopCount, 1)
        XCTAssertFalse(track.isEnabled)
        XCTAssertFalse(replacementTrack.isEnabled)
        XCTAssertEqual(replacementPeer.admissionCount, 0)
        XCTAssertEqual(unusedOutput.startCount, 0)
        XCTAssertEqual(unusedOutput.stopCount, 0)
        XCTAssertEqual(output.evidenceCallCounts, callsAfterRefusal)
        XCTAssertEqual(output.evidenceCorruptionCounts, expectedCorruptions)
        await harness.shutdown()
        watchdog.advance(to: UInt64.max)
        XCTAssertEqual(output.stopCount, 1)
    }

    private func prepare(
        harness: DriverTestHarness,
        epoch: UUID,
        peer: DriverTestPeer,
        track: DriverTestTrack
    ) async {
        await harness.beginMonitoring(epoch)
        await harness.replacePeer(peer, generation: 1)
        await harness.installTrack(track)
    }

    func testSharedClockParkingRetainsOneLeaseAcrossExactReacquisition() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled,
            lease: lease
        )
        let epoch = UUID()
        let deviceSnapshot = snapshot(
            epoch: epoch,
            generation: 1,
            available: true
        )

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(deviceSnapshot)
        guard case .selected(let selected) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 1
                ) else {
            return XCTFail("Expected the initial exact input lease.")
        }
        guard case .parked(let proof) =
                coordinator.parkForSharedClockEpochRecovery(
                    peerGeneration: 1
                ) else {
            return XCTFail("Expected a listener-bound parking proof.")
        }

        XCTAssertEqual(proof.leaseGeneration, selected.leaseGeneration)
        XCTAssertTrue(
            coordinator.sharedClockParkingProofIsCurrent(
                proof,
                peerGeneration: 1,
                snapshot: deviceSnapshot
            )
        )
        let ownedParkingEvent =
            BlackHoleDefaultInputLeaseUncertaintyEvent(
                leaseGeneration: proof.leaseGeneration,
                listenerRegistrationID:
                    proof.listenerRegistrationID,
                listenerSequence:
                    proof.acceptedListenerSequence
            )
        XCTAssertEqual(
            coordinator.defaultInputDidBecomeUncertain(
                ownedParkingEvent
            ),
            .noChange,
            "The parking write's listener event is already incorporated."
        )
        XCTAssertTrue(
            coordinator.sharedClockParkingProofIsCurrent(
                proof,
                peerGeneration: 1,
                snapshot: deviceSnapshot
            ),
            "An owned parking callback must not release the retained listener."
        )
        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            ),
            .degraded,
            "Ordinary admission cannot consume or release a recovery parking proof."
        )
        guard case .selected(let reacquired) =
                coordinator
                    .transportDidBecomeHealthyAfterSharedClockRecovery(
                        peerGeneration: 1,
                        parkingProof: proof
                    ) else {
            return XCTFail("Expected exact parked-listener reacquisition.")
        }
        XCTAssertEqual(reacquired.leaseGeneration, selected.leaseGeneration)
        XCTAssertEqual(lease.acquisitions.count, 1)
        XCTAssertEqual(lease.releases.count, 0)
    }

    func testSharedClockParkingExternalChoiceCannotBeReacquired() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled,
            lease: lease
        )
        let epoch = UUID()
        let deviceSnapshot = snapshot(
            epoch: epoch,
            generation: 1,
            available: true
        )
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(deviceSnapshot)
        _ = coordinator.transportDidBecomeHealthy(peerGeneration: 1)
        guard case .parked(let proof) =
                coordinator.parkForSharedClockEpochRecovery(
                    peerGeneration: 1
                ) else {
            return XCTFail("Expected a listener-bound parking proof.")
        }

        lease.invalidateParkingProof()

        XCTAssertFalse(
            coordinator.sharedClockParkingProofIsCurrent(
                proof,
                peerGeneration: 1,
                snapshot: deviceSnapshot
            )
        )
        XCTAssertEqual(
            coordinator
                .transportDidBecomeHealthyAfterSharedClockRecovery(
                    peerGeneration: 1,
                    parkingProof: proof
                ),
            .degraded
        )
        XCTAssertEqual(lease.acquisitions.count, 1)
        XCTAssertEqual(lease.releases.count, 1)
    }

    func testRetryableClockParkingCleanupIsRedrivenExactly() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [.retryableFailure, .released]
        )
        lease.makeNextClockEpochParkingRetryable()
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled,
            lease: lease
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(
                epoch: epoch,
                generation: 1,
                available: true
            )
        )
        guard case .selected(let selected) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 1
                ) else {
            return XCTFail("Expected the initial exact input lease.")
        }

        XCTAssertEqual(
            coordinator.parkForSharedClockEpochRecovery(
                peerGeneration: 1
            ),
            .degraded
        )
        XCTAssertEqual(lease.releases, [selected.leaseGeneration])
        XCTAssertEqual(
            coordinator.transportDidBecomeUnhealthy(
                peerGeneration: 1
            ),
            .released
        )
        XCTAssertEqual(
            lease.releases,
            [selected.leaseGeneration, selected.leaseGeneration],
            "The service-level redrive must clean only the retained generation."
        )
        XCTAssertEqual(lease.acquisitions.count, 1)
    }

    private func snapshot(
        epoch: UUID,
        generation: UInt64,
        available: Bool
    ) -> BlackHoleDeviceAvailabilitySnapshot {
        guard available else {
            return BlackHoleDeviceAvailabilitySnapshot(
                monitorEpoch: epoch,
                deviceGeneration: generation,
                defaultInputEndpoint: nil,
                hiddenMirrorSinkEndpoint: nil
            )
        }
        return BlackHoleDeviceAvailabilitySnapshot(
            monitorEpoch: epoch,
            deviceGeneration: generation,
            defaultInputEndpoint: .init(
                deviceID: 79,
                deviceUID: "com.elamin.opensteamer.virtual-microphone.input"
            ),
            hiddenMirrorSinkEndpoint: .init(
                deviceID: 89,
                deviceUID: "com.elamin.opensteamer.virtual-microphone.writer"
            )
        )
    }

    private func capturedSharedClockRejection()
        -> BlackHoleFaceTimeClockRejection {
        .insufficientSigned32Headroom(
            observation: BlackHoleFaceTimeClockObservation(
                deviceSampleTime: 6_687_779_444,
                deviceHostTime: 1,
                deviceSampleRate: 48_000,
                projectedFaceTimeSampleTime: 3_343_889_722
            ),
            maximumProjectedSampleTime:
                BlackHoleFaceTimeClockPolicy
                    .maximumProjectedSampleTime
        )
    }

    private func readyProgressSnapshots()
        -> [BlackHoleMicrophoneOutputProgressSnapshot] {
        [
            progress(
                callbacks: 1,
                requestedFrames: 480,
                successfulPulls: 1,
                successfulFrames: 480,
                silenceFallbacks: 0,
                silenceFrames: 0
            ),
            progress(
                callbacks: 2,
                requestedFrames: 960,
                successfulPulls: 2,
                successfulFrames: 960,
                silenceFallbacks: 0,
                silenceFrames: 0
            ),
        ]
    }

    private func progress(
        callbacks: UInt64,
        requestedFrames: UInt64,
        successfulPulls: UInt64,
        successfulFrames: UInt64,
        silenceFallbacks: UInt64,
        silenceFrames: UInt64,
        enqueueFailures: UInt64 = 0,
        lastEnqueueStatus: OSStatus = noErr
    ) -> BlackHoleMicrophoneOutputProgressSnapshot {
        BlackHoleMicrophoneOutputProgressSnapshot(
            queueRunning: true,
            postStartCallbackCount: callbacks,
            requestedFrameCount: requestedFrames,
            successfulPullCount: successfulPulls,
            successfulFrameCount: successfulFrames,
            silenceFallbackCount: silenceFallbacks,
            silenceFrameCount: silenceFrames,
            enqueueFailureCount: enqueueFailures,
            lastEnqueueStatus: lastEnqueueStatus
        )
    }

    private func eventually(
        attempts: Int = 1_000,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await condition()
    }
}

final class WorldwideBlackHoleDefaultInputCoordinatorTests:
    XCTestCase
{
    func testHiddenSinkIdentityChangeRebindsAtomicPairLease() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled,
            lease: lease
        )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.transportDidBecomeHealthy(peerGeneration: 1)
        guard case .selected(let first) = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        ) else {
            return XCTFail("Expected the validated pair to acquire the visible input lease")
        }

        let replacement = BlackHoleDeviceAvailabilitySnapshot(
            monitorEpoch: epoch,
            deviceGeneration: 2,
            defaultInputEndpoint: .init(
                deviceID: 79,
                deviceUID: "com.elamin.opensteamer.virtual-microphone.input"
            ),
            hiddenMirrorSinkEndpoint: .init(
                deviceID: 90,
                deviceUID: "com.elamin.opensteamer.virtual-microphone.writer"
            )
        )
        guard case .selected(let second) = coordinator
            .updateDeviceSnapshot(replacement) else {
            return XCTFail("Expected hidden-sink replacement to rebind the atomic pair")
        }

        XCTAssertNotEqual(first.leaseGeneration, second.leaseGeneration)
        XCTAssertEqual(lease.releases, [first.leaseGeneration])
        XCTAssertEqual(
            lease.acquisitions.map(\.targetUID),
            ["com.elamin.opensteamer.virtual-microphone.input", "com.elamin.opensteamer.virtual-microphone.input"]
        )
        XCTAssertEqual(
            lease.acquisitions.map(\.targetDeviceID),
            [79, 79]
        )
    }

    func testTransientPairRevalidationFailureReleasesAndSameGenerationCanRecover() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled,
            lease: lease
        )
        let epoch = UUID()
        let current = snapshot(epoch: epoch, generation: 1)

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.transportDidBecomeHealthy(peerGeneration: 1)
        guard case .selected(let first) = coordinator
            .updateDeviceSnapshot(current) else {
            return XCTFail("Expected the initial pair to acquire the lease")
        }

        XCTAssertEqual(
            coordinator.deviceRevalidationDidFail(),
            .degraded
        )
        XCTAssertEqual(lease.releases, [first.leaseGeneration])

        guard case .selected(let recovered) = coordinator
            .updateDeviceSnapshot(current) else {
            return XCTFail("Expected the same factual generation to recover after fresh validation")
        }
        XCTAssertNotEqual(first.leaseGeneration, recovered.leaseGeneration)
    }

    func testVisibleSameUIDReplacementPassesNewExactIdentityToLease() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled,
            lease: lease
        )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.transportDidBecomeHealthy(peerGeneration: 1)
        guard case .selected(let first) = coordinator
            .updateDeviceSnapshot(
                snapshot(epoch: epoch, generation: 1)
            ) else {
            return XCTFail("Expected initial exact visible endpoint selection")
        }

        let replacement = BlackHoleDeviceAvailabilitySnapshot(
            monitorEpoch: epoch,
            deviceGeneration: 2,
            defaultInputEndpoint: .init(
                deviceID: 80,
                deviceUID: "com.elamin.opensteamer.virtual-microphone.input"
            ),
            hiddenMirrorSinkEndpoint: .init(
                deviceID: 89,
                deviceUID: "com.elamin.opensteamer.virtual-microphone.writer"
            )
        )
        guard case .selected(let second) = coordinator
            .updateDeviceSnapshot(replacement) else {
            return XCTFail("Expected replacement exact visible endpoint selection")
        }

        XCTAssertEqual(first.deviceEndpoint.deviceID, 79)
        XCTAssertEqual(second.deviceEndpoint.deviceID, 80)
        XCTAssertEqual(
            lease.acquisitions.map(\.targetDeviceID),
            [79, 80]
        )
        XCTAssertEqual(
            lease.acquisitions.map(\.targetUID),
            ["com.elamin.opensteamer.virtual-microphone.input", "com.elamin.opensteamer.virtual-microphone.input"]
        )
        XCTAssertEqual(lease.releases, [first.leaseGeneration])
    }

    func testHigherPairGenerationRebindsWhenCoreAudioReusesEndpointIDs() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled,
            lease: lease
        )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.transportDidBecomeHealthy(peerGeneration: 1)
        guard case .selected(let first) = coordinator
            .updateDeviceSnapshot(
                snapshot(epoch: epoch, generation: 1)
            ) else {
            return XCTFail("Expected the initial pair generation to acquire")
        }

        guard case .selected(let second) = coordinator
            .updateDeviceSnapshot(
                snapshot(epoch: epoch, generation: 2)
            ) else {
            return XCTFail(
                "A listener-proven endpoint reincarnation must rebind even when Core Audio reused both IDs"
            )
        }

        XCTAssertNotEqual(first.leaseGeneration, second.leaseGeneration)
        XCTAssertEqual(first.deviceEndpoint, second.deviceEndpoint)
        XCTAssertEqual(lease.releases, [first.leaseGeneration])
        XCTAssertEqual(
            lease.acquisitions.map(\.targetDeviceID),
            [79, 79]
        )
    }

    func testAudioRoutingCleanupPolicyRedrivesBothOwnersAfterOneExhaustedEpisode()
    {
        var defaultInputOutcomes:
            [WorldwideBlackHoleDefaultInputOutcome] = [
                .degraded,
                .released,
            ]
        var monitorOutcomes:
            [BlackHoleDeviceAvailabilityMonitorStopResult] = [
                .retryableFailure,
                .stopped,
            ]
        var defaultInputCallCount = 0
        var monitorCallCount = 0

        let result =
            WorldwideBlackHoleAudioRoutingCleanupPolicy.run(
                maximumEpisodeCount: 3,
                shutdownDefaultInput: {
                    defaultInputCallCount += 1
                    return defaultInputOutcomes.removeFirst()
                },
                stopDeviceMonitor: {
                    monitorCallCount += 1
                    return monitorOutcomes.removeFirst()
                }
            )

        XCTAssertEqual(result, .cleaned)
        XCTAssertEqual(
            defaultInputCallCount,
            2,
            "The same production shutdown initiation must redrive default-input cleanup after one exhausted episode."
        )
        XCTAssertEqual(
            monitorCallCount,
            2,
            "The same production shutdown initiation must redrive exact device-list listener removal after one exhausted episode."
        )
    }

    func testAudioRoutingCleanupPolicyCallsCompletedHalfIdempotentlyWhileOtherHalfRecovers()
    {
        var defaultInputOutcomes:
            [WorldwideBlackHoleDefaultInputOutcome] = [
                .released,
                .noChange,
            ]
        var monitorOutcomes:
            [BlackHoleDeviceAvailabilityMonitorStopResult] = [
                .retryableFailure,
                .stopped,
            ]
        var defaultInputCallCount = 0
        var monitorCallCount = 0

        let result =
            WorldwideBlackHoleAudioRoutingCleanupPolicy.run(
                maximumEpisodeCount: 2,
                shutdownDefaultInput: {
                    defaultInputCallCount += 1
                    return defaultInputOutcomes.removeFirst()
                },
                stopDeviceMonitor: {
                    monitorCallCount += 1
                    return monitorOutcomes.removeFirst()
                }
            )

        XCTAssertEqual(result, .cleaned)
        XCTAssertEqual(defaultInputCallCount, 2)
        XCTAssertEqual(monitorCallCount, 2)
    }

    func testAudioRoutingCleanupPolicyIsBoundedAndReportsPersistentDegradation()
    {
        var defaultInputCallCount = 0
        var monitorCallCount = 0

        let result =
            WorldwideBlackHoleAudioRoutingCleanupPolicy.run(
                maximumEpisodeCount: 2,
                shutdownDefaultInput: {
                    defaultInputCallCount += 1
                    return .degraded
                },
                stopDeviceMonitor: {
                    monitorCallCount += 1
                    return .retryableFailure
                }
            )

        XCTAssertEqual(result, .degraded)
        XCTAssertEqual(defaultInputCallCount, 2)
        XCTAssertEqual(monitorCallCount, 2)
    }

    func testRetainedCleanupRedriveUsesOneGlobalRoundRobinBudget()
    {
        let retainer =
            WorldwideBlackHoleAudioRoutingCleanupRetainer()
        let first = CleanupAttemptProbe(
            results: [false, true]
        )
        let second = CleanupAttemptProbe(
            results: [false]
        )

        retainer.retain(id: UUID()) {
            first.attempt()
        }
        retainer.retain(id: UUID()) {
            second.attempt()
        }
        XCTAssertEqual(retainer.retainedJobCount, 2)

        XCTAssertEqual(
            retainer.redriveRetained(
                maximumAttemptCount: 1
            ),
            2
        )
        XCTAssertEqual(first.attemptCount, 1)
        XCTAssertEqual(second.attemptCount, 0)

        _ = retainer.redriveRetained(
            maximumAttemptCount: 1
        )
        XCTAssertEqual(first.attemptCount, 1)
        XCTAssertEqual(second.attemptCount, 1)

        XCTAssertEqual(
            retainer.redriveRetained(
                maximumAttemptCount: 1
            ),
            1,
            "A completed owner is removed while the independently degraded owner remains retained."
        )
        XCTAssertEqual(first.attemptCount, 2)
        XCTAssertEqual(second.attemptCount, 1)
    }

    func testDeviceBeforeConnectionSelectsAtHealthyBoundaryWithoutTrack() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        let deviceResult =
            coordinator.updateDeviceSnapshot(
                snapshot(epoch: epoch, generation: 1)
            )
        XCTAssertEqual(
            deviceResult,
            .noChange
        )
        let result =
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 7
            )

        guard case .selected(let key) = result else {
            return XCTFail("Expected connection-level selection")
        }
        XCTAssertEqual(key.peerGeneration, 7)
        XCTAssertEqual(key.deviceGeneration, 1)
        XCTAssertEqual(key.deviceEndpoint.deviceID, 79)
        XCTAssertEqual(key.deviceEndpoint.deviceUID, "com.elamin.opensteamer.virtual-microphone.input")
        XCTAssertEqual(lease.acquisitions.count, 1)
        XCTAssertEqual(lease.acquisitions[0].targetDeviceID, 79)
    }

    func testConnectionBeforeDeviceSelectsFirstCurrentAvailableGeneration() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        let healthyWithoutDevice =
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 3
            )
        XCTAssertEqual(
            healthyWithoutDevice,
            .waitingForMonitor
        )
        XCTAssertEqual(lease.acquisitions.count, 0)

        let result = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        guard case .selected = result else {
            return XCTFail("Expected selection on device appearance")
        }
        XCTAssertEqual(lease.acquisitions.count, 1)
    }

    func testRemovalRestoresAndReinstallUsesFreshLeaseGeneration() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        let firstGeneration =
            lease.acquisitions[0].generation

        _ = coordinator.updateDeviceSnapshot(
            BlackHoleDeviceAvailabilitySnapshot(
                monitorEpoch: epoch,
                deviceGeneration: 2,
                defaultInputEndpoint: nil,
                hiddenMirrorSinkEndpoint: nil
            )
        )
        XCTAssertEqual(lease.releases, [firstGeneration])

        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 3)
        )
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertNotEqual(
            lease.acquisitions[1].generation,
            firstGeneration
        )
    }

    func testStalePeerCannotReleaseReplacementConnection() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )
        _ = coordinator.invalidateCurrentConnection()
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 2
        )
        let replacementGeneration =
            lease.acquisitions.last!.generation
        let releaseCount = lease.releases.count

        _ = coordinator.transportDidBecomeUnhealthy(
            peerGeneration: 1
        )

        XCTAssertEqual(lease.releases.count, releaseCount)
        XCTAssertNotEqual(
            lease.releases.last,
            replacementGeneration
        )
    }

    func testStaleHealthyPeerCannotReplaceOrResurrectAfterNewerConnection() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )
        let firstGeneration =
            lease.acquisitions[0].generation

        let replacement =
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 2
            )
        guard case .selected(let replacementKey) =
                replacement else {
            return XCTFail(
                "Expected the newer peer generation to replace the first connection"
            )
        }
        XCTAssertEqual(replacementKey.peerGeneration, 2)
        XCTAssertEqual(lease.acquisitions.count, 2)
        let replacementGeneration =
            lease.acquisitions[1].generation
        XCTAssertEqual(
            lease.releases,
            [firstGeneration]
        )

        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            ),
            .noChange,
            "A stale healthy callback must not release or replace the newer connection."
        )
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertEqual(
            lease.releases,
            [firstGeneration]
        )

        XCTAssertEqual(
            coordinator.transportDidBecomeUnhealthy(
                peerGeneration: 2
            ),
            .released
        )
        XCTAssertEqual(
            lease.releases,
            [firstGeneration, replacementGeneration]
        )

        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            ),
            .noChange,
            "A stale healthy callback must not resurrect an older peer after the replacement disconnects."
        )
        XCTAssertEqual(lease.acquisitions.count, 2)

        let samePeerRecovery =
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 2
            )
        guard case .selected(let recoveryKey) =
                samePeerRecovery else {
            return XCTFail(
                "The newest peer generation must remain eligible for a fresh connection boundary"
            )
        }
        XCTAssertEqual(recoveryKey.peerGeneration, 2)
        XCTAssertEqual(lease.acquisitions.count, 3)
        XCTAssertNotEqual(
            recoveryKey.leaseGeneration,
            replacementGeneration
        )
    }

    func testLANCoexistenceSuppressesDefaultInputLease() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .suppressedForLANCoexistence,
                lease: lease
            )
        let epoch = UUID()

        XCTAssertEqual(
            coordinator.beginMonitoring(epoch: epoch),
            .suppressed
        )
        let healthyResult =
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            )
        XCTAssertEqual(
            healthyResult,
            .suppressed
        )
        XCTAssertEqual(lease.acquisitions.count, 0)
    }

    func testSynchronousPreWriteRetryReusesExactLeaseGenerationAndBaseline() {
        let lease = DefaultInputCoordinatorLeaseFake(
            acquisitionResults: [
                .retryableFailure,
                .acquired,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease,
                maximumAcquisitionAttemptCount: 3
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        let result =
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 4
            )

        guard case .selected(let key) = result else {
            return XCTFail("Expected retry to confirm default input")
        }
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertEqual(
            lease.acquisitions[0].generation,
            lease.acquisitions[1].generation,
            "Retryable pre-write failure must reuse the exact lease generation and captured baseline."
        )
        XCTAssertTrue(
            lease.releases.isEmpty,
            "A retryable pre-write failure did not acquire ownership and must not release its generation between attempts."
        )
        XCTAssertEqual(
            key.leaseGeneration,
            lease.acquisitions[1].generation
        )
    }

    func testAcquireRetryBudgetIsBoundedForExactIdentity() {
        let lease = DefaultInputCoordinatorLeaseFake(
            acquisitionResults: [
                .retryableFailure,
                .retryableFailure,
                .retryableFailure,
                .retryableFailure,
                .retryableFailure,
                .acquired,
            ],
            releaseResults: [
                .retryableFailure,
                .released,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease,
                maximumAcquisitionAttemptCount: 3,
                maximumReleaseAttemptCount: 1
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        let exhausted =
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            )
        XCTAssertEqual(exhausted, .degraded)
        guard lease.acquisitions.count == 3 else {
            return XCTFail(
                "The first healthy callback must consume exactly the bounded three-attempt acquisition budget."
            )
        }

        let exhaustedGeneration =
            lease.acquisitions[0].generation
        XCTAssertEqual(
            lease.acquisitions.map(\.generation),
            [
                exhaustedGeneration,
                exhaustedGeneration,
                exhaustedGeneration,
            ],
            "All retryable acquisition attempts must reuse one exact lease generation."
        )
        XCTAssertEqual(
            lease.releases,
            [exhaustedGeneration],
            "Budget exhaustion must immediately perform exactly one bounded release attempt for the same generation."
        )
        XCTAssertEqual(
            lease.events,
            [
                .acquisition(exhaustedGeneration),
                .acquisition(exhaustedGeneration),
                .acquisition(exhaustedGeneration),
                .release(exhaustedGeneration),
            ],
            "The exact cleanup attempt must occur only after all three acquisitions, never between them."
        )

        let repeated =
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            )
        XCTAssertEqual(repeated, .degraded)
        XCTAssertEqual(
            lease.releases,
            [
                exhaustedGeneration,
                exhaustedGeneration,
            ],
            "A duplicate healthy callback must redrive the pending exact release on the same generation."
        )
        XCTAssertEqual(
            lease.acquisitions.count,
            3,
            "Cleanup completion must not perform a fourth acquisition or bypass the exhausted identity budget."
        )
        XCTAssertEqual(
            lease.events,
            [
                .acquisition(exhaustedGeneration),
                .acquisition(exhaustedGeneration),
                .acquisition(exhaustedGeneration),
                .release(exhaustedGeneration),
                .release(exhaustedGeneration),
            ]
        )

        XCTAssertEqual(
            coordinator.updateDeviceSnapshot(
                snapshot(epoch: epoch, generation: 1)
            ),
            .noChange,
            "A duplicate snapshot from the same generation must remain idempotent."
        )
        XCTAssertEqual(lease.acquisitions.count, 3)

        XCTAssertEqual(
            coordinator.updateDeviceSnapshot(
                BlackHoleDeviceAvailabilitySnapshot(
                    monitorEpoch: epoch,
                    deviceGeneration: 3,
                    defaultInputEndpoint: nil,
                    hiddenMirrorSinkEndpoint: nil
                )
            ),
            .waitingForDevice,
            "After exact cleanup completes, factual removal must report waitingForDevice."
        )

        let result = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 4)
        )
        guard case .selected(let replacementKey) = result else {
            return XCTFail(
                "Removal and reappearance must receive a fresh bounded acquisition budget."
            )
        }
        XCTAssertEqual(lease.acquisitions.count, 6)
        XCTAssertNotEqual(
            replacementKey.leaseGeneration,
            exhaustedGeneration,
            "Reappearance must mint a different exact lease generation."
        )
        XCTAssertEqual(
            lease.acquisitions.suffix(3).map(\.generation),
            [
                replacementKey.leaseGeneration,
                replacementKey.leaseGeneration,
                replacementKey.leaseGeneration,
            ],
            "The reappeared identity must receive a fresh three-attempt budget on its new generation."
        )
        XCTAssertEqual(
            lease.events,
            [
                .acquisition(exhaustedGeneration),
                .acquisition(exhaustedGeneration),
                .acquisition(exhaustedGeneration),
                .release(exhaustedGeneration),
                .release(exhaustedGeneration),
                .acquisition(
                    replacementKey.leaseGeneration
                ),
                .acquisition(
                    replacementKey.leaseGeneration
                ),
                .acquisition(
                    replacementKey.leaseGeneration
                ),
            ]
        )
    }

    func testTerminalAcquireFailureCannotRetryUntilNewConnection() {
        let lease = DefaultInputCoordinatorLeaseFake(
            acquisitionResults: [
                .terminalFailure,
                .acquired,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease,
                maximumAcquisitionAttemptCount: 3
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            ),
            .degraded
        )
        XCTAssertEqual(lease.acquisitions.count, 1)

        XCTAssertEqual(
            coordinator.updateDeviceSnapshot(
                snapshot(epoch: epoch, generation: 2)
            ),
            .degraded
        )
        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            ),
            .degraded
        )
        XCTAssertEqual(
            lease.acquisitions.count,
            1,
            "A terminal lease generation must never reassert over an external choice."
        )

        _ = coordinator.invalidateCurrentConnection()
        let replacement =
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 2
            )
        guard case .selected(let key) = replacement else {
            return XCTFail("A new connection must receive a new lease generation")
        }
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertNotEqual(
            lease.acquisitions[0].generation,
            key.leaseGeneration
        )
    }

    func testTerminalAcquireCleanupIsRedrivenByDuplicateHealthyCallback() {
        let lease = DefaultInputCoordinatorLeaseFake(
            acquisitionResults: [
                .terminalFailure,
            ],
            releaseResults: [
                .retryableFailure,
                .released,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease,
                maximumAcquisitionAttemptCount: 3,
                maximumReleaseAttemptCount: 1
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )

        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            ),
            .degraded
        )
        XCTAssertEqual(lease.acquisitions.count, 1)
        let generation = lease.acquisitions[0].generation
        XCTAssertEqual(lease.releases, [generation])

        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            ),
            .degraded,
            "A terminal connection must still redrive retained cleanup ownership."
        )
        XCTAssertEqual(
            lease.releases,
            [generation, generation]
        )
        XCTAssertEqual(
            lease.acquisitions.count,
            1,
            "Cleanup completion must not reacquire on the terminal connection."
        )

        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            ),
            .degraded
        )
        XCTAssertEqual(
            lease.releases,
            [generation, generation]
        )
        XCTAssertEqual(lease.acquisitions.count, 1)
    }

    func testFailedRestoreIsRetainedAndRedrivenByDuplicateUnhealthyCallback() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [
                .retryableFailure,
                .released,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease,
                maximumReleaseAttemptCount: 1
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )
        let generation = lease.acquisitions[0].generation

        XCTAssertEqual(
            coordinator.transportDidBecomeUnhealthy(
                peerGeneration: 1
            ),
            .degraded
        )
        XCTAssertEqual(lease.releases, [generation])

        XCTAssertEqual(
            coordinator.transportDidBecomeUnhealthy(
                peerGeneration: 1
            ),
            .released
        )
        XCTAssertEqual(
            lease.releases,
            [generation, generation]
        )
    }

    func testSingleShutdownRedrivesPendingReleaseWithoutSecondExternalCallback()
    {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [
                .retryableFailure,
                .released,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease,
                maximumReleaseAttemptCount: 1,
                maximumShutdownAttemptCount: 2
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )

        XCTAssertEqual(
            coordinator.shutdown(),
            .released
        )
        XCTAssertEqual(
            lease.releases.count,
            2,
            "One shutdown initiation must internally redrive retained route and listener cleanup."
        )
        XCTAssertEqual(lease.shutdownCallCount, 1)
    }

    func testSingleShutdownRetriesRetryableLeaseShutdownWithinSameBoundedPolicy()
    {
        let lease = DefaultInputCoordinatorLeaseFake(
            shutdownResults: [
                .retryableFailure,
                .released,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease,
                maximumReleaseAttemptCount: 1,
                maximumShutdownAttemptCount: 2
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )

        XCTAssertEqual(
            coordinator.shutdown(),
            .released
        )
        XCTAssertEqual(lease.releases.count, 1)
        XCTAssertEqual(
            lease.shutdownCallCount,
            2,
            "A retryable lease shutdown must be redriven without another production stop callback."
        )
    }

    func testShutdownPermanentExhaustionIsBoundedAndRetainedForLaterExplicitRetry()
    {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [
                .retryableFailure,
                .retryableFailure,
                .released,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease,
                maximumReleaseAttemptCount: 1,
                maximumShutdownAttemptCount: 2
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )

        XCTAssertEqual(
            coordinator.shutdown(),
            .degraded
        )
        XCTAssertEqual(
            lease.releases.count,
            2,
            "One shutdown invocation must stop at its configured bound."
        )
        XCTAssertEqual(lease.shutdownCallCount, 0)

        XCTAssertEqual(
            coordinator.shutdown(),
            .released,
            "A later explicit coordinator shutdown must retain and complete the same cleanup ownership."
        )
        XCTAssertEqual(lease.releases.count, 3)
        XCTAssertEqual(lease.shutdownCallCount, 1)
    }

    func testExternalChoiceDuringRemovalTerminalizesCurrentConnection() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [
                .externallySuperseded,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )

        XCTAssertEqual(
            coordinator.updateDeviceSnapshot(
                BlackHoleDeviceAvailabilitySnapshot(
                    monitorEpoch: epoch,
                    deviceGeneration: 2,
                    defaultInputEndpoint: nil,
                    hiddenMirrorSinkEndpoint: nil
                )
            ),
            .released
        )
        XCTAssertEqual(
            coordinator.updateDeviceSnapshot(
                snapshot(epoch: epoch, generation: 3)
            ),
            .degraded
        )
        XCTAssertEqual(
            lease.acquisitions.count,
            1,
            "Device reappearance must not reassert over an external choice in the same connection."
        )
    }

    func testUnchangedIdentityChurnDoesNotReleaseOrReacquire() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )

        for _ in 0..<512 {
            XCTAssertEqual(
                coordinator.updateDeviceSnapshot(
                    snapshot(
                        epoch: epoch,
                        generation: 1
                    )
                ),
                .noChange
            )
        }

        XCTAssertEqual(lease.acquisitions.count, 1)
        XCTAssertTrue(lease.releases.isEmpty)
    }

    func testPostAdmissionExternalDefaultInputEventRevokesAndCannotReassertSameConnection() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [.externallySuperseded]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        guard case .selected(let admitted) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 1
                ) else {
            return XCTFail("Expected exact default-input admission")
        }

        guard case .selected(let refreshed) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 1
                ) else {
            return XCTFail(
                "The same-key path must return a freshly verified proof"
            )
        }
        XCTAssertEqual(
            admitted.leaseGeneration,
            refreshed.leaseGeneration
        )
        XCTAssertGreaterThanOrEqual(
            lease.authorizationProofCallCount,
            2
        )

        let incorporatedEvent =
            BlackHoleDefaultInputLeaseUncertaintyEvent(
                leaseGeneration: refreshed.leaseGeneration,
                listenerRegistrationID:
                    refreshed.inputAuthorization
                        .listenerRegistrationID,
                listenerSequence:
                    refreshed.inputAuthorization
                        .acceptedListenerSequence
            )
        XCTAssertEqual(
            coordinator.defaultInputDidBecomeUncertain(
                incorporatedEvent
            ),
            .noChange
        )
        XCTAssertTrue(lease.releases.isEmpty)

        let externalEvent =
            BlackHoleDefaultInputLeaseUncertaintyEvent(
                leaseGeneration: refreshed.leaseGeneration,
                listenerRegistrationID:
                    refreshed.inputAuthorization
                        .listenerRegistrationID,
                listenerSequence:
                    refreshed.inputAuthorization
                        .acceptedListenerSequence + 1
            )
        XCTAssertEqual(
            coordinator.defaultInputDidBecomeUncertain(externalEvent),
            .degraded
        )
        XCTAssertEqual(lease.releases, [refreshed.leaseGeneration])
        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 1
            ),
            .degraded,
            "The same connection must not overwrite the external choice."
        )
        XCTAssertEqual(lease.acquisitions.count, 1)
    }

    func testExternalDefaultInputFenceSurvivesSamePeerReconnectAndRepeatedRedrives()
    {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [.externallySuperseded]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        guard case .selected(let admitted) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 1
                ) else {
            return XCTFail("Expected exact default-input admission")
        }

        let externalEvent =
            BlackHoleDefaultInputLeaseUncertaintyEvent(
                leaseGeneration: admitted.leaseGeneration,
                listenerRegistrationID:
                    admitted.inputAuthorization
                        .listenerRegistrationID,
                listenerSequence:
                    admitted.inputAuthorization
                        .acceptedListenerSequence + 1
            )
        XCTAssertEqual(
            coordinator.defaultInputDidBecomeUncertain(
                externalEvent
            ),
            .degraded
        )
        XCTAssertEqual(
            coordinator.transportDidBecomeUnhealthy(
                peerGeneration: 1
            ),
            .noChange
        )

        for generation in UInt64(2)...UInt64(13) {
            XCTAssertEqual(
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 1
                ),
                .degraded
            )
            XCTAssertEqual(
                coordinator.updateDeviceSnapshot(
                    snapshot(
                        epoch: epoch,
                        generation: generation
                    )
                ),
                .noChange
            )
            _ = coordinator.invalidateCurrentConnection()
        }

        XCTAssertEqual(
            lease.acquisitions.count,
            1,
            "The externally superseded peer must perform zero reacquisitions across same-peer health, snapshot, and invalidation redrives."
        )

        guard case .selected(let replacement) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 2
                ) else {
            return XCTFail(
                "Only a strictly newer peer may clear the external-selector fence"
            )
        }
        XCTAssertEqual(replacement.peerGeneration, 2)
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertNotEqual(
            admitted.leaseGeneration,
            replacement.leaseGeneration
        )
    }

    func testStaleOldRegistrationEventCannotPoisonReplacementPeer() {
        let lease = DefaultInputCoordinatorLeaseFake()
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        guard case .selected(let first) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 1
                ),
              case .selected(let replacement) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 2
                ) else {
            return XCTFail("Expected a replacement peer lease")
        }

        let staleEvent =
            BlackHoleDefaultInputLeaseUncertaintyEvent(
                leaseGeneration: first.leaseGeneration,
                listenerRegistrationID:
                    first.inputAuthorization
                        .listenerRegistrationID,
                listenerSequence:
                    first.inputAuthorization
                        .acceptedListenerSequence + 1
            )
        XCTAssertEqual(
            coordinator.defaultInputDidBecomeUncertain(
                staleEvent
            ),
            .noChange
        )
        let currentLeaseOldRegistrationEvent =
            BlackHoleDefaultInputLeaseUncertaintyEvent(
                leaseGeneration:
                    replacement.leaseGeneration,
                listenerRegistrationID:
                    first.inputAuthorization
                        .listenerRegistrationID,
                listenerSequence:
                    replacement.inputAuthorization
                        .acceptedListenerSequence + 1
            )
        let oldLeaseCurrentRegistrationEvent =
            BlackHoleDefaultInputLeaseUncertaintyEvent(
                leaseGeneration: first.leaseGeneration,
                listenerRegistrationID:
                    replacement.inputAuthorization
                        .listenerRegistrationID,
                listenerSequence:
                    replacement.inputAuthorization
                        .acceptedListenerSequence + 1
            )
        XCTAssertEqual(
            coordinator.defaultInputDidBecomeUncertain(
                currentLeaseOldRegistrationEvent
            ),
            .noChange
        )
        XCTAssertEqual(
            coordinator.defaultInputDidBecomeUncertain(
                oldLeaseCurrentRegistrationEvent
            ),
            .noChange
        )
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertEqual(lease.releases.count, 1)

        guard case .selected(let refreshed) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 2
                ) else {
            return XCTFail(
                "The stale registration must not terminalize the replacement"
            )
        }
        XCTAssertEqual(
            refreshed.leaseGeneration,
            replacement.leaseGeneration
        )
        XCTAssertEqual(lease.acquisitions.count, 2)
    }

    func testStalePeerReleaseCannotClearPendingReplacementConnection() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [
                .retryableFailure,
                .released,
            ]
        )
        let coordinator =
            WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled,
                lease: lease,
                maximumReleaseAttemptCount: 1
            )
        let epoch = UUID()

        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 1)
        )
        _ = coordinator.transportDidBecomeHealthy(
            peerGeneration: 1
        )

        XCTAssertEqual(
            coordinator.transportDidBecomeHealthy(
                peerGeneration: 2
            ),
            .degraded
        )

        let replacement =
            coordinator.transportDidBecomeUnhealthy(
                peerGeneration: 1
            )
        guard case .selected(let key) = replacement else {
            return XCTFail(
                "Successful stale cleanup must immediately drive the already-recorded healthy replacement."
            )
        }
        XCTAssertEqual(key.peerGeneration, 2)
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertNotEqual(
            lease.acquisitions[0].generation,
            lease.acquisitions[1].generation
        )
        XCTAssertEqual(
            lease.acquisitions.count,
            2
        )
        guard case .selected(let refreshed) =
                coordinator.transportDidBecomeHealthy(
                    peerGeneration: 2
                ) else {
            return XCTFail(
                "The replacement must return a fresh same-key proof."
            )
        }
        XCTAssertEqual(refreshed.leaseGeneration, key.leaseGeneration)
        XCTAssertEqual(lease.acquisitions.count, 2)
    }

    func testRustInputLeaseAdmissionPreservesClampedOneAndLiteralThreeBudgets() {
        for configuredMaximum in [0, 1, 3] {
            let actualMaximum = configuredMaximum == 3 ? 3 : 1
            let lease = DefaultInputCoordinatorLeaseFake(
                acquisitionResults: Array(repeating: .retryableFailure, count: 8)
            )
            let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled, lease: lease,
                maximumAcquisitionAttemptCount: configuredMaximum,
                maximumReleaseAttemptCount: 1
            )
            let epoch = UUID()
            _ = coordinator.beginMonitoring(epoch: epoch)
            _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
            XCTAssertEqual(lease.acquisitions.count, actualMaximum)
            XCTAssertEqual(lease.authorizationProofCallCount, 0)
            guard let generation = lease.acquisitions.first?.generation else {
                return XCTFail("Expected the original bounded acquisition episode")
            }
            XCTAssertEqual(lease.acquisitions.map(\.generation),
                Array(repeating: generation, count: actualMaximum))
            XCTAssertEqual(lease.events,
                Array(repeating: .acquisition(generation), count: actualMaximum) + [.release(generation)])
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
            XCTAssertEqual(lease.acquisitions.count, actualMaximum,
                "A completed cleanup must not reset the exhausted exact identity")
            XCTAssertEqual(lease.releases, [generation])
        }
    }

    func testRustInputLeaseNativeOutcomeKeepsProofLazyAndTerminalCleanupExact() {
        let lease = DefaultInputCoordinatorLeaseFake(
            acquisitionResults: [.retryableFailure, .terminalFailure, .acquired]
        )
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease,
            maximumAcquisitionAttemptCount: 3, maximumReleaseAttemptCount: 1
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
        XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertEqual(lease.authorizationProofCallCount, 0,
            "Neither retryable nor terminal acquisition may query native authorization")
        guard let firstGeneration = lease.acquisitions.first?.generation else {
            return XCTFail("Expected exact native attempt identity")
        }
        XCTAssertEqual(lease.events, [.acquisition(firstGeneration),
            .acquisition(firstGeneration), .release(firstGeneration)])
        XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
        XCTAssertEqual(lease.acquisitions.count, 2)
        guard case .selected(let replacement) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 2) else {
            return XCTFail("Only a genuinely newer peer may acquire after the terminal episode")
        }
        XCTAssertNotEqual(replacement.leaseGeneration, firstGeneration)
        XCTAssertEqual(lease.acquisitions.count, 3)
        XCTAssertEqual(lease.authorizationProofCallCount, 1)
        XCTAssertEqual(lease.events, [.acquisition(firstGeneration),
            .acquisition(firstGeneration), .release(firstGeneration),
            .acquisition(replacement.leaseGeneration)])
    }

    func testRustInputLeaseReleaseVoteKeepsOneExactCleanupEpisodeAndExternalFence() {
        let cases: [[BlackHoleDefaultInputLeaseReleaseResult]] = [
            [.retryableFailure, .retryableFailure, .released], [.externallySuperseded],
        ]
        for nativeResults in cases {
            let lease = DefaultInputCoordinatorLeaseFake(releaseResults: nativeResults)
            let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled, lease: lease, maximumReleaseAttemptCount: 3
            )
            let epoch = UUID()
            _ = coordinator.beginMonitoring(epoch: epoch)
            _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
            guard case .selected(let selected) =
                    coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
                return XCTFail("Expected one genuine acquired native key")
            }
            XCTAssertEqual(lease.authorizationProofCallCount, 1)
            XCTAssertEqual(coordinator.transportDidBecomeUnhealthy(peerGeneration: 1), .released)
            let expectedCalls = nativeResults.count
            XCTAssertEqual(lease.releases,
                Array(repeating: selected.leaseGeneration, count: expectedCalls))
            XCTAssertEqual(lease.events, [.acquisition(selected.leaseGeneration)]
                + Array(repeating: .release(selected.leaseGeneration), count: expectedCalls))
            XCTAssertEqual(lease.acquisitions.count, 1)
            XCTAssertEqual(coordinator.transportDidBecomeUnhealthy(peerGeneration: 1), .noChange)
            XCTAssertEqual(lease.releases.count, expectedCalls)
            if nativeResults.first == .externallySuperseded {
                XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
                XCTAssertEqual(lease.acquisitions.count, 1,
                    "An external selector fence cannot be cleared by the same peer")
                XCTAssertEqual(lease.authorizationProofCallCount, 1)
            }
        }
    }

    func testRustInputLeaseRetainedCleanupRedrivesOnSameHealthyIdentityWithoutReadmission() {
        for terminal in [false, true] {
            let nativeAcquisitions: [BlackHoleDefaultInputLeaseAcquisitionResult] = terminal
                ? [.terminalFailure, .acquired]
                : [.retryableFailure, .retryableFailure, .retryableFailure, .acquired]
            let lease = DefaultInputCoordinatorLeaseFake(
                acquisitionResults: nativeAcquisitions,
                releaseResults: [.retryableFailure, .retryableFailure, .released]
            )
            let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled, lease: lease,
                maximumAcquisitionAttemptCount: 3, maximumReleaseAttemptCount: 1
            )
            let epoch = UUID()
            _ = coordinator.beginMonitoring(epoch: epoch)
            _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
            let expectedAcquisitions = terminal ? 1 : 3
            XCTAssertEqual(lease.acquisitions.count, expectedAcquisitions)
            guard let retainedGeneration = lease.acquisitions.first?.generation else {
                return XCTFail("Expected exact native pending cleanup ownership")
            }
            XCTAssertEqual(lease.authorizationProofCallCount, 0)
            XCTAssertEqual(lease.releases, [retainedGeneration])
            for releaseCount in [2, 3] {
                XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
                XCTAssertEqual(lease.releases, Array(repeating: retainedGeneration, count: releaseCount))
                XCTAssertEqual(lease.acquisitions.count, expectedAcquisitions,
                    "The pending-release branch must run before any same-identity admission")
                XCTAssertEqual(lease.authorizationProofCallCount, 0)
            }
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
            XCTAssertEqual(lease.releases.count, 3)
            XCTAssertEqual(lease.acquisitions.count, expectedAcquisitions)
            guard case .selected(let next) =
                    coordinator.transportDidBecomeHealthy(peerGeneration: 2) else {
                return XCTFail("A healthy-policy newer peer may acquire only after actual release")
            }
            XCTAssertNotEqual(next.leaseGeneration, retainedGeneration)
            XCTAssertEqual(lease.acquisitions.count, expectedAcquisitions + 1)
            XCTAssertEqual(lease.authorizationProofCallCount, 1)
            XCTAssertEqual(lease.events,
                Array(repeating: .acquisition(retainedGeneration), count: expectedAcquisitions)
                + Array(repeating: .release(retainedGeneration), count: 3)
                + [.acquisition(next.leaseGeneration)])
        }
    }

    func testNativeReleaseProtectionRetainsNestedUncertaintyAndExactPendingCleanup() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [.released, .retryableFailure, .released]
        )
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease, maximumReleaseAttemptCount: 1
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
        guard case .selected(let original) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Expected the original exact-listener owner")
        }
        let event = BlackHoleDefaultInputLeaseUncertaintyEvent(
            leaseGeneration: original.leaseGeneration,
            listenerRegistrationID: original.inputAuthorization.listenerRegistrationID,
            listenerSequence: original.inputAuthorization.acceptedListenerSequence + 1
        )
        var nestedOutcome: WorldwideBlackHoleDefaultInputOutcome?
        lease.onNextRelease = {
            nestedOutcome = coordinator.defaultInputDidBecomeUncertain(event)
        }
        XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 2), .degraded)
        XCTAssertEqual(nestedOutcome, .degraded)
        XCTAssertEqual(lease.acquisitions.count, 1,
            "Old released result must not bypass the nested uncertainty protection and admit peer two")
        XCTAssertEqual(lease.releases, [original.leaseGeneration, original.leaseGeneration])
        XCTAssertEqual(coordinator.updateDeviceSnapshot(
            snapshot(epoch: epoch, generation: 2)), .degraded,
            "Fresh drive for the retained original healthy peer must keep its external-selector fence")
        XCTAssertEqual(lease.acquisitions.count, 1)
        XCTAssertEqual(lease.releases.count, 2)
        XCTAssertEqual(coordinator.invalidateCurrentConnection(), .released)
        XCTAssertEqual(lease.releases,
            [original.leaseGeneration, original.leaseGeneration, original.leaseGeneration],
            "Only truthful fresh cleanup of the retained original generation may clear its key")
        XCTAssertEqual(lease.events, [.acquisition(original.leaseGeneration),
            .release(original.leaseGeneration), .release(original.leaseGeneration),
            .release(original.leaseGeneration)])
        XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .noChange)
        XCTAssertEqual(lease.acquisitions.count, 1)
    }

    func testNativeReleaseContextRetainsNestedNewerPeerWhenOwnerDoesNotChange() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [.released, .retryableFailure, .released]
        )
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease, maximumReleaseAttemptCount: 1
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
        guard case .selected(let original) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Expected the original peer-one owner")
        }
        var nestedOutcome: WorldwideBlackHoleDefaultInputOutcome?
        lease.onNextRelease = {
            nestedOutcome = coordinator.transportDidBecomeHealthy(peerGeneration: 3)
        }
        XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 2), .degraded)
        XCTAssertEqual(nestedOutcome, .degraded,
            "Nested retryable cleanup commits peer three but retains the exact old owner")
        XCTAssertEqual(lease.acquisitions.count, 1)
        XCTAssertEqual(lease.releases, [original.leaseGeneration, original.leaseGeneration])
        XCTAssertEqual(lease.events, [.acquisition(original.leaseGeneration),
            .release(original.leaseGeneration), .release(original.leaseGeneration)])
        XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 2), .noChange)
        guard case .selected(let replacement) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 3) else {
            return XCTFail("Fresh peer-three callback must redrive the retained native owner")
        }
        XCTAssertEqual(replacement.peerGeneration, 3)
        XCTAssertEqual(replacement.connectionGeneration, original.connectionGeneration + 1)
        XCTAssertNotEqual(replacement.leaseGeneration, original.leaseGeneration)
        XCTAssertEqual(lease.releases,
            [original.leaseGeneration, original.leaseGeneration, original.leaseGeneration])
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertEqual(lease.events, [.acquisition(original.leaseGeneration),
            .release(original.leaseGeneration), .release(original.leaseGeneration),
            .release(original.leaseGeneration), .acquisition(replacement.leaseGeneration)])
    }

    func testNativeReleaseContextRetainsNestedMonitorWhenOwnerDoesNotChange() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [.released, .retryableFailure, .released]
        )
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease, maximumReleaseAttemptCount: 1
        )
        let originalEpoch = UUID()
        let outerEpoch = UUID()
        let nestedEpoch = UUID()
        _ = coordinator.beginMonitoring(epoch: originalEpoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: originalEpoch, generation: 1))
        guard case .selected(let original) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Expected the original monitor owner")
        }
        var nestedOutcome: WorldwideBlackHoleDefaultInputOutcome?
        lease.onNextRelease = {
            nestedOutcome = coordinator.beginMonitoring(epoch: nestedEpoch)
        }
        XCTAssertEqual(coordinator.beginMonitoring(epoch: outerEpoch), .degraded)
        XCTAssertEqual(nestedOutcome, .degraded)
        XCTAssertEqual(lease.acquisitions.count, 1)
        XCTAssertEqual(lease.releases, [original.leaseGeneration, original.leaseGeneration])
        XCTAssertEqual(coordinator.updateDeviceSnapshot(
            snapshot(epoch: outerEpoch, generation: 1)), .noChange,
            "The stale outer epoch must not replace the nested epoch")
        guard case .selected(let replacement) = coordinator.updateDeviceSnapshot(
            snapshot(epoch: nestedEpoch, generation: 1)
        ) else { return XCTFail("The nested epoch must admit its fresh snapshot and cleanup redrive") }
        XCTAssertEqual(replacement.monitorEpoch, nestedEpoch)
        XCTAssertNotEqual(replacement.leaseGeneration, original.leaseGeneration)
        XCTAssertEqual(lease.releases,
            [original.leaseGeneration, original.leaseGeneration, original.leaseGeneration])
        XCTAssertEqual(lease.acquisitions.count, 2)
        XCTAssertEqual(lease.events, [.acquisition(original.leaseGeneration),
            .release(original.leaseGeneration), .release(original.leaseGeneration),
            .release(original.leaseGeneration), .acquisition(replacement.leaseGeneration)])
    }

    func testNativeReleaseContextRetainsNestedDeviceSnapshotWhenOwnerDoesNotChange() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [.released, .retryableFailure, .released]
        )
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease, maximumReleaseAttemptCount: 1
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
        guard case .selected(let original) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Expected the original device-generation owner")
        }
        var nestedOutcome: WorldwideBlackHoleDefaultInputOutcome?
        lease.onNextRelease = {
            nestedOutcome = coordinator.updateDeviceSnapshot(
                self.snapshot(epoch: epoch, generation: 2)
            )
        }
        XCTAssertEqual(coordinator.deviceRevalidationDidFail(), .degraded)
        XCTAssertEqual(nestedOutcome, .degraded)
        XCTAssertEqual(lease.acquisitions.count, 1)
        XCTAssertEqual(lease.releases, [original.leaseGeneration, original.leaseGeneration])
        guard case .selected(let replacement) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Old device failure must not erase the nested newer snapshot")
        }
        XCTAssertEqual(replacement.deviceGeneration, 2)
        XCTAssertNotEqual(replacement.leaseGeneration, original.leaseGeneration)
        XCTAssertEqual(lease.releases,
            [original.leaseGeneration, original.leaseGeneration, original.leaseGeneration])
        XCTAssertEqual(lease.acquisitions.count, 2)
    }

    func testNativeReleaseEpisodePreservesReentrantReplacementForEveryActualDisposition() {
        let actualResults: [BlackHoleDefaultInputLeaseReleaseResult] = [
            .released, .retryableFailure, .externallySuperseded,
        ]
        for actual in actualResults {
            let lease = DefaultInputCoordinatorLeaseFake(releaseResults: [actual, .released])
            let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
                policy: .enabled, lease: lease, maximumReleaseAttemptCount: 3
            )
            let epoch = UUID()
            _ = coordinator.beginMonitoring(epoch: epoch)
            _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
            guard case .selected(let original) =
                    coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
                return XCTFail("Expected the original native owner")
            }
            var replacement: WorldwideBlackHoleDefaultInputKey?
            lease.onNextRelease = {
                guard case .selected(let next) =
                        coordinator.transportDidBecomeHealthy(peerGeneration: 2) else {
                    return XCTFail("Expected the one-shot nested replacement")
                }
                replacement = next
            }
            XCTAssertEqual(coordinator.transportDidBecomeUnhealthy(peerGeneration: 1), .degraded)
            guard let replacement else { return XCTFail("The callback did not publish a replacement") }
            XCTAssertNotEqual(replacement.leaseGeneration, original.leaseGeneration)
            XCTAssertEqual(lease.releases, [original.leaseGeneration, original.leaseGeneration],
                "Only the outer and nested original-owner releases may run; never retry the replacement")
            XCTAssertEqual(lease.events, [.acquisition(original.leaseGeneration),
                .release(original.leaseGeneration), .release(original.leaseGeneration),
                .acquisition(replacement.leaseGeneration)])
            XCTAssertEqual(coordinator.transportDidBecomeUnhealthy(peerGeneration: 1), .noChange)
            guard case .selected(let refreshed) =
                    coordinator.transportDidBecomeHealthy(peerGeneration: 2) else {
                return XCTFail("Stale native bookkeeping must not clear or fence the replacement")
            }
            XCTAssertEqual(refreshed, replacement)
            XCTAssertEqual(lease.acquisitions.count, 2)
            XCTAssertEqual(lease.releases.count, 2)
        }
    }

    func testNativeReleaseEpisodeDoesNotOverwriteReentrantNewerHealthyPeer() {
        let lease = DefaultInputCoordinatorLeaseFake(releaseResults: [.retryableFailure, .released])
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease, maximumReleaseAttemptCount: 3
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
        guard case .selected(let original) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Expected original peer one")
        }
        var replacement: WorldwideBlackHoleDefaultInputKey?
        lease.onNextRelease = {
            guard case .selected(let next) =
                    coordinator.transportDidBecomeHealthy(peerGeneration: 3) else {
                return XCTFail("Expected the genuinely newer nested peer three")
            }
            replacement = next
        }
        XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 2), .degraded)
        guard let replacement else { return XCTFail("Missing nested peer-three key") }
        XCTAssertEqual(replacement.peerGeneration, 3)
        XCTAssertNotEqual(replacement.leaseGeneration, original.leaseGeneration)
        XCTAssertEqual(coordinator.transportDidBecomeUnhealthy(peerGeneration: 2), .noChange)
        guard case .selected(let refreshed) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 3) else {
            return XCTFail("The outer peer-two callback must not overwrite the nested peer-three commit")
        }
        XCTAssertEqual(refreshed, replacement)
        XCTAssertEqual(lease.events, [.acquisition(original.leaseGeneration),
            .release(original.leaseGeneration), .release(original.leaseGeneration),
            .acquisition(replacement.leaseGeneration)])
    }

    func testNativeReleaseEpisodeDoesNotOverwriteReentrantMonitorEpoch() {
        let lease = DefaultInputCoordinatorLeaseFake(releaseResults: [.released, .released])
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease, maximumReleaseAttemptCount: 3
        )
        let originalEpoch = UUID()
        let outerEpoch = UUID()
        let nestedEpoch = UUID()
        _ = coordinator.beginMonitoring(epoch: originalEpoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: originalEpoch, generation: 1))
        guard case .selected(let original) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Expected the original monitor owner")
        }
        var replacement: WorldwideBlackHoleDefaultInputKey?
        lease.onNextRelease = {
            XCTAssertEqual(coordinator.beginMonitoring(epoch: nestedEpoch), .released)
            guard case .selected(let next) = coordinator.updateDeviceSnapshot(
                self.snapshot(epoch: nestedEpoch, generation: 1)
            ) else { return XCTFail("Expected the nested monitor snapshot to select its native owner") }
            replacement = next
        }
        XCTAssertEqual(coordinator.beginMonitoring(epoch: outerEpoch), .degraded)
        guard let replacement else { return XCTFail("Missing nested monitor owner") }
        XCTAssertEqual(replacement.monitorEpoch, nestedEpoch)
        guard case .selected(let refreshed) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("The outer monitor callback must not erase the nested epoch and snapshot")
        }
        XCTAssertEqual(refreshed, replacement)
        XCTAssertEqual(lease.events, [.acquisition(original.leaseGeneration),
            .release(original.leaseGeneration), .release(original.leaseGeneration),
            .acquisition(replacement.leaseGeneration)])
    }

    func testNativeReleaseEpisodeFencesSameGenerationAuthorizationChange() {
        let lease = DefaultInputCoordinatorLeaseFake(releaseResults: [.retryableFailure])
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease, maximumReleaseAttemptCount: 3
        )
        let epoch = UUID()
        let currentSnapshot = snapshot(epoch: epoch, generation: 1)
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(currentSnapshot)
        guard case .selected(let original) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Expected one native authorized owner")
        }
        var parked: BlackHoleDefaultInputLeaseParkingProof?
        lease.onNextRelease = {
            guard case .parked(let proof) =
                    coordinator.parkForSharedClockEpochRecovery(peerGeneration: 1) else {
                return XCTFail("Expected a same-generation native parking authorization")
            }
            parked = proof
        }
        XCTAssertEqual(coordinator.monitoringDidFail(), .degraded)
        guard let parked else { return XCTFail("Missing nested parking proof") }
        XCTAssertEqual(parked.leaseGeneration, original.leaseGeneration)
        XCTAssertNotEqual(parked.acceptedListenerSequence,
            original.inputAuthorization.acceptedListenerSequence)
        XCTAssertEqual(lease.releases, [original.leaseGeneration],
            "The old retryable result must not redrive the refreshed same-generation authorization")
        XCTAssertTrue(coordinator.sharedClockParkingProofIsCurrent(
            parked, peerGeneration: 1, snapshot: currentSnapshot))
        guard case .selected(let restored) = coordinator.transportDidBecomeHealthyAfterSharedClockRecovery(
            peerGeneration: 1, parkingProof: parked
        ) else { return XCTFail("The old cleanup must not mark the nested parking owner release-pending") }
        XCTAssertEqual(restored.leaseGeneration, original.leaseGeneration)
        XCTAssertEqual(lease.releases, [original.leaseGeneration])
        XCTAssertEqual(lease.acquisitions.count, 1)
    }

    func testNativeReleaseEpisodeStopsBeforeGenerationlessShutdownAfterNestedCleanup() {
        let lease = DefaultInputCoordinatorLeaseFake(releaseResults: [.released, .released])
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease,
            maximumReleaseAttemptCount: 3, maximumShutdownAttemptCount: 3
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
        guard case .selected(let original) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Expected the shutdown owner")
        }
        var nested: WorldwideBlackHoleDefaultInputOutcome?
        lease.onNextRelease = { nested = coordinator.shutdown() }
        XCTAssertEqual(coordinator.shutdown(), .degraded)
        XCTAssertEqual(nested, .released)
        XCTAssertEqual(lease.releases, [original.leaseGeneration, original.leaseGeneration])
        XCTAssertEqual(lease.shutdownCallCount, 1,
            "Only nested actual cleanup may call generationless shutdown after the old episode lost its owner")
        XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 2), .noChange)
        XCTAssertEqual(lease.acquisitions.count, 1)
    }

    func testRustInputLeaseActualCRefusalAfterAcquiredKeepsExactCleanupOwnership() {
        let lease = DefaultInputCoordinatorLeaseFake(
            acquisitionResults: [.acquired],
            releaseResults: [.retryableFailure, .released]
        )
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease,
            maximumAcquisitionAttemptCount: 3, maximumReleaseAttemptCount: 1,
            maximumShutdownAttemptCount: 1
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
        let first = coordinator.transportDidBecomeHealthy(peerGeneration: 1)
        guard let generation = lease.acquisitions.first?.generation else {
            return XCTFail("Expected the actual first native acquisition")
        }
        XCTAssertEqual(lease.acquisitions.map(\.generation), [generation])
        switch first {
        case .selected(let selected):
            XCTAssertEqual(selected.leaseGeneration, generation)
            XCTAssertEqual(lease.authorizationProofCallCount, 1)
            XCTAssertEqual(lease.releases, [])
            XCTAssertEqual(coordinator.shutdown(), .degraded)
            XCTAssertEqual(lease.releases, [generation])
            XCTAssertEqual(coordinator.shutdown(), .released)
            XCTAssertEqual(lease.releases, [generation, generation])
            XCTAssertEqual(lease.shutdownCallCount, 1)
            XCTAssertEqual(lease.acquisitions.map(\.generation), [generation])
            XCTAssertEqual(lease.authorizationProofCallCount, 1)
            XCTAssertEqual(lease.events,
                [.acquisition(generation), .release(generation), .release(generation)])
            FileHandle.standardError.write(Data(
                ("MIC_INPUT_LEASE_BASELINE acquired A1 R2 P1 cleanup=actual\n").utf8))
        case .degraded:
            XCTAssertEqual(lease.authorizationProofCallCount, 0)
            XCTAssertEqual(lease.releases, [generation],
                "Refusal after native acquired must execute the first exact cleanup")
            XCTAssertEqual(coordinator.transportDidBecomeUnhealthy(peerGeneration: 999), .noChange)
            XCTAssertEqual(lease.releases, [generation],
                "A foreign peer must not spend the retained owner's cleanup")
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
            XCTAssertEqual(lease.releases, [generation, generation],
                "The same identity must redrive retained retryable cleanup before admission")
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 2), .degraded)
            XCTAssertEqual(lease.acquisitions.map(\.generation), [generation])
            XCTAssertEqual(lease.releases, [generation, generation])
            XCTAssertEqual(lease.authorizationProofCallCount, 0)
            XCTAssertEqual(lease.events,
                [.acquisition(generation), .release(generation), .release(generation)])
            FileHandle.standardError.write(Data(
                ("MIC_INPUT_LEASE_REFUSAL acquired A1 R2 P0 sameOwner=1 foreignCleanup=0 readmission=0\n").utf8))
            XCTFail("MIC_INPUT_LEASE_EXPECTED_HEALTHY_ACQUIRED_BASELINE")
        default:
            XCTFail("Unexpected first acquired coordinator outcome")
        }
    }

    func testRustInputLeaseActualCRefusalAtPostKeyLoopBudgetKeepsExactCleanupOwnership() {
        let lease = DefaultInputCoordinatorLeaseFake(
            acquisitionResults: [.retryableFailure, .acquired],
            releaseResults: [.retryableFailure, .released]
        )
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease,
            maximumAcquisitionAttemptCount: 3, maximumReleaseAttemptCount: 1,
            maximumShutdownAttemptCount: 1
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
        let first = coordinator.transportDidBecomeHealthy(peerGeneration: 1)
        guard let generation = lease.acquisitions.first?.generation else {
            return XCTFail("Expected the actual first retryable native acquisition")
        }
        switch first {
        case .selected(let selected):
            XCTAssertEqual(selected.leaseGeneration, generation)
            XCTAssertEqual(lease.acquisitions.map(\.generation), [generation, generation])
            XCTAssertEqual(lease.authorizationProofCallCount, 1)
            XCTAssertEqual(lease.releases, [])
            XCTAssertEqual(coordinator.shutdown(), .degraded)
            XCTAssertEqual(lease.releases, [generation])
            XCTAssertEqual(coordinator.shutdown(), .released)
            XCTAssertEqual(lease.releases, [generation, generation])
            XCTAssertEqual(lease.shutdownCallCount, 1)
            XCTAssertEqual(lease.acquisitions.map(\.generation), [generation, generation])
            XCTAssertEqual(lease.authorizationProofCallCount, 1)
            XCTAssertEqual(lease.events, [.acquisition(generation), .acquisition(generation),
                .release(generation), .release(generation)])
            FileHandle.standardError.write(Data(
                ("MIC_INPUT_LEASE_BASELINE postKeyBudget A2 R2 P1 cleanup=actual\n").utf8))
        case .degraded:
            XCTAssertEqual(lease.acquisitions.map(\.generation), [generation])
            XCTAssertEqual(lease.authorizationProofCallCount, 0)
            XCTAssertEqual(lease.releases, [generation],
                "The count-one budget refusal must clean the already-minted exact pending key")
            XCTAssertEqual(coordinator.transportDidBecomeUnhealthy(peerGeneration: 999), .noChange)
            XCTAssertEqual(lease.releases, [generation])
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
            XCTAssertEqual(lease.releases, [generation, generation])
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 2), .degraded)
            XCTAssertEqual(lease.acquisitions.map(\.generation), [generation])
            XCTAssertEqual(lease.releases, [generation, generation])
            XCTAssertEqual(lease.authorizationProofCallCount, 0)
            XCTAssertEqual(lease.events,
                [.acquisition(generation), .release(generation), .release(generation)])
            FileHandle.standardError.write(Data(
                ("MIC_INPUT_LEASE_REFUSAL postKeyBudget A1 R2 P0 sameOwner=1 foreignCleanup=0 readmission=0\n").utf8))
            XCTFail("MIC_INPUT_LEASE_EXPECTED_HEALTHY_POST_KEY_BUDGET_BASELINE")
        default:
            XCTFail("Unexpected first post-key budget coordinator outcome")
        }
    }

    func testRustInputLeaseActualCRefusalAfterFirstRetryableReleaseKeepsExactCleanupOwnership() {
        let lease = DefaultInputCoordinatorLeaseFake(
            releaseResults: [.retryableFailure, .released]
        )
        let coordinator = WorldwideBlackHoleDefaultInputCoordinator(
            policy: .enabled, lease: lease, maximumReleaseAttemptCount: 3
        )
        let epoch = UUID()
        _ = coordinator.beginMonitoring(epoch: epoch)
        _ = coordinator.updateDeviceSnapshot(snapshot(epoch: epoch, generation: 1))
        guard case .selected(let selected) =
                coordinator.transportDidBecomeHealthy(peerGeneration: 1) else {
            return XCTFail("Expected one genuine acquired and authorized native key")
        }
        let generation = selected.leaseGeneration
        XCTAssertEqual(lease.acquisitions.map(\.generation), [generation])
        XCTAssertEqual(lease.authorizationProofCallCount, 1)
        XCTAssertEqual(lease.releases, [])
        let release = coordinator.transportDidBecomeUnhealthy(peerGeneration: 1)
        switch release {
        case .released:
            XCTAssertEqual(lease.releases, [generation, generation])
            XCTAssertEqual(coordinator.transportDidBecomeUnhealthy(peerGeneration: 1), .noChange)
            XCTAssertEqual(lease.releases, [generation, generation])
            XCTAssertEqual(lease.acquisitions.map(\.generation), [generation])
            XCTAssertEqual(lease.authorizationProofCallCount, 1)
            XCTAssertEqual(lease.events,
                [.acquisition(generation), .release(generation), .release(generation)])
            FileHandle.standardError.write(Data(
                ("MIC_INPUT_LEASE_BASELINE releaseContinuation A1 R2 P1 cleanup=actual\n").utf8))
        case .degraded:
            XCTAssertEqual(lease.releases, [generation],
                "A malformed continuation must return the first actual retryable disposition")
            XCTAssertEqual(coordinator.transportDidBecomeUnhealthy(peerGeneration: 999), .noChange)
            XCTAssertEqual(lease.releases, [generation])
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 1), .degraded)
            XCTAssertEqual(lease.releases, [generation, generation],
                "Original retained ownership must redrive even after sticky admission refusal")
            XCTAssertEqual(coordinator.transportDidBecomeHealthy(peerGeneration: 2), .degraded)
            XCTAssertEqual(lease.acquisitions.map(\.generation), [generation])
            XCTAssertEqual(lease.releases, [generation, generation])
            XCTAssertEqual(lease.authorizationProofCallCount, 1)
            XCTAssertEqual(lease.events,
                [.acquisition(generation), .release(generation), .release(generation)])
            FileHandle.standardError.write(Data(
                ("MIC_INPUT_LEASE_REFUSAL releaseContinuation A1 R2 P1 sameOwner=1 foreignCleanup=0 readmission=0\n").utf8))
            XCTFail("MIC_INPUT_LEASE_EXPECTED_COMPLETE_RELEASE_BASELINE")
        default:
            XCTFail("Unexpected first retryable release coordinator outcome")
        }
    }


    private func snapshot(
        epoch: UUID,
        generation: UInt64
    ) -> BlackHoleDeviceAvailabilitySnapshot {
        BlackHoleDeviceAvailabilitySnapshot(
            monitorEpoch: epoch,
            deviceGeneration: generation,
            defaultInputEndpoint: .init(
                deviceID: 79,
                deviceUID: "com.elamin.opensteamer.virtual-microphone.input"
            ),
            hiddenMirrorSinkEndpoint: .init(
                deviceID: 89,
                deviceUID: "com.elamin.opensteamer.virtual-microphone.writer"
            )
        )
    }
}

private final class DefaultInputCoordinatorLeaseFake:
    WorldwideBlackHoleDefaultInputLeasing,
    @unchecked Sendable
{
    struct Acquisition {
        let generation: UInt64
        let targetEndpoint: BlackHoleDeviceEndpointIdentity

        var targetUID: String {
            targetEndpoint.deviceUID
        }

        var targetDeviceID: AudioDeviceID {
            targetEndpoint.deviceID
        }
    }

    enum Event: Equatable {
        case acquisition(UInt64)
        case release(UInt64)
    }

    private(set) var events: [Event] = []
    private(set) var acquisitions: [Acquisition] = []
    private(set) var releases: [UInt64] = []
    // TEST-only synchronous callback through the unchanged leasing protocol.
    // Consumed before invocation, so nested release cannot replay it.
    var onNextRelease: (() -> Void)?
    private var acquisitionResults:
        [BlackHoleDefaultInputLeaseAcquisitionResult]
    private var releaseResults:
        [BlackHoleDefaultInputLeaseReleaseResult]
    private var shutdownResults:
        [BlackHoleDefaultInputLeaseReleaseResult]
    private(set) var shutdownCallCount = 0
    private var listenerRegistrationIDs: [UInt64: UUID] = [:]
    private(set) var authorizationProofCallCount = 0
    private var parkingProof:
        BlackHoleDefaultInputLeaseParkingProof?
    private var nextClockEpochParkingIsRetryable = false

    init(
        acquisitionResults:
            [BlackHoleDefaultInputLeaseAcquisitionResult] = [],
        releaseResults:
            [BlackHoleDefaultInputLeaseReleaseResult] = [],
        shutdownResults:
            [BlackHoleDefaultInputLeaseReleaseResult] = []
    ) {
        self.acquisitionResults = acquisitionResults
        self.releaseResults = releaseResults
        self.shutdownResults = shutdownResults
    }

    func acquisitionResult(
        generation: UInt64,
        targetEndpoint: BlackHoleDeviceEndpointIdentity
    ) -> BlackHoleDefaultInputLeaseAcquisitionResult {
        events.append(.acquisition(generation))
        acquisitions.append(
            Acquisition(
                generation: generation,
                targetEndpoint: targetEndpoint
            )
        )
        guard !acquisitionResults.isEmpty else {
            return .acquired
        }
        return acquisitionResults.removeFirst()
    }

    func authorizationProof(
        generation: UInt64,
        targetEndpoint: BlackHoleDeviceEndpointIdentity
    ) -> BlackHoleDefaultInputLeaseAuthorization? {
        authorizationProofCallCount += 1
        let registrationID: UUID
        if let existing = listenerRegistrationIDs[generation] {
            registrationID = existing
        } else {
            registrationID = UUID()
            listenerRegistrationIDs[generation] = registrationID
        }
        return BlackHoleDefaultInputLeaseAuthorization(
            leaseGeneration: generation,
            listenerRegistrationID: registrationID,
            acceptedListenerSequence: 1,
            targetEndpoint: targetEndpoint
        )
    }

    func release(
        generation: UInt64
    ) -> BlackHoleDefaultInputLeaseReleaseResult {
        events.append(.release(generation))
        releases.append(generation)
        let actual: BlackHoleDefaultInputLeaseReleaseResult = releaseResults.isEmpty
            ? .released : releaseResults.removeFirst()
        let callback = onNextRelease
        onNextRelease = nil
        callback?()
        return actual
    }

    func parkForClockEpochRecovery(
        generation: UInt64,
        targetEndpoint: BlackHoleDeviceEndpointIdentity
    ) -> BlackHoleDefaultInputLeaseParkingResult {
        if nextClockEpochParkingIsRetryable {
            nextClockEpochParkingIsRetryable = false
            return .retryableFailure
        }
        let registrationID =
            listenerRegistrationIDs[generation] ?? UUID()
        listenerRegistrationIDs[generation] = registrationID
        let proof = BlackHoleDefaultInputLeaseParkingProof(
            leaseGeneration: generation,
            listenerRegistrationID: registrationID,
            acceptedListenerSequence: 2,
            parkingEndpoint: BlackHoleDeviceEndpointIdentity(
                deviceID: 91,
                deviceUID:
                    WorldwideVirtualMicrophoneEndpointContract
                        .retiredLegacyVisibleDeviceUID
            ),
            targetEndpoint: targetEndpoint
        )
        parkingProof = proof
        return .parked(proof)
    }

    func clockEpochParkingProofIsCurrent(
        _ proof: BlackHoleDefaultInputLeaseParkingProof
    ) -> Bool {
        parkingProof == proof
    }

    func reacquisitionResult(
        parkingProof proof: BlackHoleDefaultInputLeaseParkingProof,
        targetEndpoint: BlackHoleDeviceEndpointIdentity
    ) -> BlackHoleDefaultInputLeaseAcquisitionResult {
        guard parkingProof == proof,
              proof.targetEndpoint == targetEndpoint else {
            return .terminalFailure
        }
        parkingProof = nil
        return .acquired
    }

    func invalidateParkingProof() {
        parkingProof = nil
    }

    func makeNextClockEpochParkingRetryable() {
        nextClockEpochParkingIsRetryable = true
    }

    func shutdown()
        -> BlackHoleDefaultInputLeaseReleaseResult {
        shutdownCallCount += 1
        guard !shutdownResults.isEmpty else {
            return .released
        }
        return shutdownResults.removeFirst()
    }
}

private final class DriverSharedClockFailureProbe:
    @unchecked Sendable
{
    struct Entry: Equatable {
        let key: WorldwideIPhoneMicrophoneForwardingKey
        let rejection: BlackHoleFaceTimeClockRejection
    }

    private let lock = NSLock()
    private var recordedEntries: [Entry] = []

    var entries: [Entry] {
        lock.withLock { recordedEntries }
    }

    func record(
        key: WorldwideIPhoneMicrophoneForwardingKey,
        rejection: BlackHoleFaceTimeClockRejection
    ) {
        lock.withLock {
            recordedEntries.append(
                Entry(key: key, rejection: rejection)
            )
        }
    }
}

private final class DriverFormatFailureProbe:
    @unchecked Sendable
{
    struct Entry: Equatable {
        let key: WorldwideIPhoneMicrophoneForwardingKey
        let rejection: BlackHoleMicrophoneOutputFormatRejection
    }

    private let lock = NSLock()
    private var recordedEntries: [Entry] = []

    var entries: [Entry] {
        lock.withLock { recordedEntries }
    }

    func record(
        key: WorldwideIPhoneMicrophoneForwardingKey,
        rejection: BlackHoleMicrophoneOutputFormatRejection
    ) {
        lock.withLock {
            recordedEntries.append(
                Entry(key: key, rejection: rejection)
            )
        }
    }
}

private enum DriverTestEvidenceReentry: Equatable, Sendable {
    case nestedWatermarkSnapshot, progressShutdown, freshnessClockShutdown
}

private struct DriverTestNestedObservation: Equatable, Sendable {
    let phase: WorldwideIPhoneMicrophoneForwardingPhase
    let queueRunning: Bool
    let inboundMediaFresh: Bool
    let progressReadDelta: Int
    let clockReadDelta: Int
    let producerDelta: [Int]
}

private enum DriverTestEvidenceCleanup: Equatable, Sendable {
    case trackDisable, outputStop
}

private enum DriverTestEvidenceFault: Equatable, Sendable {
    case none
    case readinessWrongVote, readinessStatusZero
    case watermarkWrongAdvance, watermarkStatusZero
    case freshnessPlanWrongVote, freshnessPlanStatusZero
    case freshnessDecisionWrongVote, freshnessDecisionStatusZero

    var family: Int {
        switch self {
        case .readinessWrongVote, .readinessStatusZero: 0
        case .watermarkWrongAdvance, .watermarkStatusZero: 1
        case .none, .freshnessPlanWrongVote, .freshnessPlanStatusZero,
             .freshnessDecisionWrongVote, .freshnessDecisionStatusZero: 2
        }
    }
    var isFreshnessDecision: Bool {
        self == .freshnessDecisionWrongVote || self == .freshnessDecisionStatusZero
    }
}

private enum DriverTestRetryFault: Equatable, Sendable {
    case none, statusZero, coherentCorruption, nestedSnapshot, shutdown, replacePeer
}

private struct DriverTestRetryCall: Equatable, Sendable {
    let maximum: Int64
    let opcode: UInt32
    let category: UInt32
    let beforePresent: UInt32
    let beforeCount: Int64
    let beforeMayRetry: UInt32
    let afterPresent: UInt32
    let afterCount: Int64
    let afterMayRetry: UInt32
    let status: UInt32
    let decision: UInt32
    let redrive: UInt32
    let nativeStopCount: Int?
    let nativeTrackEnabled: Bool?
    let nativeRedrive: Bool?
}

private actor DriverTestHarness {
    private let driver:
        WorldwideIPhoneMicrophoneForwardingDriver<
            DriverTestPeer,
            DriverTestTrack
        >
    private let automaticallyAdvanceInboundMedia: Bool
    private var currentPeer: DriverTestPeer?
    private var currentPeerGeneration: UInt64 = 0
    private var nextInboundCounter: UInt64 = 100

    init(
        policy:
            WorldwideIPhoneMicrophoneForwardingPolicy = .enabled,
        factory: DriverTestOutputFactory,
        readinessGate: DriverSuspensionGate? = nil,
        readinessSampleLimit: Int = 2,
        retryGate: DriverSuspensionGate? = nil,
        retrySleepThrowsAfterGate: Bool = false,
        maximumAttemptCountPerKey: Int = 3,
        maximumStaleInboundMediaSamples: Int = 3,
        mediaFreshnessTimeoutNanoseconds: UInt64 = 3_000_000_000,
        mediaFreshnessWatchdog:
            DriverTestMediaFreshnessWatchdog? = nil,
        automaticallyAdvanceInboundMedia: Bool = true,
        sharedClockFailureHandler:
            @escaping @Sendable (
                WorldwideIPhoneMicrophoneForwardingKey,
                BlackHoleFaceTimeClockRejection
            ) async -> Void = { _, _ in },
        formatFailureHandler:
            @escaping @Sendable (
                WorldwideIPhoneMicrophoneForwardingKey,
                BlackHoleMicrophoneOutputFormatRejection
            ) async -> Void = { _, _ in }
    ) {
        self.automaticallyAdvanceInboundMedia =
            automaticallyAdvanceInboundMedia
        driver = WorldwideIPhoneMicrophoneForwardingDriver(
            policy: policy,
            makeOutput: { _, endpoint in
                factory.makeOutput(endpoint: endpoint)
            },
            startOutput: { output in
                guard let output = output as? DriverTestOutput else {
                    throw DriverTestError.wrongOutputType
                }
                try await output.startAsynchronously()
            },
            admit: { peer, track in
                try await peer.admit(track)
            },
            disableTrack: { track in
                track.setEnabled(false)
            },
            readinessSleep: {
                if let readinessGate {
                    await readinessGate.wait()
                }
            },
            readinessSampleLimit: readinessSampleLimit,
            maximumStaleInboundMediaSamples:
                maximumStaleInboundMediaSamples,
            mediaFreshnessTimeoutNanoseconds:
                mediaFreshnessTimeoutNanoseconds,
            mediaFreshnessNow: {
                mediaFreshnessWatchdog?.now
                    ?? DispatchTime.now().uptimeNanoseconds
            },
            mediaFreshnessDeadlineSleep: { deadline in
                if let mediaFreshnessWatchdog {
                    try await mediaFreshnessWatchdog.sleep(
                        until: deadline
                    )
                } else {
                    while true {
                        let now =
                            DispatchTime.now().uptimeNanoseconds
                        guard now < deadline else { return }
                        try await Task.sleep(
                            nanoseconds: deadline - now
                        )
                    }
                }
            },
            retrySleep: {
                if let retryGate {
                    await retryGate.wait()
                }
                if retrySleepThrowsAfterGate { throw CancellationError() }
            },
            maximumAttemptCountPerKey:
                maximumAttemptCountPerKey,
            makeAttemptID: { factory.makeRecordedAttemptID() },
            sharedClockFailureHandler:
                sharedClockFailureHandler,
            formatFailureHandler:
                formatFailureHandler
        )
    }

    func configureRetryEvidence(
        factory: DriverTestOutputFactory,
        target: UInt32 = 0,
        fault: DriverTestRetryFault = .none,
        output: DriverTestOutput? = nil,
        track: DriverTestTrack? = nil,
        replacementPeer: DriverTestPeer? = nil,
        observationKey: WorldwideIPhoneMicrophoneForwardingKey? = nil
    ) {
        let original = driver
        driver.configureRetryMutationForTesting { [weak original] config, before, event, actual in
            let nativeOutput = output ?? factory.lastProducedOutput
            let shouldMutate = factory.recordRetryCall(.init(
                maximum: config.maximum_attempt_count, opcode: event.opcode,
                category: event.failure_category,
                beforePresent: before.present, beforeCount: before.count, beforeMayRetry: before.may_retry,
                afterPresent: actual.state.present, afterCount: actual.state.count,
                afterMayRetry: actual.state.may_retry, status: actual.status,
                decision: actual.decision, redrive: actual.redrive_action,
                nativeStopCount: nativeOutput?.stopCount, nativeTrackEnabled: track?.isEnabled,
                nativeRedrive: observationKey.flatMap { key in
                    original?.retryObservationForTesting(isolation: nil, key: key).redrive
                }
            ), target: target)
            guard shouldMutate else { return actual }
            if fault == .nestedSnapshot {
                if let original {
                    let nested = original.snapshot(isolation: nil)
                    factory.recordRetryNestedSnapshot(nested.phase)
                }
                return actual
            }
            if fault == .shutdown {
                original?.shutdown(isolation: nil)
                return actual
            }
            if fault == .replacePeer {
                if let replacementPeer {
                    original?.replacePeer(isolation: nil, peer: replacementPeer, peerGeneration: 2)
                }
                return actual
            }
            var result = actual
            switch fault {
            case .none, .nestedSnapshot, .shutdown, .replacePeer: break
            case .statusZero: result.status = 0
            case .coherentCorruption:
                switch event.opcode {
                case 1, 3: result.decision = actual.decision == 0 ? 1 : 0
                case 2: result.state.count = actual.state.count + 1
                case 4: result.state.may_retry = actual.state.may_retry == 0 ? 1 : 0
                default: preconditionFailure("Closed four-operation test")
                }
            }
            return result
        }
    }

    func retryObservation(_ key: WorldwideIPhoneMicrophoneForwardingKey)
        -> (count: Int?, mayRetry: Bool?, redrive: Bool, faultExhaustCalls: Int,
            bridgeFaulted: Bool, retainedKeys: [WorldwideIPhoneMicrophoneForwardingKey]) {
        driver.retryObservationForTesting(key: key)
    }

    func configureEvidenceFault(
        _ fault: DriverTestEvidenceFault,
        output: DriverTestOutput
    ) {
        driver.configureEvidenceMutationsForTesting(
            .init(
                readiness: { _, actual in
                    let armed = output.evidenceCallShouldCorrupt(0)
                    guard armed, fault.family == 0, actual.status == 1,
                          actual.ready == 1 else { return actual }
                    var result = actual
                    if fault == .readinessStatusZero {
                        result.status = 0
                    } else {
                        result.ready = 0
                        result.continuing = 0
                    }
                    output.recordEvidenceCorruption(0)
                    return result
                },
                watermark: { _, _, actual in
                    let armed = output.evidenceCallShouldCorrupt(1)
                    guard armed, fault.family == 1, actual.status == 1,
                          actual.did_advance == 1 else { return actual }
                    var result = actual
                    if fault == .watermarkStatusZero {
                        result.status = 0
                    } else {
                        result.did_advance = 0
                    }
                    output.recordEvidenceCorruption(1)
                    return result
                },
                freshness: { _, event, actual in
                    let armed = output.evidenceCallShouldCorrupt(2)
                    guard armed, fault != .none, fault.family == 2 else {
                        return actual
                    }
                    var result = actual
                    if fault.isFreshnessDecision {
                        guard event.now.present == 1, actual.status == 1 else {
                            return actual
                        }
                        if fault == .freshnessDecisionStatusZero {
                            result.status = 0
                        } else {
                            result.fresh = actual.fresh == 1 ? 0 : 1
                        }
                    } else {
                        guard event.now.present == 0, actual.status == 2 else {
                            return actual
                        }
                        if fault == .freshnessPlanStatusZero {
                            result.status = 0
                        } else {
                            result.status = 1
                            result.fresh = 1
                        }
                    }
                    output.recordEvidenceCorruption(2)
                    return result
                }
            )
        )
    }

    func configureEvidenceObservation(
        _ cut: DriverTestEvidenceReentry,
        output: DriverTestOutput,
        watchdog: DriverTestMediaFreshnessWatchdog
    ) {
        let original = driver
        driver.configureEvidenceMutationsForTesting(
            .init(
                readiness: { _, actual in
                    _ = output.evidenceCallShouldCorrupt(0)
                    return actual
                },
                watermark: { [weak original] _, _, actual in
                    let armed = output.evidenceCallShouldCorrupt(1)
                    if armed, cut == .nestedWatermarkSnapshot,
                       actual.status == 1, actual.did_advance == 1,
                       let original {
                        let reads = output.progressReadCount
                        let clocks = watchdog.nowReadCount
                        let calls = output.evidenceCallCounts
                        let nested = original.snapshot(isolation: nil)
                        output.recordNestedObservation(.init(
                            phase: nested.phase,
                            queueRunning: nested.queueRunning,
                            inboundMediaFresh: nested.inboundMediaFresh,
                            progressReadDelta: output.progressReadCount - reads,
                            clockReadDelta: watchdog.nowReadCount - clocks,
                            producerDelta: zip(output.evidenceCallCounts, calls).map { pair in pair.0 - pair.1 }
                        ))
                    }
                    return actual
                },
                freshness: { _, event, actual in
                    _ = output.evidenceCallShouldCorrupt(2)
                    output.recordFreshnessVote(nowPresent: event.now.present, status: actual.status)
                    return actual
                }
            )
        )
    }

    func armEvidenceReentry(
        _ cut: DriverTestEvidenceReentry,
        output: DriverTestOutput,
        watchdog: DriverTestMediaFreshnessWatchdog
    ) {
        let original = driver
        switch cut {
        case .nestedWatermarkSnapshot:
            output.armEvidenceFault()
        case .progressShutdown:
            output.setOneShotProgressHook { [weak original] in
                original?.shutdown(isolation: nil)
            }
        case .freshnessClockShutdown:
            watchdog.setOneShotNowHook { [weak original] in
                original?.shutdown(isolation: nil)
            }
        }
    }

    func armCleanupShutdown(
        _ cut: DriverTestEvidenceCleanup,
        output: DriverTestOutput,
        track: DriverTestTrack
    ) {
        let original = driver
        switch cut {
        case .trackDisable:
            track.setOneShotDisableHook { [weak original] in
                original?.shutdown(isolation: nil)
            }
        case .outputStop:
            output.setOneShotStopHook { [weak original] in
                original?.shutdown(isolation: nil)
            }
        }
    }

    func shutdown() {
        driver.shutdown()
    }

    func beginMonitoring(_ epoch: UUID) {
        driver.beginMonitoring(epoch: epoch)
    }

    func replacePeer(
        _ peer: DriverTestPeer,
        generation: UInt64
    ) {
        currentPeer = peer
        currentPeerGeneration = generation
        driver.replacePeer(
            peer: peer,
            peerGeneration: generation
        )
    }

    func installTrack(_ track: DriverTestTrack) async {
        await driver.installTrack(track)
        await automaticallyPublishAdvancingInboundMediaIfNeeded()
    }

    func authorize(
        peer: DriverTestPeer,
        generation: UInt64
    ) async {
        await driver.authorizeTransport(
            peer: peer,
            peerGeneration: generation
        )
        await automaticallyPublishAdvancingInboundMediaIfNeeded()
    }

    func invalidateTransport(
        preservingSharedClockUnsafeFailure: Bool = false
    ) {
        driver.invalidateTransport(
            preservingSharedClockUnsafeFailure:
                preservingSharedClockUnsafeFailure
        )
    }

    func updateDevice(
        _ snapshot: BlackHoleDeviceAvailabilitySnapshot
    ) async {
        await driver.updateDeviceSnapshot(snapshot)
        await automaticallyPublishAdvancingInboundMediaIfNeeded()
    }

    func handleRuntimeFailure(
        _ output: DriverTestOutput,
        category:
            WorldwideIPhoneMicrophoneForwardingFailureCategory =
                .runtimeEnqueueFailed
    ) async -> Bool {
        let handled = await driver.handleRuntimeFailure(
            from: output,
            category: category
        )
        await automaticallyPublishAdvancingInboundMediaIfNeeded()
        return handled
    }

    func publishInboundMedia(
        packets: UInt64?,
        bytes: UInt64?,
        jitterBufferEmittedCount: UInt64? = nil,
        totalSamplesReceived: UInt64? = nil,
        peer: DriverTestPeer? = nil,
        generation: UInt64? = nil
    ) async {
        guard let sourcePeer = peer ?? currentPeer else { return }
        await driver.updateInboundMediaFreshness(
            peer: sourcePeer,
            peerGeneration: generation ?? currentPeerGeneration,
            watermark:
                WorldwideIPhoneMicrophoneInboundMediaWatermark(
                    packetsReceived: packets,
                    bytesReceived: bytes,
                    jitterBufferEmittedCount:
                        jitterBufferEmittedCount,
                    totalSamplesReceived: totalSamplesReceived
                )
        )
    }

    private func automaticallyPublishAdvancingInboundMediaIfNeeded()
        async {
        guard automaticallyAdvanceInboundMedia,
              driver.snapshot().exactTrackAdmitted,
              let currentPeer else {
            return
        }
        nextInboundCounter &+= 1
        await publishInboundMedia(
            packets: nextInboundCounter,
            bytes: nextInboundCounter * 80,
            peer: currentPeer,
            generation: currentPeerGeneration
        )
        nextInboundCounter &+= 1
        await publishInboundMedia(
            packets: nextInboundCounter,
            bytes: nextInboundCounter * 80,
            peer: currentPeer,
            generation: currentPeerGeneration
        )
    }

    func snapshot()
        -> WorldwideIPhoneMicrophoneForwardingHostSnapshot {
        driver.snapshot()
    }
}

private final class DriverTestOutput:
    WorldwideIPhoneMicrophoneOutput,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let startGate: DriverSuspensionGate?
    private let startError: (any Error)?
    private var progressSnapshots:
        [BlackHoleMicrophoneOutputProgressSnapshot]
    private var starts = 0
    private var stops = 0
    private var startEntered = false
    private var evidenceFaultArmed = false
    private var evidenceCalls = [0, 0, 0]
    private var evidenceCorruptions = [0, 0, 0]
    private var stopHook: (() -> Void)?
    private var stopHookCalls = 0
    private var progressReads = 0
    private var progressHook: (() -> Void)?
    private var progressHookCalls = 0
    private var nested: DriverTestNestedObservation?
    private var nestedSnapshots = 0
    private var recordedFreshnessVotes: [[UInt32]] = []

    init(
        startGate: DriverSuspensionGate? = nil,
        startError: (any Error)? = nil,
        progressSnapshots:
            [BlackHoleMicrophoneOutputProgressSnapshot] = [.zero]
    ) {
        self.startGate = startGate
        self.startError = startError
        self.progressSnapshots = progressSnapshots
    }

    func startAsynchronously() async throws {
        lock.withLock {
            startEntered = true
        }
        if let startGate {
            await startGate.wait()
        }
        try start()
    }

    func start() throws {
        let error = lock.withLock { () -> (any Error)? in
            starts += 1
            return startError
        }
        if let error {
            throw error
        }
    }

    func stop() {
        let hook = lock.withLock { () -> (() -> Void)? in
            stops += 1
            let hook = stopHook
            stopHook = nil
            if hook != nil { stopHookCalls += 1 }
            return hook
        }
        hook?()
    }

    func setOneShotStopHook(_ hook: @escaping () -> Void) {
        lock.withLock {
            precondition(stopHook == nil)
            stopHook = hook
        }
    }

    var cleanupHookCount: Int {
        lock.withLock { stopHookCalls }
    }

    var forwardingProgressSnapshot:
        BlackHoleMicrophoneOutputProgressSnapshot {
        let capture = lock.withLock { () -> (BlackHoleMicrophoneOutputProgressSnapshot, (() -> Void)?) in
            progressReads += 1
            let hook = progressHook
            progressHook = nil
            if hook != nil { progressHookCalls += 1 }
            guard !progressSnapshots.isEmpty else {
                return (.zero, hook)
            }
            if progressSnapshots.count > 1 {
                return (progressSnapshots.removeFirst(), hook)
            }
            return (progressSnapshots[0], hook)
        }
        capture.1?()
        return capture.0
    }

    func setOneShotProgressHook(_ hook: @escaping () -> Void) {
        lock.withLock {
            precondition(progressHook == nil)
            progressHook = hook
        }
    }

    var progressReadCount: Int { lock.withLock { progressReads } }
    var progressHookCount: Int { lock.withLock { progressHookCalls } }
    var nestedObservation: DriverTestNestedObservation? { lock.withLock { nested } }
    var nestedSnapshotCount: Int { lock.withLock { nestedSnapshots } }
    var freshnessVotes: [[UInt32]] { lock.withLock { recordedFreshnessVotes } }

    func recordNestedObservation(_ observation: DriverTestNestedObservation) {
        lock.withLock {
            nestedSnapshots += 1
            nested = observation
        }
    }

    func recordFreshnessVote(nowPresent: UInt32, status: UInt32) {
        lock.withLock { recordedFreshnessVotes.append([nowPresent, status]) }
    }

    var startCount: Int {
        lock.withLock { starts }
    }

    var stopCount: Int {
        lock.withLock { stops }
    }

    func armEvidenceFault() {
        lock.withLock { evidenceFaultArmed = true }
    }

    func evidenceCallShouldCorrupt(_ family: Int) -> Bool {
        precondition((0..<3).contains(family))
        return lock.withLock {
            evidenceCalls[family] += 1
            return evidenceFaultArmed
        }
    }

    func recordEvidenceCorruption(_ family: Int) {
        precondition((0..<3).contains(family))
        lock.withLock { evidenceCorruptions[family] += 1 }
    }

    var evidenceCallCounts: [Int] {
        lock.withLock { evidenceCalls }
    }

    var evidenceCorruptionCounts: [Int] {
        lock.withLock { evidenceCorruptions }
    }

    var startWasEntered: Bool {
        lock.withLock { startEntered }
    }
}

private final class DriverTestOutputFactory:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var outputs: [DriverTestOutput]
    private var requests = 0
    private var endpoints: [BlackHoleDeviceEndpointIdentity] = []
    private var createdOutput: DriverTestOutput?
    private var recordedRetryCalls: [DriverTestRetryCall] = []
    private var retryFaultArmed = false
    private var retryMutations = 0
    private var retryNestedSnapshots = 0
    private var retryNestedPhaseValue: WorldwideIPhoneMicrophoneForwardingPhase?
    private var attemptIDs = 0

    func makeRecordedAttemptID() -> UUID {
        lock.withLock { attemptIDs += 1 }
        return UUID()
    }

    func armRetryFault() {
        lock.withLock { retryFaultArmed = true }
    }

    func recordRetryCall(_ call: DriverTestRetryCall, target: UInt32) -> Bool {
        lock.withLock {
            recordedRetryCalls.append(call)
            guard retryFaultArmed, call.opcode == target else { return false }
            retryFaultArmed = false
            retryMutations += 1
            return true
        }
    }

    func recordRetryNestedSnapshot(_ phase: WorldwideIPhoneMicrophoneForwardingPhase) {
        lock.withLock {
            retryNestedSnapshots += 1
            retryNestedPhaseValue = phase
        }
    }

    var retryCalls: [DriverTestRetryCall] { lock.withLock { recordedRetryCalls } }
    var retryMutationCount: Int { lock.withLock { retryMutations } }
    var retryNestedSnapshotCount: Int { lock.withLock { retryNestedSnapshots } }
    var retryNestedPhase: WorldwideIPhoneMicrophoneForwardingPhase? { lock.withLock { retryNestedPhaseValue } }
    var attemptIDCount: Int { lock.withLock { attemptIDs } }
    var lastProducedOutput: DriverTestOutput? { lock.withLock { createdOutput } }


    init(outputs: [DriverTestOutput]) {
        self.outputs = outputs
    }

    func makeOutput(
        endpoint: BlackHoleDeviceEndpointIdentity
    ) -> (any WorldwideIPhoneMicrophoneOutput)? {
        lock.withLock {
            requests += 1
            endpoints.append(endpoint)
            guard !outputs.isEmpty else {
                return nil
            }
            let output = outputs.removeFirst()
            createdOutput = output
            return output
        }
    }

    func append(_ output: DriverTestOutput) {
        lock.withLock {
            outputs.append(output)
        }
    }

    var requestCount: Int {
        lock.withLock { requests }
    }

    var requestedUIDs: [String] {
        lock.withLock { endpoints.map(\.deviceUID) }
    }

    var requestedDeviceIDs: [AudioDeviceID] {
        lock.withLock { endpoints.map(\.deviceID) }
    }
}

private final class DriverTestPeer: @unchecked Sendable {
    private let lock = NSLock()
    private let admissionGate: DriverSuspensionGate?
    private var healthy: Bool
    private var admissions = 0

    init(
        healthy: Bool = true,
        admissionGate: DriverSuspensionGate? = nil
    ) {
        self.healthy = healthy
        self.admissionGate = admissionGate
    }

    func admit(_ track: DriverTestTrack) async throws {
        lock.withLock {
            admissions += 1
        }
        if let admissionGate {
            await admissionGate.wait()
        }
        let isHealthy = lock.withLock { healthy }
        guard isHealthy else {
            track.setEnabled(false)
            throw DriverTestError.admission
        }
        track.setEnabled(true)
    }

    var admissionCount: Int {
        lock.withLock { admissions }
    }
}

private final class CleanupAttemptProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var results: [Bool]
    private var attempts = 0

    init(results: [Bool]) {
        self.results = results
    }

    func attempt() -> Bool {
        lock.withLock {
            attempts += 1
            guard !results.isEmpty else {
                return false
            }
            return results.removeFirst()
        }
    }

    var attemptCount: Int {
        lock.withLock {
            attempts
        }
    }
}

private final class RuntimeDisposalOutputFactory:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let operations:
        DistinctRuntimeAudioQueueOperations
    private var outputs:
        [BlackHoleMicrophoneOutput] = []

    init(
        operations:
            DistinctRuntimeAudioQueueOperations
    ) {
        self.operations = operations
    }

    func makeOutput()
        -> (any WorldwideIPhoneMicrophoneOutput)? {
        guard let output =
                BlackHoleMicrophoneOutput(
                    testingAudioQueueOperations:
                        operations,
                    renderForTesting: {
                        samples,
                        frameCount in
                        for index in 0..<frameCount {
                            samples[index] = 1
                        }
                        return true
                    },
                    runtimeFailureHandler: {
                        _, _ in
                    }
                ) else {
            return nil
        }
        lock.withLock {
            outputs.append(output)
        }
        return output
    }

    func output(
        at index: Int
    ) -> BlackHoleMicrophoneOutput? {
        lock.withLock {
            guard outputs.indices.contains(index)
            else {
                return nil
            }
            return outputs[index]
        }
    }

    func latestOutput()
        -> BlackHoleMicrophoneOutput? {
        lock.withLock {
            outputs.last
        }
    }
}

private actor RuntimeDisposalDriverHarness {
    private let driver:
        WorldwideIPhoneMicrophoneForwardingDriver<
            DriverTestPeer,
            DriverTestTrack
        >
    private var currentPeer: DriverTestPeer?
    private var currentPeerGeneration: UInt64 = 0
    private var nextInboundCounter: UInt64 = 1_000

    init(
        factory: RuntimeDisposalOutputFactory,
        operations:
            DistinctRuntimeAudioQueueOperations
    ) {
        driver =
            WorldwideIPhoneMicrophoneForwardingDriver(
                policy: .enabled,
                makeOutput: { _, _ in
                    factory.makeOutput()
                },
                startOutput: { output in
                    try output.start()
                    guard let output =
                            output as?
                                BlackHoleMicrophoneOutput,
                          let queue =
                            operations.latestQueue,
                          let buffer =
                            operations
                                .firstActiveBuffer
                    else {
                        return
                    }
                    output
                        .debugInvokeRealtimeCallbackForTesting(
                            queue: queue,
                            buffer: buffer
                        )
                },
                admit: { peer, track in
                    try await peer.admit(track)
                },
                disableTrack: { track in
                    track.setEnabled(false)
                },
                readinessSleep: {
                    guard let output =
                            factory.latestOutput(),
                          let queue =
                            operations.latestQueue,
                          let buffer =
                            operations
                                .firstActiveBuffer
                    else {
                        return
                    }
                    output
                        .debugInvokeRealtimeCallbackForTesting(
                            queue: queue,
                            buffer: buffer
                        )
                },
                readinessSampleLimit: 2,
                retrySleep: {},
                maximumAttemptCountPerKey: 3
            )
    }

    func beginMonitoring(_ epoch: UUID) {
        driver.beginMonitoring(epoch: epoch)
    }

    func replacePeer(
        _ peer: DriverTestPeer,
        generation: UInt64
    ) {
        currentPeer = peer
        currentPeerGeneration = generation
        driver.replacePeer(
            peer: peer,
            peerGeneration: generation
        )
    }

    func installTrack(
        _ track: DriverTestTrack
    ) async {
        await driver.installTrack(track)
        await publishAdvancingInboundMediaIfNeeded()
    }

    func authorize(
        peer: DriverTestPeer,
        generation: UInt64
    ) async {
        await driver.authorizeTransport(
            peer: peer,
            peerGeneration: generation
        )
        await publishAdvancingInboundMediaIfNeeded()
    }

    func updateDevice(
        _ snapshot:
            BlackHoleDeviceAvailabilitySnapshot
    ) async {
        await driver.updateDeviceSnapshot(snapshot)
        await publishAdvancingInboundMediaIfNeeded()
    }

    func handleRuntimeFailure(
        _ output: BlackHoleMicrophoneOutput
    ) async -> Bool {
        let handled = await driver.handleRuntimeFailure(
            from: output,
            category:
                .runtimeProgressStalled
        )
        await publishAdvancingInboundMediaIfNeeded()
        return handled
    }

    private func publishAdvancingInboundMediaIfNeeded() async {
        guard driver.snapshot().exactTrackAdmitted,
              let currentPeer else {
            return
        }
        nextInboundCounter &+= 1
        await driver.updateInboundMediaFreshness(
            peer: currentPeer,
            peerGeneration: currentPeerGeneration,
            watermark:
                WorldwideIPhoneMicrophoneInboundMediaWatermark(
                    packetsReceived: nextInboundCounter,
                    bytesReceived: nextInboundCounter * 80,
                    jitterBufferEmittedCount: nil,
                    totalSamplesReceived: nil
                )
        )
        nextInboundCounter &+= 1
        await driver.updateInboundMediaFreshness(
            peer: currentPeer,
            peerGeneration: currentPeerGeneration,
            watermark:
                WorldwideIPhoneMicrophoneInboundMediaWatermark(
                    packetsReceived: nextInboundCounter,
                    bytesReceived: nextInboundCounter * 80,
                    jitterBufferEmittedCount: nil,
                    totalSamplesReceived: nil
                )
        )
    }

    func snapshot()
        -> WorldwideIPhoneMicrophoneForwardingHostSnapshot {
        driver.snapshot()
    }

    func shutdown() {
        driver.shutdown()
    }
}

private final class
    DistinctRuntimeAudioQueueOperations:
    BlackHoleMicrophoneOutputAudioQueueOperations,
    @unchecked Sendable
{
    private struct QueueState {
        var disposed = false
        var allocations:
            [RuntimeDisposalBufferAllocation] = []
    }

    private let lock = NSLock()
    private let disposeStatuses: [OSStatus]
    private var disposeIndex = 0
    private var nextQueueIdentity: UInt = 65_536
    private var queues: [UInt: QueueState] = [:]
    private var selectedDeviceUIDs: [UInt: String] = [:]
    private var created:
        [UInt] = []
    private var eventStorage:
        [String] = []
    private var latestQueueStorage:
        AudioQueueRef?

    init(disposeStatuses: [OSStatus]) {
        self.disposeStatuses = disposeStatuses
    }

    deinit {
        let allocations = lock.withLock {
            queues.values.flatMap {
                $0.allocations
            }
        }
        for allocation in allocations {
            allocation.freeIfNeeded()
        }
    }

    var createdQueueIdentities: [UInt] {
        lock.withLock {
            created
        }
    }

    var events: [String] {
        lock.withLock {
            eventStorage
        }
    }

    var latestQueue: AudioQueueRef? {
        lock.withLock {
            latestQueueStorage
        }
    }

    var firstActiveBuffer:
        AudioQueueBufferRef? {
        lock.withLock {
            for queue in created.reversed() {
                guard let state = queues[queue],
                      !state.disposed,
                      let allocation =
                        state.allocations.first(
                            where: {
                                !$0.isFreed
                            }
                        ) else {
                    continue
                }
                return allocation.buffer
            }
            return nil
        }
    }

    var activeAllocationCount: Int {
        lock.withLock {
            queues.values.reduce(0) {
                partial,
                state in
                partial + state.allocations.filter {
                    !$0.isFreed
                }.count
            }
        }
    }

    func createOutputQueue() -> (
        status: OSStatus,
        queue: AudioQueueRef?
    ) {
        lock.withLock {
            let identity = nextQueueIdentity
            nextQueueIdentity += 1
            let queue =
                OpaquePointer(
                    bitPattern: identity
                )!
            queues[identity] = QueueState()
            created.append(identity)
            latestQueueStorage = queue
            eventStorage.append(
                "create:\(identity)"
            )
            return (noErr, queue)
        }
    }

    func translateDeviceID(
        exactUID: String
    ) -> (status: OSStatus, deviceID: AudioDeviceID?) {
        guard exactUID
                == WorldwideVirtualMicrophoneEndpointContract
                    .hiddenMirrorSinkDeviceUID else {
            return (kAudio_ParamError, nil)
        }
        return (noErr, 89)
    }

    func setCurrentDevice(
        _ uid: String,
        on queue: AudioQueueRef
    ) -> OSStatus {
        lock.withLock {
            selectedDeviceUIDs[Self.identity(queue)] = uid
            return noErr
        }
    }

    func currentDeviceUID(
        on queue: AudioQueueRef
    ) -> (status: OSStatus, uid: String?) {
        lock.withLock {
            (noErr, selectedDeviceUIDs[Self.identity(queue)])
        }
    }

    func allocateBuffer(
        on queue: AudioQueueRef,
        byteCount: UInt32
    ) -> (
        status: OSStatus,
        buffer: AudioQueueBufferRef?
    ) {
        lock.withLock {
            let identity =
                Self.identity(queue)
            guard var state = queues[identity],
                  !state.disposed else {
                return (kAudio_ParamError, nil)
            }
            let allocation =
                RuntimeDisposalBufferAllocation(
                    capacity: byteCount
                )
            state.allocations.append(allocation)
            queues[identity] = state
            return (noErr, allocation.buffer)
        }
    }

    func enqueueBuffer(
        _ buffer: AudioQueueBufferRef,
        on queue: AudioQueueRef
    ) -> OSStatus {
        lock.withLock {
            let identity =
                Self.identity(queue)
            guard let state = queues[identity],
                  !state.disposed,
                  state.allocations.contains(
                    where: {
                        $0.buffer == buffer
                            && !$0.isFreed
                    }
                  ) else {
                return kAudio_ParamError
            }
            return noErr
        }
    }

    func startQueue(
        _ queue: AudioQueueRef
    ) -> OSStatus {
        noErr
    }

    func stopQueue(
        _ queue: AudioQueueRef,
        immediate: Bool
    ) -> OSStatus {
        noErr
    }

    func freeBuffer(
        _ buffer: AudioQueueBufferRef,
        from queue: AudioQueueRef
    ) -> OSStatus {
        lock.withLock {
            let identity =
                Self.identity(queue)
            guard let state = queues[identity],
                  let allocation =
                    state.allocations.first(
                        where: {
                            $0.buffer == buffer
                        }
                    ) else {
                return kAudio_ParamError
            }
            allocation.freeIfNeeded()
            return noErr
        }
    }

    func disposeQueue(
        _ queue: AudioQueueRef,
        immediate: Bool
    ) -> OSStatus {
        lock.withLock {
            let identity =
                Self.identity(queue)
            guard var state = queues[identity],
                  !state.disposed else {
                preconditionFailure(
                    "AudioQueueDispose was called twice for terminal queue \(identity)"
                )
            }
            let status =
                disposeIndex
                    < disposeStatuses.count
                ? disposeStatuses[disposeIndex]
                : noErr
            disposeIndex += 1
            eventStorage.append(
                "dispose:\(identity):\(status)"
            )
            state.disposed = true
            for allocation in state.allocations {
                allocation.freeIfNeeded()
            }
            queues[identity] = state
            return status
        }
    }

    private static func identity(
        _ queue: AudioQueueRef
    ) -> UInt {
        UInt(bitPattern: queue)
    }
}

private final class RuntimeDisposalBufferAllocation:
    @unchecked Sendable
{
    let buffer: AudioQueueBufferRef
    private let lock = NSLock()
    private var data:
        UnsafeMutableRawPointer?
    private var bufferStorage:
        UnsafeMutablePointer<AudioQueueBuffer>?

    init(capacity: UInt32) {
        let byteCount = max(1, Int(capacity))
        let data = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<Int16>.alignment
        )
        data.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: byteCount
        )
        let storage =
            UnsafeMutablePointer<AudioQueueBuffer>
                .allocate(capacity: 1)
        storage.initialize(
            to: AudioQueueBuffer(
                mAudioDataBytesCapacity: capacity,
                mAudioData: data,
                mAudioDataByteSize: 0,
                mUserData: nil,
                mPacketDescriptionCapacity: 0,
                mPacketDescriptions: nil,
                mPacketDescriptionCount: 0
            )
        )
        self.data = data
        bufferStorage = storage
        buffer = storage
    }

    deinit {
        freeIfNeeded()
    }

    var isFreed: Bool {
        lock.withLock {
            bufferStorage == nil
        }
    }

    func freeIfNeeded() {
        lock.lock()
        let data = self.data
        let storage = bufferStorage
        self.data = nil
        bufferStorage = nil
        lock.unlock()

        if let storage {
            storage.deinitialize(count: 1)
            storage.deallocate()
        }
        data?.deallocate()
    }
}

private final class DriverTestTrack: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var disableHook: (() -> Void)?
    private var disableHookCalls = 0
    private var disabledCalls = 0

    var isEnabled: Bool {
        lock.withLock { enabled }
    }

    func setEnabled(_ enabled: Bool) {
        let hook = lock.withLock { () -> (() -> Void)? in
            self.enabled = enabled
            guard !enabled else { return nil }
            disabledCalls += 1
            let hook = disableHook
            disableHook = nil
            if hook != nil { disableHookCalls += 1 }
            return hook
        }
        hook?()
    }

    func setOneShotDisableHook(_ hook: @escaping () -> Void) {
        lock.withLock {
            precondition(disableHook == nil)
            disableHook = hook
        }
    }

    var cleanupHookCount: Int {
        lock.withLock { disableHookCalls }
    }

    var disableCount: Int {
        lock.withLock { disabledCalls }
    }
}

private final class DriverTestMediaFreshnessWatchdog:
    @unchecked Sendable
{
    private struct Waiter {
        let deadline: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var currentNanoseconds: UInt64
    private var waiters: [Waiter] = []
    private var scheduledDeadlineCount = 0
    private var nowReads = 0
    private var nowHook: (() -> Void)?
    private var nowHookCalls = 0

    init(now: UInt64 = 0) {
        currentNanoseconds = now
    }

    var now: UInt64 {
        let capture = lock.withLock { () -> (UInt64, (() -> Void)?) in
            nowReads += 1
            let hook = nowHook
            nowHook = nil
            if hook != nil { nowHookCalls += 1 }
            return (currentNanoseconds, hook)
        }
        capture.1?()
        return capture.0
    }

    func setOneShotNowHook(_ hook: @escaping () -> Void) {
        lock.withLock {
            precondition(nowHook == nil)
            nowHook = hook
        }
    }

    var nowHookCount: Int { lock.withLock { nowHookCalls } }

    var nowReadCount: Int {
        lock.withLock { nowReads }
    }

    func sleep(until deadline: UInt64) async throws {
        if Task.isCancelled {
            throw CancellationError()
        }
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                scheduledDeadlineCount += 1
                guard currentNanoseconds < deadline else {
                    return true
                }
                waiters.append(
                    Waiter(
                        deadline: deadline,
                        continuation: continuation
                    )
                )
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    func advance(to nanoseconds: UInt64) {
        setNowWithoutDelivering(to: nanoseconds)
        deliverDueDeadlines()
    }

    func setNowWithoutDelivering(to nanoseconds: UInt64) {
        lock.withLock {
            currentNanoseconds = max(
                currentNanoseconds,
                nanoseconds
            )
        }
    }

    func deliverDueDeadlines() {
        let ready = lock.withLock { () -> [Waiter] in
            let ready = waiters.filter {
                $0.deadline <= currentNanoseconds
            }
            waiters.removeAll {
                $0.deadline <= currentNanoseconds
            }
            return ready
        }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }

    var scheduleCount: Int {
        lock.withLock { scheduledDeadlineCount }
    }
}

private actor DriverSuspensionGate {
    private var isOpen = false
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        entered = true
        await withCheckedContinuation {
            waiters.append($0)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let continuations = waiters
        waiters.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume()
        }
    }

    func hasEntered() -> Bool {
        entered
    }
}

private enum DriverTestError: Error {
    case start
    case admission
    case wrongOutputType
}

private extension NSLock {
    func withLock<T>(
        _ body: () throws -> T
    ) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
#endif
