import AppKit
import CoreServices
import WebRTCTransport
import XCTest
@testable import CaptureServer

private final class MusicTestBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func read() -> Value { lock.withLock { value } }
    func set(_ value: Value) { lock.withLock { self.value = value } }
}

private final class MusicTestBackend: MacMusicNowPlayingBackend, @unchecked Sendable {
    var snapshot: MacMusicPlayerSnapshot? = musicTestSnapshot()
    var error: MacMusicBackendError?
    var commandError: MacMusicBackendError?
    var commands: [MacMusicCommand] = []
    var permissions = 0
    var reads = 0
    var onCommand: ((MacMusicCommand) -> Void)?

    func requestAutomationPermission() throws { permissions += 1; if let error { throw error } }
    func readSnapshot(deadline: TimeInterval) throws -> MacMusicPlayerSnapshot? {
        reads += 1
        if let error { throw error }
        return snapshot
    }
    func send(
        _ command: MacMusicCommand, expected: MacMusicPlayerSnapshot, deadline: TimeInterval,
        isAuthorized: @escaping @Sendable () -> Bool
    ) throws -> WebRTCRemoteMediaCommandResult {
        guard isAuthorized(), snapshot?.hasSameItem(as: expected) == true else { return .staleContext }
        commands.append(command)
        if let commandError { throw commandError }
        onCommand?(command)
        return .applied
    }
}

private final class MusicSelectionTestBrowser: MacSystemNowPlayingRuntime, @unchecked Sendable {
    let isAvailable = true
    private let token = MacNowPlayingClientToken(object: NSObject(), clientIdentity: "fixed-browser")
    func fetchSnapshot(completion: @escaping @Sendable (MacNowPlayingRuntimeSnapshotResult) -> Void) {
        completion(.snapshot(.init(client: token, sourceName: "YouTube",
            metadata: .init(title: "Browser track", artist: nil, album: nil, duration: 120,
                elapsedTime: 10, playbackRate: 1, timestamp: Date(timeIntervalSince1970: 200),
                contentIdentifier: "browser-item", uniqueIdentifier: nil), enabledCommands: [1, 6, 7])))
    }
    func send(rawCommand: Int, snapshot: MacNowPlayingRuntimeSnapshot,
              isAuthorized: @escaping @Sendable () -> Bool,
              completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        XCTFail("The secondary Music selection must not route a command to the browser")
        completion(.failed)
    }
}

private func musicTestSnapshot(
    trackID: String = "0000000000000002", title: String = "Track", state: MacMusicPlaybackState = .playing,
    duration: Double? = 120, position: Double? = 15
) -> MacMusicPlayerSnapshot {
    MacMusicPlayerSnapshot(
        owner: MacMusicPlayerIdentity(processID: 42, launchDate: Date(timeIntervalSince1970: 100)),
        trackID: trackID, title: title, artist: "Artist", album: "Album", duration: duration,
        position: position, state: state, observedAt: Date(timeIntervalSince1970: 200),
        navigation: MacMusicNavigation(playlistID: "00000000000000AB", index: 2, count: 3,
                                      nextTrackID: "0000000000000003", previousTrackID: "0000000000000001")
    )
}

/// Responds to real descriptor queries and records the target state changed by command events.
private final class MusicTestAppleEventsClient: MacMusicAppleEventsClient, @unchecked Sendable {
    var owner: MacMusicPlayerIdentity? = musicTestSnapshot().owner
    var hasPlaylist = true
    var index: Int32 = 2
    var indexHint: Int32?
    var state: OSType = 0x6B505350
    var duration = 120.0
    var position = 15.0
    var shuffle = false
    var repeatCode: OSType = 0x6B52704F
    var disabled: Set<Int32> = []
    var permissionStatus: OSStatus = noErr
    var eventError: OSStatus?
    var permissionRequests = 0
    var commandEvents: [AEEventID] = []
    var positionWrites: [Double] = []
    var setError: OSStatus?
    var onSet: (() -> Void)?
    var options: [NSAppleEventDescriptor.SendOptions] = []
    var timeouts: [TimeInterval] = []
    var targets: [Int32] = []
    var onProperty: ((AEKeyword) -> Void)?
    var ignoreCommands = false
    let trackIDs = ["0000000000000001", "0000000000000002", "0000000000000003"]

    func runningOwner() -> MacMusicPlayerIdentity? { owner }
    func requestPermission(owner: MacMusicPlayerIdentity) -> OSStatus {
        permissionRequests += 1
        return permissionStatus
    }
    func sendEvent(
        _ event: NSAppleEventDescriptor, options: NSAppleEventDescriptor.SendOptions, timeout: TimeInterval
    ) throws -> NSAppleEventDescriptor {
        self.options.append(options)
        timeouts.append(timeout)
        if let address = event.attributeDescriptor(forKeyword: keyAddressAttr) {
            XCTAssertEqual(address.descriptorType, typeKernelProcessID)
            XCTAssertEqual(address.data.count, MemoryLayout<Int32>.size)
            targets.append(address.data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        } else { XCTFail("Missing PID target") }
        if let eventError { throw NSError(domain: NSOSStatusErrorDomain, code: Int(eventError)) }
        let result: NSAppleEventDescriptor
        if event.eventClass == 0x686F6F6B {
            commandEvents.append(event.eventID)
            if !ignoreCommands {
                switch event.eventID {
                case 0x506C6179: state = 0x6B505350
                case 0x50617573: state = 0x6B505370
                case 0x4E657874: index = index == 3 ? 1 : index + 1
                case 0x50726576: index = index == 1 ? 3 : index - 1
                default: XCTFail("Unexpected command")
                }
            }
            result = .null()
        } else if event.eventID == kAESetData {
            XCTAssertEqual(event.eventClass, kAECoreSuite)
            let object = try XCTUnwrap(event.paramDescriptor(forKeyword: keyDirectObject))
            XCTAssertEqual(object.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue, typeProperty)
            XCTAssertEqual(object.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue, 0x70506F73)
            XCTAssertEqual(object.forKeyword(AEKeyword(keyAEContainer))?.descriptorType, typeNull)
            let target = try XCTUnwrap(event.paramDescriptor(forKeyword: keyAEData))
            XCTAssertEqual(target.descriptorType, typeIEEE64BitFloatingPoint)
            positionWrites.append(target.doubleValue)
            if !ignoreCommands { position = target.doubleValue }
            onSet?()
            if let setError { throw NSError(domain: NSOSStatusErrorDomain, code: Int(setError)) }
            result = .null()
        } else if event.eventID == kAECountElements {
            XCTAssertEqual(event.paramDescriptor(forKeyword: keyAEObjectClass)?.typeCodeValue, 0x6354726B)
            result = .init(int32: 3)
        } else {
            XCTAssertEqual(event.eventClass, kAECoreSuite)
            XCTAssertEqual(event.eventID, kAEGetData)
            let object = try XCTUnwrap(event.paramDescriptor(forKeyword: keyDirectObject))
            let property = try XCTUnwrap(object.forKeyword(AEKeyword(keyAEKeyData))).typeCodeValue
            let container = object.forKeyword(AEKeyword(keyAEContainer))
            let containerClass = container?.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue
            let trackIndex = container?.forKeyword(AEKeyword(keyAEKeyData))?.int32Value ?? index
            onProperty?(property)
            switch property {
            case 0x70506C53: result = .init(enumCode: state)
            case 0x7054726B: result = Self.object(classCode: 0x6354726B, index: index)
            case 0x70506C61: result = hasPlaylist ? Self.object(classCode: 0x63506C79, index: 1) : .null()
            case 0x70504953:
                if container?.forKeyword(AEKeyword(keyAEKeyData))?.enumCodeValue == OSType(kAEAll) {
                    result = .list()
                    for (index, identifier) in trackIDs.enumerated() {
                        result.insert(.init(string: identifier), at: index + 1)
                    }
                } else {
                    result = .init(string: containerClass == 0x63506C79
                                   ? "00000000000000AB" : trackIDs[Int(trackIndex - 1)])
                }
            case 0x706E616D: result = .init(string: "Track \(trackIndex)")
            case 0x70417274: result = .init(string: "Artist")
            case 0x70416C62: result = .init(string: "Album")
            case 0x70447572: result = .init(double: duration)
            case 0x70506F73: result = .init(double: position)
            case 0x70536845: result = .init(boolean: shuffle)
            case 0x70527074: result = .init(enumCode: repeatCode)
            case 0x70696478: result = .init(int32: indexHint ?? trackIndex)
            case 0x656E626C: result = .init(boolean: !disabled.contains(trackIndex))
            default: XCTFail("Unexpected property \(property)"); result = .null()
            }
        }
        let reply = NSAppleEventDescriptor(
            eventClass: kCoreEventClass, eventID: kAEAnswer, targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        reply.setParam(result, forKeyword: keyDirectObject)
        return reply
    }

    private static func object(classCode: OSType, index: Int32) -> NSAppleEventDescriptor {
        let object = NSAppleEventDescriptor.record()
        object.setDescriptor(.init(typeCode: classCode), forKeyword: AEKeyword(keyAEDesiredClass))
        object.setDescriptor(.null(), forKeyword: AEKeyword(keyAEContainer))
        object.setDescriptor(.init(enumCode: OSType(formAbsolutePosition)), forKeyword: AEKeyword(keyAEKeyForm))
        object.setDescriptor(.init(int32: index), forKeyword: AEKeyword(keyAEKeyData))
        return object.coerce(toDescriptorType: typeObjectSpecifier)!
    }
}

final class MacMusicNowPlayingRuntimeTests: XCTestCase {
    func testNoPlayerDoesNotSendEventsOrRequestPermission() throws {
        let client = MusicTestAppleEventsClient()
        client.owner = nil
        let backend = MacMusicAppleEventsBackend(client: client)
        XCTAssertNil(try backend.readSnapshot(deadline: deadline()))
        XCTAssertThrowsError(try backend.requestAutomationPermission())
        XCTAssertTrue(client.options.isEmpty)
        XCTAssertEqual(client.permissionRequests, 0)
    }

    func testDenialNeverPromptsAndExplicitOnboardingUsesExactOwner() async {
        let client = MusicTestAppleEventsClient()
        client.eventError = -1743
        let runtime = MacMusicNowPlayingRuntime(backend: MacMusicAppleEventsBackend(client: client))
        guard case .noActiveMedia = await fetch(runtime) else { return XCTFail("Denied source published") }
        XCTAssertEqual(runtime.lastDiscoveryStatus, .permissionDenied)
        XCTAssertEqual(client.permissionRequests, 0)
        client.permissionStatus = -1743
        let denied = await withCheckedContinuation { continuation in
            runtime.requestAutomationPermission { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(denied)
        XCTAssertEqual(client.permissionRequests, 1)
        XCTAssertTrue(client.options.allSatisfy {
            $0.rawValue & UInt(kAENeverInteract | kAEDoNotPromptForUserConsent)
                == UInt(kAENeverInteract | kAEDoNotPromptForUserConsent)
        })
    }

    func testPublicDescriptorReadPublishesRealMetadataAndBoundedPIDEvents() throws {
        let client = MusicTestAppleEventsClient()
        let snapshot = try XCTUnwrap(MacMusicAppleEventsBackend(client: client).readSnapshot(deadline: deadline()))
        XCTAssertEqual(snapshot.trackID, "0000000000000002")
        XCTAssertEqual(snapshot.title, "Track 2")
        XCTAssertEqual(snapshot.artist, "Artist")
        XCTAssertEqual(snapshot.album, "Album")
        XCTAssertEqual(snapshot.duration, 120)
        XCTAssertEqual(snapshot.position, 15)
        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(snapshot.enabledCommands, [1, 4, 5, 6, 7])
        XCTAssertTrue(client.timeouts.allSatisfy { $0 > 0 && $0 <= 0.25 })
        XCTAssertTrue(client.targets.allSatisfy { $0 == 42 })
        XCTAssertEqual(client.permissionRequests, 0)
    }

    func testPlaylistBoundariesRepeatShuffleAndUncheckedTracksAffectCapabilities() throws {
        let client = MusicTestAppleEventsClient()
        let backend = MacMusicAppleEventsBackend(client: client)
        client.index = 1
        client.state = 0x6B505370
        XCTAssertEqual(try backend.readSnapshot(deadline: deadline())?.enabledCommands, [0, 4, 6, 7])
        client.index = 3
        XCTAssertEqual(try backend.readSnapshot(deadline: deadline())?.enabledCommands, [0, 5, 6, 7])
        client.repeatCode = 0x6B416C6C
        XCTAssertEqual(try backend.readSnapshot(deadline: deadline())?.enabledCommands, [0, 4, 5, 6, 7])
        client.shuffle = true
        XCTAssertEqual(try backend.readSnapshot(deadline: deadline())?.enabledCommands, [0, 6, 7])
        client.shuffle = false
        client.index = 2
        client.disabled = [1, 3]
        XCTAssertEqual(try backend.readSnapshot(deadline: deadline())?.enabledCommands, [0, 6, 7])
        client.hasPlaylist = false
        XCTAssertEqual(try backend.readSnapshot(deadline: deadline())?.enabledCommands, [0, 6, 7])
    }

    func testTrackReplacementDuringMetadataReadRejectsMixedSnapshot() {
        let client = MusicTestAppleEventsClient()
        client.onProperty = { property in if property == 0x706E616D { client.index = 3 } }
        XCTAssertThrowsError(try MacMusicAppleEventsBackend(client: client).readSnapshot(deadline: deadline())) {
            XCTAssertEqual($0 as? MacMusicBackendError, .staleItem)
        }
    }

    func testLibraryIndexIsResolvedAgainstExactCurrentPlaylistTrackIDs() throws {
        let client = MusicTestAppleEventsClient()
        client.indexHint = 10_000
        let snapshot = try XCTUnwrap(MacMusicAppleEventsBackend(client: client).readSnapshot(deadline: deadline()))
        XCTAssertEqual(snapshot.navigation?.index, 2)
        XCTAssertEqual(snapshot.enabledCommands, [1, 4, 5, 6, 7])
    }

    func testRevocationAtFinalIdentityReadPreventsAppleEventDispatch() throws {
        let client = MusicTestAppleEventsClient()
        client.hasPlaylist = false
        let backend = MacMusicAppleEventsBackend(client: client)
        let snapshot = try XCTUnwrap(backend.readSnapshot(deadline: deadline()))
        let authorization = WebRTCControlAuthorization()
        var identityReads = 0
        client.onProperty = { property in
            if property == 0x70504953 {
                identityReads += 1
                if identityReads == 3 { authorization.revoke() }
            }
        }
        XCTAssertThrowsError(try backend.send(.pause, expected: snapshot, deadline: deadline(),
                                             isAuthorized: { authorization.isValid })) {
            XCTAssertEqual($0 as? MacMusicBackendError, .staleItem)
        }
        XCTAssertFalse(authorization.isValid)
        XCTAssertTrue(client.commandEvents.isEmpty)
        XCTAssertEqual(client.state, 0x6B505350)
    }

    func testOwnerAndItemReplacementBeforeCommandCannotChangeNewTarget() throws {
        let client = MusicTestAppleEventsClient()
        let backend = MacMusicAppleEventsBackend(client: client)
        let snapshot = try XCTUnwrap(backend.readSnapshot(deadline: deadline()))
        client.index = 3
        XCTAssertEqual(try backend.send(.pause, expected: snapshot, deadline: deadline(), isAuthorized: { true }), .staleContext)
        client.index = 2
        client.owner = MacMusicPlayerIdentity(processID: 42, launchDate: Date(timeIntervalSince1970: 101))
        XCTAssertEqual(try backend.send(.pause, expected: snapshot, deadline: deadline(), isAuthorized: { true }), .staleContext)
        XCTAssertTrue(client.commandEvents.isEmpty)
    }

    func testAbsoluteAndRelativeCommandsRequireActualTargetReadback() throws {
        let client = MusicTestAppleEventsClient()
        let backend = MacMusicAppleEventsBackend(client: client)
        for command in [MacMusicCommand.pause, .play, .next, .previous] {
            let snapshot = try XCTUnwrap(backend.readSnapshot(deadline: deadline()))
            XCTAssertEqual(try backend.send(command, expected: snapshot, deadline: deadline(), isAuthorized: { true }), .applied)
        }
        XCTAssertEqual(client.state, 0x6B505350)
        XCTAssertEqual(client.index, 2)
        XCTAssertEqual(client.commandEvents, [0x50617573, 0x506C6179, 0x4E657874, 0x50726576])
        client.ignoreCommands = true
        let snapshot = try XCTUnwrap(backend.readSnapshot(deadline: deadline()))
        XCTAssertEqual(try backend.send(.pause, expected: snapshot, deadline: deadline(), isAuthorized: { true }), .failed)
        XCTAssertEqual(try backend.send(.next, expected: snapshot, deadline: deadline(), isAuthorized: { true }), .failed)
    }

    func testSeekSetsExactPositionOnceClampsAndPreservesTrackAndPlayback() throws {
        for (command, origin, target) in [(MacMusicCommand.seekForward30, 15.0, 45.0),
                                          (.seekBackward30, 70, 40), (.seekForward30, 115, 120),
                                          (.seekBackward30, 5, 0)] {
            let client = MusicTestAppleEventsClient(); client.position = origin
            let backend = MacMusicAppleEventsBackend(client: client)
            let snapshot = try XCTUnwrap(backend.readSnapshot(deadline: deadline()))
            XCTAssertEqual(try backend.send(command, expected: snapshot, deadline: deadline(), isAuthorized: { true }), .applied)
            XCTAssertEqual(client.positionWrites, [target])
            XCTAssertEqual(client.position, target)
            XCTAssertEqual(client.index, 2)
            XCTAssertEqual(client.state, 0x6B505350)
            XCTAssertTrue(client.commandEvents.isEmpty)
            XCTAssertTrue(command.isRelative)
            XCTAssertFalse(command.changesTrack)
        }
    }

    func testSeekCapabilityRejectsMissingOrInvalidTimelineAndStoppedPlayer() {
        for snapshot in [musicTestSnapshot(duration: nil), musicTestSnapshot(duration: 0),
                         musicTestSnapshot(duration: .infinity), musicTestSnapshot(duration: 31_536_001),
                         musicTestSnapshot(position: nil), musicTestSnapshot(position: -1),
                         musicTestSnapshot(position: 121), musicTestSnapshot(position: .nan),
                         musicTestSnapshot(state: .stopped)] {
            XCTAssertFalse(snapshot.enabledCommands.contains(6))
            XCTAssertFalse(snapshot.enabledCommands.contains(7))
        }
        XCTAssertEqual(musicTestSnapshot(state: .paused).enabledCommands, [0, 4, 5, 6, 7])
    }

    func testSeekRequiresActualPositionReadbackAndNeverResendsTimeout() throws {
        let client = MusicTestAppleEventsClient(), backend = MacMusicAppleEventsBackend(client: client)
        let snapshot = try XCTUnwrap(backend.readSnapshot(deadline: deadline()))
        client.ignoreCommands = true
        XCTAssertEqual(try backend.send(.seekForward30, expected: snapshot, deadline: deadline(), isAuthorized: { true }), .failed)
        XCTAssertEqual(client.position, 15)
        client.ignoreCommands = false; client.setError = OSStatus(errAETimeout)
        XCTAssertThrowsError(try backend.send(.seekForward30, expected: snapshot, deadline: deadline(), isAuthorized: { true })) {
            XCTAssertEqual($0 as? MacMusicBackendError, .timedOut)
        }
        XCTAssertEqual(client.position, 45)
        XCTAssertEqual(client.positionWrites, [45, 45])
    }

    func testSeekFinalIdentityAuthorizationAndDeadlineFencesPreventMutation() throws {
        for mutation in ["track", "owner", "authorization", "deadline"] {
            let clock = MusicTestBox<TimeInterval>(10)
            let client = MusicTestAppleEventsClient(); client.hasPlaylist = false
            let backend = MacMusicAppleEventsBackend(client: client, now: { clock.read() })
            let snapshot = try XCTUnwrap(backend.readSnapshot(deadline: 11))
            let authorization = WebRTCControlAuthorization()
            var positions = 0
            client.onProperty = { property in
                if property == 0x70506F73 {
                    positions += 1
                    if positions == 2 {
                        switch mutation {
                        case "track": client.index = 3
                        case "owner": client.owner = .init(processID: 43, launchDate: snapshot.owner.launchDate)
                        case "authorization": authorization.revoke()
                        default: clock.set(12)
                        }
                    }
                }
            }
            do {
                let result = try backend.send(.seekForward30, expected: snapshot, deadline: 11,
                                              isAuthorized: { authorization.isValid })
                XCTAssertEqual(result, .staleContext)
            } catch {
                XCTAssertTrue([MacMusicBackendError.staleItem, .timedOut].contains(error as? MacMusicBackendError ?? .invalidData))
            }
            XCTAssertEqual(positions, 2)
            XCTAssertTrue(client.positionWrites.isEmpty, mutation)
        }
    }

    func testSeekReadbackRejectsTargetReplacementAfterDispatch() throws {
        let client = MusicTestAppleEventsClient(), backend = MacMusicAppleEventsBackend(client: client)
        let snapshot = try XCTUnwrap(backend.readSnapshot(deadline: deadline()))
        client.onSet = { client.index = 3 }
        XCTAssertEqual(try backend.send(.seekForward30, expected: snapshot, deadline: deadline(), isAuthorized: { true }), .staleContext)
        XCTAssertEqual(client.positionWrites, [45])
    }

    func testSeekTimeoutConsumesRuntimeAuthorityAndFreshSnapshotAllowsNewIntent() async throws {
        for command in [6, 7] {
            let backend = MusicTestBackend(); backend.commandError = .timedOut
            let runtime = MacMusicNowPlayingRuntime(backend: backend)
            let old = try await snapshot(runtime)
            let initial = await send(runtime, command: command, snapshot: old)
            let replay = await send(runtime, command: command, snapshot: old)
            XCTAssertEqual(initial, .failed); XCTAssertEqual(replay, .staleContext)
            let fresh = try await snapshot(runtime)
            XCTAssertFalse(old.client === fresh.client)
            let stale = await send(runtime, command: command, snapshot: old)
            XCTAssertEqual(stale, .staleContext)
            backend.commandError = nil
            let renewed = await send(runtime, command: command, snapshot: fresh)
            XCTAssertEqual(renewed, .applied)
            XCTAssertEqual(backend.commands.count, 2)
        }
    }

    func testConfirmedSeekPreservesItemTokenOnlyAfterFreshSameItemRead() async throws {
        for command in [6, 7] {
            let backend = MusicTestBackend()
            let runtime = MacMusicNowPlayingRuntime(backend: backend)
            let old = try await snapshot(runtime)
            let initial = await send(runtime, command: command, snapshot: old)
            let beforeRead = await send(runtime, command: command, snapshot: old)
            XCTAssertEqual(initial, .applied)
            XCTAssertEqual(beforeRead, .staleContext)
            let fresh = try await snapshot(runtime)
            XCTAssertTrue(old.client === fresh.client, "Confirmed seek is not a new source or item")
            let nextIntent = await send(runtime, command: command, snapshot: fresh)
            XCTAssertEqual(nextIntent, .applied)
            XCTAssertEqual(backend.commands.count, 2)
            backend.snapshot = musicTestSnapshot(trackID: "0000000000000003")
            let replacement = try await snapshot(runtime)
            XCTAssertFalse(replacement.client === fresh.client)
            let stale = await send(runtime, command: command, snapshot: fresh)
            XCTAssertEqual(stale, .staleContext)
            XCTAssertEqual(backend.commands.count, 2)
        }
    }

    func testSecondaryMusicSeekKeepsPublishedContextAndPreparedCommandCannotReplay() async throws {
        let backend = MusicTestBackend()
        backend.onCommand = { command in
            if command == .seekForward30 { backend.snapshot = musicTestSnapshot(position: 45) }
            if command == .pause { backend.snapshot = musicTestSnapshot(state: .paused, position: 45) }
        }
        let runtime = MacSupportedNowPlayingRuntime(browser: MusicSelectionTestBrowser(),
            music: MacMusicNowPlayingRuntime(backend: backend))
        let controller = MacSystemNowPlayingController(runtime: runtime, now: { Date(timeIntervalSince1970: 200) })
        defer { controller.stop() }
        let latest = MusicTestBox<WebRTCRemoteMediaStateUpdate?>(nil)
        let initial = expectation(description: "Initial two-source catalog")
        let seeked = expectation(description: "Music seek readback")
        controller.start { state in
            latest.set(state)
            if state.additionalItems.first?.elapsedTime == 15 { initial.fulfill() }
            if state.additionalItems.first?.elapsedTime == 45,
               state.additionalItems.first?.playbackState == .playing { seeked.fulfill() }
        }
        await fulfillment(of: [initial], timeout: 2)
        let initialState = try XCTUnwrap(latest.read())
        XCTAssertEqual(initialState.item?.sourceName, "YouTube")
        let music = try XCTUnwrap(initialState.additionalItems.first)
        let prepared = try XCTUnwrap(controller.prepareCommand(.seekForward30, contextID: music.contextID,
                                                               isAuthorized: { true }))
        let result = await controller.perform(prepared)
        XCTAssertEqual(result, .applied)
        await fulfillment(of: [seeked], timeout: 2)
        XCTAssertEqual(latest.read()?.additionalItems.first?.contextID, music.contextID)
        let replay = await controller.perform(prepared)
        XCTAssertEqual(replay, .staleContext)
        let pause = try XCTUnwrap(controller.prepareCommand(.pause, contextID: music.contextID,
                                                            isAuthorized: { true }))
        let paused = await controller.perform(pause)
        XCTAssertEqual(paused, .applied)
        XCTAssertEqual(backend.commands, [.seekForward30, .pause])
    }

    func testQueuedRevocationPreventsBackendCommand() async throws {
        let backend = MusicTestBackend()
        let queue = DispatchQueue(label: "music-test-revocation")
        let runtime = MacMusicNowPlayingRuntime(backend: backend, queue: queue)
        let snapshot = try await snapshot(runtime)
        let authorization = WebRTCControlAuthorization()
        queue.suspend()
        let result = MusicTestBox<WebRTCRemoteMediaCommandResult?>(nil)
        let finished = expectation(description: "revoked command returned")
        runtime.send(rawCommand: 1, snapshot: snapshot, isAuthorized: { authorization.isValid }) {
            result.set($0); finished.fulfill()
        }
        authorization.revoke()
        queue.resume()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(result.read(), .staleContext)
        XCTAssertTrue(backend.commands.isEmpty)
    }

    func testDiscoveryStatusDistinguishesNoPlayerAndFailureWithoutContent() async {
        let backend = MusicTestBackend()
        backend.snapshot = nil
        let runtime = MacMusicNowPlayingRuntime(backend: backend)
        _ = await fetch(runtime)
        XCTAssertEqual(runtime.lastDiscoveryStatus, .noPlayer)
        for (error, status) in [(MacMusicBackendError.permissionRequired, MacMusicDiscoveryStatus.permissionRequired),
                                (.permissionDenied, .permissionDenied), (.timedOut, .timedOut),
                                (.staleItem, .staleItem), (.invalidData, .invalidData)] {
            backend.error = error
            _ = await fetch(runtime)
            XCTAssertEqual(runtime.lastDiscoveryStatus, status)
        }
        XCTAssertEqual(backend.permissions, 0)
    }

    func testFetchAdmissionIsBoundedAndExpiredQueuedWorkDoesNotReadPlayer() async {
        let backend = MusicTestBackend()
        let clock = MusicTestBox<TimeInterval>(10)
        let queue = DispatchQueue(label: "music-test-deadline")
        let runtime = MacMusicNowPlayingRuntime(backend: backend, queue: queue, now: { clock.read() })
        queue.suspend()
        let first = expectation(description: "expired fetch")
        runtime.fetchSnapshot { result in
            guard case .noActiveMedia = result else { return XCTFail("Expired fetch published") }
            first.fulfill()
        }
        guard case .retry = await fetch(runtime) else {
            queue.resume()
            return XCTFail("Duplicate fetch queued")
        }
        clock.set(12)
        queue.resume()
        await fulfillment(of: [first], timeout: 2)
        XCTAssertEqual(backend.reads, 0)
        XCTAssertEqual(runtime.lastDiscoveryStatus, .timedOut)
    }

    func testRelativeTimeoutConsumesSnapshotAndCannotReplayAcrossRefresh() async throws {
        let backend = MusicTestBackend()
        backend.commandError = .timedOut
        let runtime = MacMusicNowPlayingRuntime(backend: backend)
        let old = try await snapshot(runtime)
        let initial = await send(runtime, command: 4, snapshot: old)
        let replay = await send(runtime, command: 4, snapshot: old)
        XCTAssertEqual(initial, .failed)
        XCTAssertEqual(replay, .staleContext)
        let fresh = try await snapshot(runtime)
        XCTAssertFalse(old.client === fresh.client)
        let stale = await send(runtime, command: 4, snapshot: old)
        let renewed = await send(runtime, command: 4, snapshot: fresh)
        XCTAssertEqual(stale, .staleContext)
        XCTAssertEqual(renewed, .failed)
        XCTAssertEqual(backend.commands, [.next, .next])
    }

    func testMetadataSanitizationRejectsBadIdentityAndBoundsTextAndTime() {
        XCTAssertNil(MacMusicNowPlayingRuntime.metadata(musicTestSnapshot(trackID: "invalid")))
        XCTAssertNil(MacMusicNowPlayingRuntime.metadata(musicTestSnapshot(title: "\u{0}\n\t")))
        let bounded = MacMusicNowPlayingRuntime.metadata(musicTestSnapshot(
            title: "\u{0} " + String(repeating: "é", count: 2_000), duration: 120, position: 999
        ))
        XCTAssertLessThanOrEqual(bounded?.title?.utf8.count ?? .max, WebRTCRemoteMediaItem.maximumTitleBytes)
        XCTAssertEqual(bounded?.elapsedTime, 120)
        let invalid = MacMusicNowPlayingRuntime.metadata(musicTestSnapshot(duration: .infinity, position: .nan))
        XCTAssertNil(invalid?.duration)
        XCTAssertNil(invalid?.elapsedTime)
    }

    private func deadline() -> TimeInterval { ProcessInfo.processInfo.systemUptime + 5 }
    private func fetch(_ runtime: MacMusicNowPlayingRuntime) async -> MacNowPlayingRuntimeSnapshotResult {
        await withCheckedContinuation { continuation in runtime.fetchSnapshot { continuation.resume(returning: $0) } }
    }
    private func snapshot(_ runtime: MacMusicNowPlayingRuntime) async throws -> MacNowPlayingRuntimeSnapshot {
        guard case let .snapshot(snapshot) = await fetch(runtime) else {
            throw MacMusicBackendError.unavailable
        }
        return snapshot
    }
    private func send(
        _ runtime: MacMusicNowPlayingRuntime, command: Int, snapshot: MacNowPlayingRuntimeSnapshot
    ) async -> WebRTCRemoteMediaCommandResult {
        await withCheckedContinuation { continuation in
            runtime.send(rawCommand: command, snapshot: snapshot, isAuthorized: { true }) { continuation.resume(returning: $0) }
        }
    }
}
