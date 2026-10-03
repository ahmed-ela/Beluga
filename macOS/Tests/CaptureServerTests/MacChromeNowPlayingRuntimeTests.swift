import AppKit
import CoreServices
import WebRTCTransport
import XCTest
@testable import CaptureServer

private final class ChromeTestBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ value: Value) { lock.withLock { self.value = value } }
    func update(_ body: (inout Value) -> Void) { lock.withLock { body(&value) } }
}

private let chromeOwner = MacChromePlayerIdentity(processID: 42, launchDate: Date(timeIntervalSince1970: 100))
private let chromeURL = "https://www.youtube.com/watch?v=abcdefghijk"
private let chromeNextURL = "https://www.youtube.com/watch?v=lmnopqrstuv"

private func chromeMedia(video: String = "abcdefghijk", paused: Bool = false,
                         item: String = "00000000-0000-4000-8000-000000000001", generation: Int64 = 1,
                         title: String = "Video", pageTime: Double = 50_000,
                         document: String = "00000000-0000-4000-8000-000000000002",
                         duration: Double? = 120, elapsed: Double? = 15, canSeek: Bool? = true,
                         continuity: String? = nil) -> MacChromeScriptSnapshot {
    .init(documentID: document, itemID: item, itemGeneration: generation,
          videoID: video, title: title, artist: "Channel", duration: duration, elapsedTime: elapsed,
          playbackRate: 1, paused: paused, observedAtUnixMilliseconds: 1_000_000,
          observedAtPageMilliseconds: pageTime, canPlay: paused, canPause: !paused,
          canNext: true, canPrevious: true, canSeek: canSeek, playbackContinuityID: continuity)
}

private func chromePlayer(tab: String = "2", media: MacChromeScriptSnapshot = chromeMedia(),
                          owner: MacChromePlayerIdentity = chromeOwner, window: String = "1") -> MacChromePlayerSnapshot {
    .init(tab: .init(owner: owner, windowID: window, tabID: tab), media: media, receivedAtUptime: 10)
}

private final class ChromeTestBackend: MacChromeNowPlayingBackend, @unchecked Sendable {
    var snapshots = [chromePlayer()]
    var error: MacChromeBackendError?
    var commandError: MacChromeBackendError?
    var commands: [MacChromeCommand] = []
    var positions: [TimeInterval?] = []
    var commandTargets: [MacChromeTabIdentity] = []
    var reads = 0
    var permissions = 0
    var onPermission: (() -> Void)?
    var onCommand: ((MacChromeCommand) -> Void)?
    var onRead: (() -> Void)?
    func readSnapshots(deadline: TimeInterval) throws -> [MacChromePlayerSnapshot] {
        reads += 1
        if let error { throw error }
        onRead?()
        return snapshots
    }
    func requestAutomationPermission() throws { permissions += 1; onPermission?() }
    func send(_ command: MacChromeCommand, positionSeconds: TimeInterval?, expected: MacChromePlayerSnapshot, deadline: TimeInterval,
              isAuthorized: @escaping @Sendable () -> Bool) throws -> WebRTCRemoteMediaCommandResult {
        guard isAuthorized() else { return .staleContext }
        commands.append(command); commandTargets.append(expected.tab)
        positions.append(positionSeconds)
        if let commandError { throw commandError }
        onCommand?(command)
        return .applied
    }
}

private struct ChromeRecoveryAbsentMusic: MacSystemNowPlayingRuntime {
    var isAvailable: Bool { true }
    func fetchSnapshot(completion: @escaping @Sendable (MacNowPlayingRuntimeSnapshotResult) -> Void) {
        completion(.noActiveMedia)
    }
    func send(rawCommand: Int, snapshot: MacNowPlayingRuntimeSnapshot,
              isAuthorized: @escaping @Sendable () -> Bool,
              completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        XCTFail("Chrome recovery transferred a command to absent Music")
        completion(.failed)
    }
    func stop() {}
}

/// Holds the actual specialized native call after controller admission. Deliberately does not
/// help cancellation in stop(): the controller's own authorization must retire delayed work.
private final class ChromeHeldHandoffRuntime: MacSystemNowPlayingRuntime, @unchecked Sendable {
    let inner: MacChromeNowPlayingRuntime
    let admitted: @Sendable () -> Void
    let completed: @Sendable () -> Void
    let pending = ChromeTestBox<(@Sendable () -> Void)?>(nil)
    var isAvailable: Bool { true }
    init(inner: MacChromeNowPlayingRuntime, admitted: @escaping @Sendable () -> Void,
         completed: @escaping @Sendable () -> Void) {
        self.inner = inner; self.admitted = admitted; self.completed = completed
    }
    func fetchSnapshot(completion: @escaping @Sendable (MacNowPlayingRuntimeSnapshotResult) -> Void) {
        inner.fetchSnapshot(completion: completion)
    }
    func stop() {}
    func send(rawCommand: Int, snapshot: MacNowPlayingRuntimeSnapshot,
              isAuthorized: @escaping @Sendable () -> Bool,
              completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        XCTFail("Handoff fell back to an ordinary command"); completion(.failed)
    }
    func sendHandoffPause(source: MacYouTubeHandoffSource, phonePositionSeconds: Double,
                          snapshot: MacNowPlayingRuntimeSnapshot,
                          isAuthorized: @escaping @Sendable () -> Bool,
                          completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        pending.set { [inner, completed] in
            inner.sendHandoffPause(source: source, phonePositionSeconds: phonePositionSeconds,
                snapshot: snapshot, isAuthorized: isAuthorized) { result in
                    completion(result); completed()
                }
        }
        admitted()
    }
    func release() {
        var action: (@Sendable () -> Void)?
        pending.update { action = $0; $0 = nil }
        action?()
    }
}

/// Executes actual production Apple Event descriptor queries against a changing fake target.
private final class ChromeTestClient: MacChromeAppleEventsClient, @unchecked Sendable {
    struct Window {
        var id: String
        var mode: String = "normal"
        var tabs: [(id: String, url: String)]
    }
    var owner: MacChromePlayerIdentity? = chromeOwner
    var windows = [Window(id: "1", tabs: [("2", chromeURL)])]
    var media = chromeMedia()
    var mediaByTab: [String: MacChromeScriptSnapshot] = [:]
    var errorByTab: [String: OSStatus] = [:]
    var noMediaTabs = Set<String>()
    var scriptTabIDs: [String] = []
    var onReadTab: ((String) -> Void)?
    var permissionStatus: OSStatus = noErr
    var permissionRequests: [Bool] = []
    var options: [NSAppleEventDescriptor.SendOptions] = []
    var timeouts: [TimeInterval] = []
    var targets: [Int32] = []
    var requests: [[String: Any]] = []
    var commandDispatches = 0
    var resultPolls = 0
    var pendingPlay = false
    var ignoreCommands = false
    var commandError: OSStatus?
    var commandReply: (status: String, media: MacChromeScriptSnapshot?)?
    var scriptError: (OSStatus, String)?
    var oversizedResult = false
    var urlReads = 0
    var onURLRead: ((Int) -> Void)?
    var onProperty: ((OSType) -> Void)?
    var onCommandRequest: (([String: Any]) -> Void)?

    func runningOwner() -> MacChromePlayerIdentity? { owner }
    func automationPermission(owner: MacChromePlayerIdentity, askUser: Bool) -> OSStatus {
        XCTAssertEqual(owner, self.owner)
        permissionRequests.append(askUser)
        return permissionStatus
    }

    func sendEvent(_ event: NSAppleEventDescriptor, options: NSAppleEventDescriptor.SendOptions,
                   timeout: TimeInterval) throws -> NSAppleEventDescriptor {
        self.options.append(options); timeouts.append(timeout)
        let target = try XCTUnwrap(event.attributeDescriptor(forKeyword: keyAddressAttr))
        XCTAssertEqual(target.descriptorType, typeKernelProcessID)
        targets.append(target.data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        let result: NSAppleEventDescriptor
        if event.eventClass == 0x43725375 {
            XCTAssertEqual(event.eventID, 0x45784A61)
            let targetTab = try XCTUnwrap(event.paramDescriptor(forKeyword: keyDirectObject))
            XCTAssertEqual(targetTab.forKeyword(AEKeyword(keyAEKeyForm))?.enumCodeValue, OSType(formUniqueID))
            let tabID = try XCTUnwrap(targetTab.forKeyword(AEKeyword(keyAEKeyData))?.stringValue)
            let windowID = targetTab.forKeyword(AEKeyword(keyAEContainer))?.forKeyword(AEKeyword(keyAEKeyData))?.stringValue
            XCTAssertTrue(windows.contains { $0.id == windowID && $0.tabs.contains { $0.id == tabID } })
            scriptTabIDs.append(tabID)
            let script = try XCTUnwrap(event.paramDescriptor(forKeyword: 0x4A765363)?.stringValue)
            let marker = try XCTUnwrap(script.range(of: "\n)(", options: .backwards))
            let request = try XCTUnwrap(JSONSerialization.jsonObject(with:
                Data(script[marker.upperBound...].dropLast().utf8)) as? [String: Any])
            requests.append(request)
            if let scriptError { return answer(.null(), error: scriptError.0, message: scriptError.1) }
            if oversizedResult { return answer(.init(string: String(repeating: "x", count: 262_145))) }
            let operation = request["operation"] as? String
            if operation == "read" {
                onReadTab?(tabID)
                if let error = errorByTab[tabID] { throw NSError(domain: NSOSStatusErrorDomain, code: Int(error)) }
                if noMediaTabs.contains(tabID) { return answer(.init(string: "{\"schemaVersion\":1,\"status\":\"noMedia\"}")) }
            }
            var status = "ok"
            var seekFrom: Double?
            var seekTarget: Double?
            if operation == "command" {
                commandDispatches += 1
                onCommandRequest?(request)
                if let commandReply {
                    var payload: [String: Any] = ["schemaVersion": 1, "status": commandReply.status]
                    if let media = commandReply.media {
                        payload["snapshot"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(media))
                    }
                    return answer(.init(string: String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)))
                }
                if ["seekForward30", "seekBackward30", "seekToPosition"].contains(request["command"] as? String ?? "") {
                    seekFrom = media.elapsedTime
                    seekTarget = min(media.duration ?? 0, max(0, request["positionSeconds"] as? Double ??
                        ((seekFrom ?? 0) + (request["command"] as? String == "seekForward30" ? 30 : -30))))
                }
                if !ignoreCommands {
                    switch request["command"] as? String {
                    case "pause": media = chromeMedia(paused: true)
                    case "play":
                        if pendingPlay { status = "pending" } else { media = chromeMedia(paused: false) }
                    case "next", "previous":
                        media = chromeMedia(video: "lmnopqrstuv", item: "00000000-0000-4000-8000-000000000003", generation: 2)
                        windows[0].tabs[0].url = chromeNextURL
                    case "seekForward30", "seekBackward30", "seekToPosition":
                        media = chromeMedia(paused: media.paused, duration: media.duration, elapsed: seekTarget)
                    default: XCTFail("Unexpected command")
                    }
                }
                if let commandError { throw NSError(domain: NSOSStatusErrorDomain, code: Int(commandError)) }
            } else if operation == "result" {
                resultPolls += 1
                if resultPolls < 2 { status = "pending" }
                else { media = chromeMedia(paused: false) }
            } else { XCTAssertEqual(operation, "read") }
            var object: [String: Any] = ["schemaVersion": 1, "status": status,
                "snapshot": try JSONSerialization.jsonObject(with: JSONEncoder().encode(
                    operation == "read" ? (mediaByTab[tabID] ?? media) : media))]
            if let seekFrom, let seekTarget { object["seekFrom"] = seekFrom; object["seekTarget"] = seekTarget }
            result = .init(string: String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        } else {
            XCTAssertEqual(event.eventClass, kAECoreSuite)
            XCTAssertEqual(event.eventID, kAEGetData)
            let reference = try XCTUnwrap(event.paramDescriptor(forKeyword: keyDirectObject))
            let property = try XCTUnwrap(reference.forKeyword(AEKeyword(keyAEKeyData))).typeCodeValue
            let container = try XCTUnwrap(reference.forKeyword(AEKeyword(keyAEContainer)))
            let kind = container.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue
            let selector = container.forKeyword(AEKeyword(keyAEKeyData))
            let isAll = container.forKeyword(AEKeyword(keyAEKeyForm))?.enumCodeValue == OSType(formAbsolutePosition)
            onProperty?(property)
            if property == 0x49442020, kind == 0x6377696E, isAll { result = Self.list(windows.map(\.id)) }
            else if property == 0x6D6F6465 {
                result = .init(string: try XCTUnwrap(windows.first { $0.id == selector?.stringValue }).mode)
            } else {
                XCTAssertEqual(kind, 0x43725462)
                let windowID = container.forKeyword(AEKeyword(keyAEContainer))?
                    .forKeyword(AEKeyword(keyAEKeyData))?.stringValue
                let window = try XCTUnwrap(windows.first { $0.id == windowID })
                if property == 0x49442020, isAll { result = Self.list(window.tabs.map(\.id)) }
                else if property == 0x55524C20, isAll { result = Self.list(window.tabs.map(\.url)) }
                else if property == 0x55524C20 {
                    urlReads += 1
                    onURLRead?(urlReads)
                    result = .init(string: try XCTUnwrap(windows.first { $0.id == windowID }?.tabs
                        .first { $0.id == selector?.stringValue }).url)
                } else { XCTFail("Unexpected property"); result = .null() }
            }
        }
        return answer(result)
    }

    private func answer(_ result: NSAppleEventDescriptor, error: OSStatus? = nil, message: String? = nil)
        -> NSAppleEventDescriptor {
        let reply = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEAnswer, targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        reply.setParam(result, forKeyword: keyDirectObject)
        if let error { reply.setParam(.init(int32: error), forKeyword: keyErrorNumber) }
        if let message { reply.setParam(.init(string: message), forKeyword: keyErrorString) }
        return reply
    }

    private static func list(_ strings: [String]) -> NSAppleEventDescriptor {
        let result = NSAppleEventDescriptor.list()
        for (index, string) in strings.enumerated() { result.insert(.init(string: string), at: index + 1) }
        return result
    }
}

final class MacChromeNowPlayingRuntimeTests: XCTestCase {
    func testHandoffDescriptorRequiresNativeContinuityAndFreshPlayingSeekableSource() async throws {
        let continuity = UUID().uuidString.lowercased()
        for media in [chromeMedia(), chromeMedia(paused: true, continuity: continuity),
                      chromeMedia(canSeek: false, continuity: continuity),
                      chromeMedia(duration: nil, continuity: continuity)] {
            let backend = ChromeTestBackend(); backend.snapshots = [chromePlayer(media: media)]
            let value = try await snapshot(makeRuntime(backend))
            XCTAssertNil(value.handoffSource)
        }
        let backend = ChromeTestBackend(); backend.snapshots = [chromePlayer(media: chromeMedia(continuity: continuity))]
        let runtime = makeRuntime(backend), value = try await snapshot(runtime)
        let source = try XCTUnwrap(value.handoffSource)
        XCTAssertEqual(source.videoID, "abcdefghijk")
        XCTAssertEqual(source.positionSeconds, 15)
        XCTAssertTrue(source.isFreshForOffer(now: 10.5))
        XCTAssertFalse(source.isFreshForOffer(now: 12))
        XCTAssertFalse(source.isFreshForOffer(now: 9))
        // A backend without the specialized native operation must not substitute plain Pause.
        let result = await withCheckedContinuation { continuation in
            runtime.sendHandoffPause(source: source, phonePositionSeconds: 15,
                snapshot: value, isAuthorized: { true }) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(result, .unsupported)
        XCTAssertTrue(backend.commands.isEmpty)
    }

    func testHandoffCrossesControllerCompositeNativeBackendOnceWithPauseReadback() async throws {
        let client = ChromeTestClient(); client.media = chromeMedia(continuity: UUID().uuidString.lowercased())
        let commandRequest = ChromeTestBox<[String: Any]?>(nil)
        client.onCommandRequest = { commandRequest.set($0) }
        let browser = MacChromeNowPlayingRuntime(backend: makeBackend(client), now: { 10 })
        let composite = MacSupportedNowPlayingRuntime(browser: browser, music: ChromeRecoveryAbsentMusic())
        let controller = MacSystemNowPlayingController(runtime: composite,
            now: { Date(timeIntervalSince1970: 1000) }, stateDiagnostics: { _ in }, uptime: { 10 })
        let published = expectation(description: "exact native source published")
        let state = ChromeTestBox<WebRTCRemoteMediaStateUpdate?>(nil)
        controller.start { update in
            if update.item?.playbackState == .playing, state.get() == nil { state.set(update); published.fulfill() }
        }
        defer { controller.stop() }
        await fulfillment(of: [published], timeout: 3)
        let item = try XCTUnwrap(state.get()?.item)
        let preparedValue = await controller.prepareHandoff(contextID: item.contextID, isAuthorized: { true })
        let prepared = try XCTUnwrap(preparedValue)
        XCTAssertEqual(prepared.videoID, "abcdefghijk")
        let foreign = MacSystemNowPlayingController(runtime: composite, uptime: { 10 })
        let foreignResult = await foreign.performHandoffPause(prepared, phonePositionSeconds: 15)
        XCTAssertEqual(foreignResult, .staleContext)
        let result = await controller.performHandoffPause(prepared, phonePositionSeconds: 15)
        XCTAssertEqual(result, .applied)
        XCTAssertTrue(client.media.paused)
        let duplicate = await controller.performHandoffPause(prepared, phonePositionSeconds: 15)
        XCTAssertEqual(duplicate, .staleContext)
        XCTAssertEqual(client.commandDispatches, 1)
        let request = try XCTUnwrap(commandRequest.get())
        let condition = try XCTUnwrap(request["handoff"] as? [String: Any])
        XCTAssertEqual(request["command"] as? String, "pause")
        XCTAssertEqual(condition["phonePositionSeconds"] as? Double, 15)
        XCTAssertEqual(condition["videoID"] as? String, "abcdefghijk")
        XCTAssertFalse(client.permissionRequests.contains(true))
    }

    func testNativeHandoffDescriptorIsOneUseEvenBeforeNextPublication() async throws {
        let client = ChromeTestClient(), original = chromeMedia(continuity: UUID().uuidString.lowercased())
        client.media = original
        let runtime = MacChromeNowPlayingRuntime(backend: makeBackend(client), now: { 10 })
        let value = try await snapshot(runtime), source = try XCTUnwrap(value.handoffSource)
        func pause() async -> WebRTCRemoteMediaCommandResult {
            await withCheckedContinuation { continuation in
                runtime.sendHandoffPause(source: source, phonePositionSeconds: 15,
                    snapshot: value, isAuthorized: { true }) { continuation.resume(returning: $0) }
            }
        }
        let first = await pause()
        XCTAssertEqual(first, .applied)
        // Even a provider returning exactly the old fields cannot revive consumed host authority.
        client.media = original
        let second = await pause()
        XCTAssertEqual(second, .staleContext)
        XCTAssertEqual(client.commandDispatches, 1)
        XCTAssertFalse(source.isFreshForOffer(now: 10))
    }

    func testHandoffControllerRevocationAndTimeoutRetireDelayedNativeWork() async throws {
        for boundary in ["invalidate", "stop", "external", "commit", "timeout"] {
            let client = ChromeTestClient(); client.media = chromeMedia(continuity: UUID().uuidString.lowercased())
            let browser = MacChromeNowPlayingRuntime(backend: makeBackend(client), now: { 10 })
            let admitted = expectation(description: boundary + " admitted")
            let completed = expectation(description: boundary + " native completion")
            let runtime = ChromeHeldHandoffRuntime(inner: browser,
                admitted: { admitted.fulfill() }, completed: { completed.fulfill() })
            let controller = MacSystemNowPlayingController(runtime: runtime,
                operationTimeout: boundary == "timeout" ? 0.05 : 2,
                stateDiagnostics: { _ in }, uptime: { 10 })
            let published = expectation(description: boundary + " published")
            let item = ChromeTestBox<WebRTCRemoteMediaItem?>(nil)
            controller.start { update in
                if let value = update.item, item.get() == nil { item.set(value); published.fulfill() }
            }
            defer { controller.stop(); browser.stop() }
            await fulfillment(of: [published], timeout: 3)
            let authorization = WebRTCControlAuthorization()
            let commitAuthorization = WebRTCControlAuthorization()
            let preparedValue = await controller.prepareHandoff(contextID: try XCTUnwrap(item.get()).contextID,
                isAuthorized: { authorization.isValid })
            let prepared = try XCTUnwrap(preparedValue)
            let task = Task { await controller.performHandoffPause(prepared, phonePositionSeconds: 15,
                executionIsAuthorized: { commitAuthorization.isValid }) }
            await fulfillment(of: [admitted], timeout: 3)
            switch boundary {
            case "invalidate": controller.invalidateCommands()
            case "stop": controller.stop()
            case "external": authorization.revoke()
            case "commit": commitAuthorization.revoke()
            default:
                let result = await task.value
                XCTAssertEqual(result, .failed)
            }
            runtime.release()
            await fulfillment(of: [completed], timeout: 3)
            let result = await task.value
            XCTAssertEqual(result, boundary == "timeout" ? .failed : .staleContext)
            XCTAssertEqual(client.commandDispatches, 0, boundary)
        }
    }

    func testHandoffCannotCrossRuntimeOwnerAndRevokedOrExpiredQueuedWork() async throws {
        for boundary in ["foreign", "stop", "revoke", "expiry"] {
            let client = ChromeTestClient(); client.media = chromeMedia(continuity: UUID().uuidString.lowercased())
            let clock = ChromeTestBox(10.0), queue = DispatchQueue(label: "handoff-native-queue")
            let runtime = MacChromeNowPlayingRuntime(backend: makeBackend(client, now: { clock.get() }),
                queue: queue, now: { clock.get() })
            let value = try await snapshot(runtime), source = try XCTUnwrap(value.handoffSource)
            let authority = WebRTCControlAuthorization()
            let target = boundary == "foreign" ? MacChromeNowPlayingRuntime(backend: makeBackend(client), now: { 10 }) : runtime
            queue.suspend()
            let done = expectation(description: "old handoff rejected")
            target.sendHandoffPause(source: source, phonePositionSeconds: 15,
                snapshot: value, isAuthorized: { authority.isValid }) {
                    XCTAssertEqual($0, .staleContext, boundary); done.fulfill()
                }
            if boundary == "stop" { runtime.stop() }
            if boundary == "revoke" { authority.revoke() }
            if boundary == "expiry" { clock.set(41) }
            queue.resume()
            await fulfillment(of: [done], timeout: 3)
            XCTAssertEqual(client.commandDispatches, 0, boundary)
        }
    }

    func testHandoffBackendRejectsChangedTimelineOrFarAwayPhoneBeforeCommand() throws {
        let continuity = UUID().uuidString.lowercased()
        for changed in [chromeMedia(continuity: UUID().uuidString.lowercased()),
                        chromeMedia(elapsed: 80, continuity: continuity),
                        chromeMedia(duration: 200, continuity: continuity),
                        chromeMedia(paused: true, continuity: continuity)] {
            let client = ChromeTestClient(); client.media = chromeMedia(continuity: continuity)
            let backend = makeBackend(client), source = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
            let condition = try XCTUnwrap(MacChromeHandoffPauseCondition(source: source, phonePositionSeconds: 15))
            client.media = changed
            let result = try backend.sendHandoffPause(expected: source, condition: condition,
                deadline: 11, isAuthorized: { true })
            XCTAssertNotEqual(result, .applied); XCTAssertEqual(client.commandDispatches, 0)
        }
        let client = ChromeTestClient(); client.media = chromeMedia(continuity: continuity)
        let backend = makeBackend(client), source = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        let condition = try XCTUnwrap(MacChromeHandoffPauseCondition(source: source, phonePositionSeconds: 80))
        XCTAssertEqual(try backend.sendHandoffPause(expected: source, condition: condition,
            deadline: 11, isAuthorized: { true }), .staleContext)
        XCTAssertEqual(client.commandDispatches, 0)
    }

    func testHandoffRequiresNativePauseAndPositionReadbackNotOnlyOKEnvelope() throws {
        for mode in ["ignored", "position"] {
            let client = ChromeTestClient(); client.media = chromeMedia(continuity: UUID().uuidString.lowercased())
            let backend = makeBackend(client), source = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
            let condition = try XCTUnwrap(MacChromeHandoffPauseCondition(source: source, phonePositionSeconds: 15))
            if mode == "ignored" { client.ignoreCommands = true }
            else { client.commandReply = ("ok", chromeMedia(paused: true, elapsed: 80)) }
            XCTAssertEqual(try backend.sendHandoffPause(expected: source, condition: condition,
                deadline: 11, isAuthorized: { true }), .failed)
            XCTAssertEqual(client.commandDispatches, 1)
        }
    }

    func testThirtyNineYouTubeCandidatesDiscoverLatePlayingItemWithoutTruncation() throws {
        let client = ChromeTestClient()
        client.windows[0].tabs = (2...40).map { (String($0), chromeURL) }
        client.media = chromeMedia(paused: true)
        client.mediaByTab["40"] = chromeMedia()
        guard case .selected(let selected) = makeBackend(client).readSelection(preferred: nil, deadline: 11.5)
        else { return XCTFail("39-tab discovery failed") }
        XCTAssertEqual(selected.tab.tabID, "40")
        XCTAssertEqual(client.scriptTabIDs, (2...40).map(String.init))
    }

    func testInventoryCapacityAndDuplicateIdentityStillFailBeforePageReads() {
        for duplicate in [false, true] {
            let client = ChromeTestClient()
            client.windows[0].tabs = duplicate ? [("2", chromeURL), ("2", chromeURL)]
                : (2...514).map { (String($0), chromeURL) }
            guard case .incomplete(.invalidData, holding: nil) = makeBackend(client).readSelection(preferred: nil, deadline: 11.5)
            else { return XCTFail("Invalid inventory admitted") }
            XCTAssertTrue(client.scriptTabIDs.isEmpty)
        }
    }

    func testUnrelatedTimeoutDoesNotHideLaterFreshPlayingItemButIsNotNoMedia() {
        let client = ChromeTestClient()
        client.windows[0].tabs.append(("3", chromeURL))
        client.errorByTab["2"] = OSStatus(errAETimeout)
        let backend = makeBackend(client)
        guard case .selected(let selected) = backend.readSelection(preferred: nil, deadline: 11.5)
        else { return XCTFail("Healthy successor starved") }
        XCTAssertEqual(selected.tab.tabID, "3")
        client.media = chromeMedia(paused: true)
        guard case .incomplete(.timedOut, holding: nil) = backend.readSelection(preferred: nil, deadline: 11.5)
        else { return XCTFail("Unknown tab was treated as paused/noMedia") }
    }

    func testSelectedUnknownBlocksPromotionAndFreshRecoveryRotatesAuthority() async throws {
        let client = ChromeTestClient()
        client.windows[0].tabs.append(("3", chromeURL))
        let backend = makeBackend(client)
        let runtime = MacChromeNowPlayingRuntime(backend: backend, now: { 10 })
        let old = try await snapshot(runtime)
        for failure in [OSStatus(errAETimeout), OSStatus(-1700)] {
            client.errorByTab["2"] = failure
            client.scriptTabIDs = []
            guard case .retry = await fetch(runtime) else { return XCTFail("Unknown owner promoted another tab") }
            XCTAssertEqual(client.scriptTabIDs, ["2"])
            await assertSend(runtime, command: 1, snapshot: old, equals: .staleContext)
        }
        client.errorByTab = [:]
        let fresh = try await snapshot(runtime)
        XCTAssertFalse(old.client === fresh.client)
        await assertSend(runtime, command: 1, snapshot: fresh, equals: .applied)
    }

    func testRoundRobinProgressUsesStableIdentityAcrossInventoryChurn() {
        let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
        client.windows[0].tabs = [("2", chromeURL), ("3", chromeURL), ("4", chromeURL), ("5", chromeURL)]
        client.errorByTab = ["2": OSStatus(errAETimeout), "3": OSStatus(errAETimeout), "4": OSStatus(errAETimeout)]
        client.onReadTab = { _ in clock.update { $0 += 0.35 } }
        let backend = makeBackend(client, now: { clock.get() })
        guard case .incomplete = backend.readSelection(preferred: nil, deadline: 11.5)
        else { return XCTFail("Unfinished slice published authority") }
        XCTAssertEqual(client.scriptTabIDs, ["2", "3"])
        client.windows[0].tabs = [("6", chromeURL), ("3", chromeURL), ("5", chromeURL), ("4", chromeURL)]
        client.scriptTabIDs = []
        guard case .selected(let selected) = backend.readSelection(preferred: nil, deadline: clock.get() + 1.5)
        else { return XCTFail("Cursor lost stable successor") }
        XCTAssertEqual(selected.tab.tabID, "5")
        XCTAssertEqual(client.scriptTabIDs, ["3", "5"])
    }

    func testHealthyTabAtSliceBoundaryGetsFullBudgetOnNextPass() {
        let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
        client.windows[0].tabs = [("2", chromeURL), ("3", chromeURL), ("4", chromeURL)]
        client.noMediaTabs = ["2", "3"]
        client.onReadTab = { tab in clock.update { $0 += tab == "4" ? 0.1 : 0.35 } }
        let backend = makeBackend(client, now: { clock.get() })
        guard case .incomplete = backend.readSelection(preferred: nil, deadline: 11.5)
        else { return XCTFail("A slice-expired read published authority") }
        XCTAssertEqual(client.scriptTabIDs, ["2", "3", "4"])
        client.scriptTabIDs = []
        guard case .selected(let selected) = backend.readSelection(preferred: nil, deadline: clock.get() + 1.5)
        else { return XCTFail("Healthy tab starved at slice boundary") }
        XCTAssertEqual(selected.tab.tabID, "4")
        XCTAssertEqual(client.scriptTabIDs, ["4"])
    }

    func testFullSliceFirstCandidateTimeoutWithOverheadCannotPinDiscovery() {
        let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
        client.windows[0].tabs = [("2", chromeURL), ("3", chromeURL)]
        client.errorByTab = ["2": OSStatus(errAETimeout)]
        client.onReadTab = { tab in clock.update { $0 += tab == "2" ? 0.41 : 0.1 } }
        guard case .selected(let selected) = makeBackend(client, now: { clock.get() })
            .readSelection(preferred: nil, deadline: 11.5)
        else { return XCTFail("First candidate timeout pinned discovery") }
        XCTAssertEqual(selected.tab.tabID, "3")
        XCTAssertEqual(client.scriptTabIDs, ["2", "3"])
    }

    func testFreshPlayingOwnerSkipsUnrelatedRendererAndPausedOwnerStaysControllable() throws {
        let client = ChromeTestClient()
        client.windows[0].tabs.append(("3", chromeURL)); client.errorByTab["3"] = OSStatus(errAETimeout)
        let backend = makeBackend(client), expected = chromePlayer()
        guard case .selected = backend.readSelection(preferred: expected, deadline: 11.5)
        else { return XCTFail("Selected playing owner disappeared") }
        XCTAssertEqual(client.scriptTabIDs, ["2"])
        client.media = chromeMedia(paused: true); client.scriptTabIDs = []
        guard case .selected(let paused) = backend.readSelection(preferred: expected, deadline: 11.5)
        else { return XCTFail("Fresh paused owner disappeared during incomplete search") }
        XCTAssertTrue(paused.media.paused)
        client.scriptTabIDs = []
        XCTAssertEqual(try backend.send(.play, expected: paused, deadline: 11.5, isAuthorized: { true }), .applied)
        XCTAssertTrue(client.scriptTabIDs.allSatisfy { $0 == "2" })
        XCTAssertEqual(client.commandDispatches, 1)
    }

    func testFreshPausedOwnerPublishesBeforeUnrelatedInventoryExhaustsDeadline() {
        let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
        let expected = chromePlayer()
        client.media = chromeMedia(paused: true)
        for index in 2...5 {
            client.windows.append(.init(id: String(index), tabs: [(String(index + 10), chromeURL)]))
            client.errorByTab[String(index + 10)] = OSStatus(errAETimeout)
        }
        let exactObservation = ChromeTestBox<TimeInterval?>(nil)
        client.onReadTab = { tab in
            XCTAssertEqual(tab, expected.tab.tabID, "Unrelated discovery must not precede the exact selected read")
            clock.update { $0 += 0.1 }
            exactObservation.set(clock.get())
        }
        let censusStarted = ChromeTestBox(false)
        client.onProperty = { property in
            if property == 0x49442020 { censusStarted.set(true) }
            if censusStarted.get() { clock.update { $0 += 0.1 } }
        }
        let deadline = 11.5
        let result = makeBackend(client, now: { clock.get() })
            .readSelection(preferred: expected, deadline: deadline)

        XCTAssertEqual(exactObservation.get(), 10.1, "The exact player was freshly observed before census work")
        XCTAssertEqual(client.scriptTabIDs, [expected.tab.tabID])
        XCTAssertEqual(client.commandDispatches, 0, "An external pause observation must not mutate a player")
        let observed: MacChromePlayerSnapshot?
        switch result {
        case .selected(let value): observed = value
        case .incomplete(_, let holding): observed = holding
        case .noPlayer: observed = nil
        }
        XCTAssertEqual(observed?.tab, expected.tab)
        XCTAssertEqual(observed?.media.identity, expected.media.identity)
        XCTAssertEqual(observed?.media.paused, true, "A fresh paused observation, not the old playing hint, reached the backend")
        XCTAssertEqual(observed?.receivedAtUptime, 10.1)
        guard case .selected(let paused) = result else {
            return XCTFail("Fresh exact paused owner was withheld by unrelated inventory: \(result)")
        }
        XCTAssertTrue(paused.hasSameItem(as: expected))
        XCTAssertTrue(paused.media.paused)
        XCTAssertEqual(paused.media.enabledCommands, [0, 4, 5, 6, 7, MacChromeCommand.seekToPosition.rawValue])
        XCTAssertEqual(paused.receivedAtUptime, 10.1)
        XCTAssertLessThan(clock.get(), deadline, "Publication must precede the caller deadline, not revive a late snapshot")
    }

    func testFreshPlayingOwnerDoesNotSpendItsDeadlineOnUnrelatedInventory() {
        let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
        client.windows.append(.init(id: "4", tabs: [("5", chromeURL)]))
        client.errorByTab["5"] = OSStatus(errAETimeout)
        client.onReadTab = { _ in clock.update { $0 += 0.1 } }
        client.onProperty = { property in
            XCTAssertNotEqual(property, 0x49442020, "A freshly playing owner must bypass the global census")
        }
        guard case .selected(let selected) = makeBackend(client, now: { clock.get() })
            .readSelection(preferred: chromePlayer(), deadline: 11.5) else {
            return XCTFail("Fresh selected playing owner became unavailable")
        }
        XCTAssertTrue(selected.hasSameItem(as: chromePlayer()))
        XCTAssertFalse(selected.media.paused)
        XCTAssertEqual(client.scriptTabIDs, ["2"])
        XCTAssertEqual(client.commandDispatches, 0)
        XCTAssertLessThan(clock.get(), 11.5)
    }

    func testPausedOwnerDeadlineRecoveryCannotBypassPermissionOrReplacementOwner() {
        for permissionDenied in [true, false] {
            let client = ChromeTestClient()
            client.media = chromeMedia(paused: true)
            if permissionDenied {
                client.permissionStatus = -1743
            } else {
                client.onReadTab = { _ in
                    client.owner = .init(processID: 43, launchDate: chromeOwner.launchDate)
                }
            }
            let result = makeBackend(client).readSelection(preferred: chromePlayer(), deadline: 11.5)
            guard case .incomplete(let failure, _) = result else {
                return XCTFail("Uncertain selected owner became publication authority: \(result)")
            }
            XCTAssertEqual(failure, permissionDenied ? .permissionDenied : .staleItem)
            XCTAssertEqual(client.scriptTabIDs, permissionDenied ? [] : ["2"])
            XCTAssertEqual(client.commandDispatches, 0)
            XCTAssertTrue(client.permissionRequests.allSatisfy { !$0 })
        }
    }

    func testSelectedReadTimeoutOrStalenessCannotBorrowPausedHintOrBootstrapSibling() {
        for failure in [OSStatus(errAETimeout), OSStatus(-1728)] {
            let client = ChromeTestClient()
            client.media = chromeMedia(paused: true)
            client.windows[0].tabs.append(("3", chromeURL))
            client.mediaByTab["3"] = chromeMedia()
            client.errorByTab["2"] = failure
            let result = makeBackend(client).readSelection(preferred: chromePlayer(), deadline: 11.5)
            guard case .incomplete(let error, let holding) = result else {
                return XCTFail("Unknown selected item became publication authority: \(result)")
            }
            XCTAssertEqual(error, failure == OSStatus(errAETimeout) ? .timedOut : .staleItem)
            XCTAssertEqual(holding?.media.paused, false, "Only the old playing hint exists; no paused read succeeded")
            XCTAssertEqual(client.scriptTabIDs, ["2"])
            XCTAssertEqual(client.commandDispatches, 0)
        }
    }

    func testSpeculativeCensusOverrunningAbsoluteDeadlineCannotPublishFreshPausedOwner() {
        let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
        client.media = chromeMedia(paused: true)
        client.onReadTab = { _ in clock.update { $0 += 0.1 } }
        client.onProperty = { property in
            if property == 0x49442020 { clock.set(11.6) }
        }
        let result = makeBackend(client, now: { clock.get() })
            .readSelection(preferred: chromePlayer(), deadline: 11.5)
        guard case .incomplete(.timedOut, let holding) = result else {
            return XCTFail("An expired paused observation became publication authority: \(result)")
        }
        XCTAssertEqual(holding?.media.paused, true)
        XCTAssertEqual(client.scriptTabIDs, ["2"])
        XCTAssertEqual(client.commandDispatches, 0)
    }

    func testSpeculativeCensusTimeoutRechecksPermissionBeforePublishingPausedOwner() {
        let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
        client.media = chromeMedia(paused: true)
        for index in 2...5 {
            client.windows.append(.init(id: String(index), tabs: [(String(index + 10), chromeURL)]))
        }
        client.onReadTab = { _ in clock.update { $0 += 0.1 } }
        let censusStarted = ChromeTestBox(false)
        client.onProperty = { property in
            if property == 0x49442020 {
                censusStarted.set(true)
                client.permissionStatus = -1743
            }
            if censusStarted.get() { clock.update { $0 += 0.1 } }
        }
        let result = makeBackend(client, now: { clock.get() })
            .readSelection(preferred: chromePlayer(), deadline: 11.5)
        guard case .incomplete(.permissionDenied, let holding) = result else {
            return XCTFail("Revoked permission survived the speculative timeout: \(result)")
        }
        XCTAssertEqual(holding?.media.paused, true)
        XCTAssertEqual(client.scriptTabIDs, ["2"])
        XCTAssertEqual(client.commandDispatches, 0)
        XCTAssertTrue(client.permissionRequests.allSatisfy { !$0 })
    }

    func testSpeculativeCensusOwnerReplacementCannotPublishFreshPausedOwner() {
        let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
        client.media = chromeMedia(paused: true)
        client.onReadTab = { _ in clock.update { $0 += 0.1 } }
        client.onProperty = { property in
            if property == 0x49442020 {
                clock.set(11.2)
                client.owner = .init(processID: 43, launchDate: chromeOwner.launchDate)
            }
        }
        let result = makeBackend(client, now: { clock.get() })
            .readSelection(preferred: chromePlayer(), deadline: 11.5)
        guard case .incomplete(.staleItem, let holding) = result else {
            return XCTFail("Replacement Chrome owner survived speculative census expiry: \(result)")
        }
        XCTAssertEqual(holding?.media.paused, true)
        XCTAssertEqual(holding?.receivedAtUptime, 10.1)
        XCTAssertEqual(client.scriptTabIDs, ["2"])
        XCTAssertEqual(client.commandDispatches, 0)
    }

    func testTimelyCensusCanPromoteSuccessorAndFinalResumedOwnerStillWins() {
        for resumesDuringDiscovery in [false, true] {
            let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
            client.windows[0].tabs.append(("3", chromeURL))
            client.mediaByTab["2"] = chromeMedia(paused: true)
            client.mediaByTab["3"] = chromeMedia()
            let censusStarted = ChromeTestBox(false), remainingCensusProperties = ChromeTestBox(4)
            client.onProperty = { property in
                if property == 0x49442020 { censusStarted.set(true) }
                if censusStarted.get(), remainingCensusProperties.get() > 0 {
                    clock.update { $0 += 0.2 }
                    remainingCensusProperties.update { $0 -= 1 }
                }
            }
            client.onReadTab = { tab in
                clock.update { $0 += 0.1 }
                if tab == "3", resumesDuringDiscovery { client.mediaByTab["2"] = chromeMedia() }
            }
            let result = makeBackend(client, now: { clock.get() })
                .readSelection(preferred: chromePlayer(), deadline: 11.5)
            guard case .selected(let selected) = result else {
                return XCTFail("Timely successor discovery was starved by the census: \(result)")
            }
            XCTAssertEqual(selected.tab.tabID, resumesDuringDiscovery ? "2" : "3")
            XCTAssertFalse(selected.media.paused)
            XCTAssertEqual(client.scriptTabIDs, ["2", "3", "2"], "Handoff requires the final exact selected-owner read")
            XCTAssertEqual(client.commandDispatches, 0)
            XCTAssertLessThan(clock.get(), 11.5)
        }
    }

    func testUnrelatedCandidatePermissionFailureDoesNotFallBackToFreshPausedOwner() {
        let client = ChromeTestClient()
        client.media = chromeMedia(paused: true)
        client.windows[0].tabs.append(("3", chromeURL))
        client.errorByTab["3"] = -1743
        let result = makeBackend(client).readSelection(preferred: chromePlayer(), deadline: 11.5)
        guard case .incomplete(.permissionDenied, let holding) = result else {
            return XCTFail("An unrelated permission failure was treated as harmless timeout: \(result)")
        }
        XCTAssertEqual(holding?.media.paused, true)
        XCTAssertEqual(client.scriptTabIDs, ["2", "3"])
        XCTAssertEqual(client.commandDispatches, 0)
    }

    func testExternalPausedOwnerCrossesActualAppleEventsCompositeAndControllerWithoutCommand() async throws {
        let client = ChromeTestClient(), clock = ChromeTestBox(10.0)
        for index in 2...5 {
            client.windows.append(.init(id: String(index), tabs: [(String(index + 10), chromeURL)]))
            client.errorByTab[String(index + 10)] = OSStatus(errAETimeout)
        }
        client.onReadTab = { _ in clock.update { $0 += 0.1 } }
        let expensiveCensus = ChromeTestBox(false), censusStarted = ChromeTestBox(false)
        client.onProperty = { property in
            guard expensiveCensus.get() else { return }
            if property == 0x49442020 { censusStarted.set(true) }
            if censusStarted.get() { clock.update { $0 += 0.1 } }
        }
        let backend = makeBackend(client, now: { clock.get() })
        let chrome = MacChromeNowPlayingRuntime(backend: backend, now: { clock.get() })
        let composite = MacSupportedNowPlayingRuntime(browser: chrome, music: ChromeRecoveryAbsentMusic())
        let controller = MacSystemNowPlayingController(runtime: composite, operationTimeout: 20,
            now: { Date(timeIntervalSince1970: 1000) })
        defer { controller.stop() }
        let updates = ChromeTestBox<[WebRTCRemoteMediaStateUpdate]>([])
        let playing = expectation(description: "actual Chrome selected playing item")
        let paused = expectation(description: "external pause publishes without a viewer command")
        controller.start { update in
            updates.update { $0.append(update) }
            switch update.revision {
            case 1: playing.fulfill()
            case 2: paused.fulfill()
            default: XCTFail("Unexpected additional controller publication")
            }
        }
        await fulfillment(of: [playing], timeout: 20)
        let initial = try XCTUnwrap(updates.get().last?.item)
        XCTAssertEqual(initial.playbackState, .playing)
        client.media = chromeMedia(paused: true)
        expensiveCensus.set(true)
        controller.refresh()
        await fulfillment(of: [paused], timeout: 20)
        let values = updates.get()
        XCTAssertEqual(values.map(\.revision), [1, 2])
        let observed = try XCTUnwrap(values.last?.item)
        XCTAssertEqual(observed.contextID, initial.contextID)
        XCTAssertEqual(observed.title, initial.title)
        XCTAssertEqual(observed.playbackState, .paused)
        XCTAssertEqual(observed.playbackRate, 0)
        XCTAssertTrue(observed.capabilities.canPlay)
        XCTAssertFalse(observed.capabilities.canPause)
        XCTAssertEqual(client.scriptTabIDs, ["2", "2"])
        XCTAssertEqual(client.commandDispatches, 0)
    }

    func testPausedOwnerResumedDuringDiscoveryWinsFinalPromotionFence() {
        let client = ChromeTestClient()
        client.windows[0].tabs.append(("3", chromeURL))
        client.mediaByTab["2"] = chromeMedia(paused: true)
        client.onReadTab = { tab in if tab == "3" { client.mediaByTab["2"] = chromeMedia() } }
        guard case .selected(let selected) = makeBackend(client).readSelection(preferred: chromePlayer(), deadline: 11.5)
        else { return XCTFail("Selection unavailable") }
        XCTAssertEqual(selected.tab.tabID, "2")
        XCTAssertFalse(selected.media.paused)
        XCTAssertEqual(client.scriptTabIDs, ["2", "3", "2"])
    }

    func testPausedOwnerBecomingUnknownDuringPromotionDoesNotHandOff() {
        let client = ChromeTestClient()
        client.windows[0].tabs.append(("3", chromeURL))
        client.mediaByTab["2"] = chromeMedia(paused: true)
        client.onReadTab = { tab in if tab == "3" { client.errorByTab["2"] = OSStatus(errAETimeout) } }
        guard case .incomplete(.timedOut, holding: let held) = makeBackend(client).readSelection(preferred: chromePlayer(), deadline: 11.5)
        else { return XCTFail("Unknown paused owner handed off") }
        XCTAssertEqual(held?.tab.tabID, "2")
    }

    func testCommandUncertaintyRevokesAbsoluteCommandTokenUntilFreshRead() async throws {
        for command in [0, 1] {
            let backend = ChromeTestBackend()
            backend.snapshots = [chromePlayer(media: chromeMedia(paused: command == 0))]
            let runtime = makeRuntime(backend), old = try await snapshot(runtime)
            backend.commandError = .timedOut
            await assertSend(runtime, command: command, snapshot: old, equals: .failed)
            await assertSend(runtime, command: command, snapshot: old, equals: .staleContext)
            backend.commandError = nil
            let fresh = try await snapshot(runtime)
            XCTAssertFalse(fresh.client === old.client)
            await assertSend(runtime, command: command, snapshot: fresh, equals: .applied)
            XCTAssertEqual(backend.commands.count, 2)
        }
    }

    func testLateConfirmedAbsenceOrReplacementCannotRestorePreviousOwnership() async throws {
        for replacement in [false, true] {
            let backend = ChromeTestBackend(), clock = ChromeTestBox(10.0)
            let runtime = MacChromeNowPlayingRuntime(backend: backend, now: { clock.get() })
            let old = try await snapshot(runtime)
            backend.snapshots = replacement ? [chromePlayer(media: chromeMedia(item: UUID().uuidString))] : []
            backend.onRead = { clock.update { $0 += 2 } }
            guard case .retry = await fetch(runtime) else { return XCTFail("Late result published authority") }
            backend.onRead = nil
            backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), chromePlayer(tab: "3", media: chromeMedia(paused: true))]
            guard case .retry = await fetch(runtime) else { return XCTFail("Old ownership resurrected after retirement") }
            await assertSend(runtime, command: 1, snapshot: old, equals: .staleContext)
        }
    }

    func testCommandConfirmedRetirementClearsOwnershipBeforeOldItemReturns() async throws {
        let backend = ChromeTestBackend(), runtime = makeRuntime(backend)
        let old = try await snapshot(runtime)
        backend.commandError = .retiredItem
        await assertSend(runtime, command: 1, snapshot: old, equals: .staleContext)
        backend.commandError = nil
        backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), chromePlayer(tab: "3", media: chromeMedia(paused: true))]
        guard case .retry = await fetch(runtime) else { return XCTFail("Command-proven retired owner returned") }
    }

    func testFinalCommandFenceSeparatesProvenReplacementFromUnknownState() throws {
        for status in ["staleContext", "noMedia"] {
            let client = ChromeTestClient(), backend = makeBackend(client)
            client.commandReply = (status, status == "noMedia" ? nil : chromeMedia(item: UUID().uuidString))
            XCTAssertThrowsError(try backend.send(.pause, expected: chromePlayer(), deadline: 11.5, isAuthorized: { true })) {
                XCTAssertEqual($0 as? MacChromeBackendError, .retiredItem)
            }
        }
        for snapshot in [nil, chromeMedia()] as [MacChromeScriptSnapshot?] {
            let client = ChromeTestClient(), backend = makeBackend(client)
            client.commandReply = ("staleContext", snapshot)
            XCTAssertEqual(try backend.send(.pause, expected: chromePlayer(), deadline: 11.5, isAuthorized: { true }), .staleContext)
        }
    }

    func testArtworkUsesValidatedVideoIDWithoutChangingItemIdentity() throws {
        let original = try XCTUnwrap(MacChromeNowPlayingRuntime.metadata(chromePlayer()))
        XCTAssertEqual(original.artwork, WebRTCRemoteMediaArtworkReference(videoID: "abcdefghijk"))
        let newArtwork = try XCTUnwrap(MacChromeNowPlayingRuntime.metadata(
            chromePlayer(media: chromeMedia(video: "lmnopqrstuv"))))
        XCTAssertEqual(newArtwork.artwork?.videoID, "lmnopqrstuv")
        XCTAssertEqual(original.identityComponent, newArtwork.identityComponent)
        XCTAssertNotEqual(original, newArtwork)
        for id in ["", "abcdefghij", "abcdefghij/", "abcdefghij?", "abcdefghié"] {
            XCTAssertNil(MacChromeNowPlayingRuntime.metadata(chromePlayer(media: chromeMedia(video: id))))
        }
        XCTAssertNil(MacChromeNowPlayingRuntime.metadata(chromePlayer(media: chromeMedia(document: "bad-document"))))
        XCTAssertNil(MacChromeNowPlayingRuntime.metadata(chromePlayer(media: chromeMedia(item: "bad-item"))))
        XCTAssertNil(MacChromeNowPlayingRuntime.metadata(chromePlayer(media: chromeMedia(generation: 0))))
        XCTAssertNil(MacChromeNowPlayingRuntime.metadata(chromePlayer(
            owner: .init(processID: 0, launchDate: chromeOwner.launchDate))))
    }

    func testArtworkFollowsSourceReplacementAndNeverRestoresRetiredItem() async throws {
        let backend = ChromeTestBackend()
        let runtime = makeRuntime(backend)
        let old = try await snapshot(runtime)
        XCTAssertEqual(old.metadata.artwork?.videoID, "abcdefghijk")
        backend.snapshots = [chromePlayer(media: chromeMedia(video: "lmnopqrstuv",
            item: "00000000-0000-4000-8000-000000000003", generation: 2))]
        let successor = try await snapshot(runtime)
        XCTAssertEqual(successor.metadata.artwork?.videoID, "lmnopqrstuv")
        XCTAssertNotEqual(old.identityKey, successor.identityKey)
        await assertSend(runtime, command: 1, snapshot: old, equals: .staleContext)
        XCTAssertTrue(backend.commands.isEmpty)
        runtime.stop()
    }

    func testNoRunningChromeSendsNothingAndCannotRequestLaunchOrPermission() throws {
        let client = ChromeTestClient(); client.owner = nil
        let backend = makeBackend(client)
        XCTAssertTrue(try backend.readSnapshots(deadline: 11).isEmpty)
        XCTAssertThrowsError(try backend.requestAutomationPermission())
        XCTAssertTrue(client.options.isEmpty)
        XCTAssertTrue(client.permissionRequests.isEmpty)
    }

    func testPublicNativeDescriptorsUseStablePIDIDsNormalWindowsAndNoPromptOptions() throws {
        let client = ChromeTestClient()
        client.windows[0].tabs.append(("3", "https://example.com/private"))
        client.windows.append(.init(id: "4", mode: "incognito", tabs: [("5", chromeURL)]))
        let snapshots = try makeBackend(client).readSnapshots(deadline: 11)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.tab, chromePlayer().tab)
        XCTAssertEqual(snapshots.first?.media.title, "Video")
        XCTAssertEqual(snapshots.first?.media.duration, 120)
        XCTAssertEqual(snapshots.first?.media.elapsedTime, 15)
        XCTAssertEqual(snapshots.first?.media.enabledCommands, [1, 4, 5, 6, 7, MacChromeCommand.seekToPosition.rawValue])
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.permissionRequests, [false])
        XCTAssertTrue(client.targets.allSatisfy { $0 == 42 })
        XCTAssertTrue(client.timeouts.allSatisfy { $0 > 0 && $0 <= 0.35 })
        XCTAssertTrue(client.options.allSatisfy {
            $0.rawValue & UInt(kAENeverInteract | kAEDoNotPromptForUserConsent | kAEDontRecord)
                == UInt(kAENeverInteract | kAEDoNotPromptForUserConsent | kAEDontRecord)
        })
    }

    func testPermissionDeniedNeverPromptsAndExplicitOnboardingIsSeparate() throws {
        let client = ChromeTestClient(); client.permissionStatus = -1744
        let backend = makeBackend(client)
        XCTAssertThrowsError(try backend.readSnapshots(deadline: 11)) {
            XCTAssertEqual($0 as? MacChromeBackendError, .permissionRequired)
        }
        XCTAssertEqual(client.permissionRequests, [false])
        XCTAssertTrue(client.options.isEmpty)
        client.permissionStatus = -1743
        XCTAssertThrowsError(try backend.requestAutomationPermission()) {
            XCTAssertEqual($0 as? MacChromeBackendError, .permissionDenied)
        }
        XCTAssertEqual(client.permissionRequests, [false, true])
    }

    func testJavaScriptPermissionErrorIsContentFreeAndDistinct() throws {
        let client = ChromeTestClient()
        client.scriptError = (-10000, "Executing JavaScript through AppleScript is turned off.")
        XCTAssertThrowsError(try makeBackend(client).readSnapshots(deadline: 11)) {
            XCTAssertEqual($0 as? MacChromeBackendError, .javascriptPermissionRequired)
        }
        XCTAssertEqual(client.permissionRequests, [false])
    }

    func testOnlyOrdinaryExactYouTubeWatchURLsAreEligible() {
        XCTAssertEqual(MacChromeAppleEventsBackend.videoID(from: chromeURL + "&list=abc&index=2"), "abcdefghijk")
        for url in ["http://www.youtube.com/watch?v=abcdefghijk", "https://youtube.com/watch?v=abcdefghijk",
                    "https://www.youtube.com.evil.test/watch?v=abcdefghijk", "https://user@www.youtube.com/watch?v=abcdefghijk",
                    "https://www.youtube.com:443/watch?v=abcdefghijk", chromeURL + "&v=lmnopqrstuv", chromeURL + "#x",
                    "https://www.youtube.com/shorts/abcdefghijk", "chrome://extensions", "javascript:alert(1)"] {
            XCTAssertNil(MacChromeAppleEventsBackend.videoID(from: url), url)
        }
    }

    func testOwnerRestartAndSameURLItemABACannotReuseSnapshot() throws {
        let client = ChromeTestClient(); let backend = makeBackend(client)
        let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        client.owner = .init(processID: 42, launchDate: Date(timeIntervalSince1970: 101))
        XCTAssertThrowsError(try backend.send(.pause, expected: expected, deadline: 11, isAuthorized: { true }))
        client.owner = chromeOwner
        client.media = chromeMedia(item: "00000000-0000-4000-8000-000000000003", generation: 3)
        XCTAssertThrowsError(try backend.send(.pause, expected: expected, deadline: 11, isAuthorized: { true })) {
            XCTAssertEqual($0 as? MacChromeBackendError, .retiredItem)
        }
        XCTAssertEqual(client.commandDispatches, 0)
    }

    func testURLChangeAtReadBoundaryRejectsMixedSnapshotAndOversizedReplyFailsClosed() throws {
        let client = ChromeTestClient()
        client.onURLRead = { count in if count == 2 { client.windows[0].tabs[0].url = chromeNextURL } }
        XCTAssertThrowsError(try makeBackend(client).readSnapshots(deadline: 11))
        client.onURLRead = nil; client.windows[0].tabs[0].url = chromeURL; client.oversizedResult = true
        XCTAssertThrowsError(try makeBackend(client).readSnapshots(deadline: 11)) {
            XCTAssertEqual($0 as? MacChromeBackendError, .invalidData)
        }
    }

    func testFinalNativeAuthorizationGuardPreventsActualPlayerMutation() throws {
        let client = ChromeTestClient(); let backend = makeBackend(client)
        let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        client.urlReads = 0
        let armed = ChromeTestBox(false); let checks = ChromeTestBox(0)
        client.onURLRead = { count in if count == 4 { armed.set(true) } }
        XCTAssertThrowsError(try backend.send(.pause, expected: expected, deadline: 11, isAuthorized: {
            guard armed.get() else { return true }
            let count = checks.get() + 1; checks.set(count)
            return count == 1 // post-URL proof passes; final native dispatch is revoked.
        }))
        XCTAssertTrue(armed.get())
        XCTAssertEqual(client.commandDispatches, 0)
        XCTAssertFalse(client.media.paused)
    }

    func testFinalNativeDeadlineGuardPreventsActualPlayerMutation() throws {
        let client = ChromeTestClient(); let armed = ChromeTestBox(false); let checks = ChromeTestBox(0)
        let backend = makeBackend(client, now: {
            guard armed.get() else { return 10 }
            let count = checks.get() + 1; checks.set(count)
            return count == 1 ? 10 : 20
        })
        let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        client.urlReads = 0
        client.onURLRead = { count in if count == 4 { armed.set(true) } }
        XCTAssertThrowsError(try backend.send(.pause, expected: expected, deadline: 11, isAuthorized: { true }))
        XCTAssertTrue(armed.get())
        XCTAssertEqual(client.commandDispatches, 0)
        XCTAssertFalse(client.media.paused)
    }

    func testCommandExpiryUsesEarlierSnapshotClockAndPlayRequiresAsyncReadback() throws {
        let client = ChromeTestClient(); client.media = chromeMedia(paused: true); client.pendingPlay = true
        let backend = makeBackend(client)
        let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        XCTAssertEqual(try backend.send(.play, expected: expected, deadline: 11, isAuthorized: { true }), .applied)
        XCTAssertEqual(client.commandDispatches, 1)
        XCTAssertEqual(client.resultPolls, 2)
        let request = try XCTUnwrap(client.requests.first { $0["operation"] as? String == "command" })
        XCTAssertEqual(request["expiresAtPageMilliseconds"] as? Double, 51_000)
        XCTAssertEqual(request["expiresAtUnixMilliseconds"] as? Double, 1_001_000)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(request["commandID"] as? String)))
        let expectedObject = try XCTUnwrap(request["expected"] as? [String: Any])
        XCTAssertEqual(expectedObject["itemID"] as? String, expected.media.itemID)
        XCTAssertFalse(client.media.paused)
    }

    func testSuccessfulEnvelopeWithoutActualPauseAndRelativeTransitionIsNotApplied() throws {
        let client = ChromeTestClient(); client.ignoreCommands = true
        let backend = makeBackend(client)
        let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        XCTAssertEqual(try backend.send(.pause, expected: expected, deadline: 11, isAuthorized: { true }), .failed)
        XCTAssertEqual(try backend.send(.next, expected: expected, deadline: 11, isAuthorized: { true }), .failed)
        XCTAssertEqual(client.commandDispatches, 2)
    }

    func testRelativeTimeoutDoesNotResendNativeMutation() throws {
        let client = ChromeTestClient(); let backend = makeBackend(client)
        let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        client.commandError = OSStatus(errAETimeout)
        XCTAssertThrowsError(try backend.send(.next, expected: expected, deadline: 11, isAuthorized: { true }))
        XCTAssertEqual(client.commandDispatches, 1)
        XCTAssertEqual(client.resultPolls, 0)
        XCTAssertEqual(client.media.videoID, "lmnopqrstuv")
    }

    func testSeekReadbackClampsWithoutChangingTrackOrPlayback() throws {
        for (command, origin, target) in [(MacChromeCommand.seekForward30, 15.0, 45.0),
                                          (.seekBackward30, 60, 30), (.seekForward30, 115, 120),
                                          (.seekBackward30, 5, 0)] {
            let client = ChromeTestClient(); client.media = chromeMedia(paused: true, elapsed: origin)
            let backend = makeBackend(client)
            let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
            XCTAssertEqual(try backend.send(command, expected: expected, deadline: 11, isAuthorized: { true }), .applied)
            XCTAssertEqual(client.media.elapsedTime, target)
            XCTAssertEqual(client.media.identity, expected.media.identity)
            XCTAssertTrue(client.media.paused)
            XCTAssertEqual(client.commandDispatches, 1)
            XCTAssertFalse(command.changesTrack)
            XCTAssertTrue(command.isRelative)
        }
    }

    func testAbsoluteSeekCarriesFractionalPositionClampsAndRequiresNativeReadback() throws {
        for (position, target) in [(0.0, 0.0), (51.375, 51.375), (500.0, 120.0)] {
            let client = ChromeTestClient(); client.media = chromeMedia(paused: true)
            let backend = makeBackend(client)
            let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
            XCTAssertTrue(expected.media.enabledCommands.contains(MacChromeCommand.seekToPosition.rawValue))
            XCTAssertEqual(try backend.send(.seekToPosition, positionSeconds: position,
                expected: expected, deadline: 11, isAuthorized: { true }), .applied)
            XCTAssertEqual(client.media.elapsedTime, target)
            XCTAssertEqual(client.media.identity, expected.media.identity)
            XCTAssertTrue(client.media.paused)
            XCTAssertEqual(client.requests.first { $0["operation"] as? String == "command" }?["positionSeconds"] as? Double, position)
            XCTAssertEqual(client.commandDispatches, 1)
        }
        let client = ChromeTestClient(), backend = makeBackend(client)
        let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        for position in [nil, -1.0, .nan, .infinity, 31_536_001.0] as [Double?] {
            XCTAssertEqual(try backend.send(.seekToPosition, positionSeconds: position,
                expected: expected, deadline: 11, isAuthorized: { true }), .failed)
        }
        XCTAssertEqual(try backend.send(.pause, positionSeconds: 1,
            expected: expected, deadline: 11, isAuthorized: { true }), .failed)
        XCTAssertEqual(client.commandDispatches, 0)
        client.ignoreCommands = true
        XCTAssertEqual(try backend.send(.seekToPosition, positionSeconds: 51.375,
            expected: expected, deadline: 11, isAuthorized: { true }), .failed)
        XCTAssertEqual(client.commandDispatches, 1)
        XCTAssertEqual(client.media.elapsedTime, 15)
    }

    func testAbsoluteSeekFlowsThroughControllerCompositeAndChromeOnceAndRetiresWithAuthority() async throws {
        let backend = ChromeTestBackend(), chrome = makeRuntime(backend)
        let composite = MacSupportedNowPlayingRuntime(browser: chrome, music: ChromeRecoveryAbsentMusic())
        let controller = MacSystemNowPlayingController(runtime: composite, operationTimeout: 5,
                                                       now: { Date(timeIntervalSince1970: 1000) })
        defer { controller.stop() }
        let updates = ChromeTestBox<[WebRTCRemoteMediaStateUpdate]>([])
        let ready = expectation(description: "exact seekable Chrome source")
        controller.start { update in
            updates.update { $0.append(update) }
            if update.revision == 1 { ready.fulfill() }
        }
        await fulfillment(of: [ready], timeout: 2)
        let item = try XCTUnwrap(updates.get().last?.item)
        XCTAssertTrue(item.capabilities.canSeekToPosition)
        XCTAssertNil(controller.prepareCommand(.seekToPosition, contextID: item.contextID, isAuthorized: { true }))
        XCTAssertNil(controller.prepareCommand(.pause, contextID: item.contextID, positionSeconds: 57.125, isAuthorized: { true }))
        let prepared = try XCTUnwrap(controller.prepareCommand(.seekToPosition, contextID: item.contextID,
            positionSeconds: 57.125, isAuthorized: { true }))
        let results = await withTaskGroup(of: WebRTCRemoteMediaCommandResult.self) { group in
            for _ in 0..<8 { group.addTask { await controller.perform(prepared) } }
            var values: [WebRTCRemoteMediaCommandResult] = []
            for await result in group { values.append(result) }
            return values
        }
        XCTAssertEqual(results.filter { $0 == .applied }.count, 1)
        XCTAssertEqual(results.filter { $0 == .staleContext }.count, 7)
        XCTAssertEqual(backend.commands, [.seekToPosition])
        XCTAssertEqual(backend.positions, [57.125])
        XCTAssertEqual(backend.commandTargets, [chromePlayer().tab])
        let retired = try XCTUnwrap(controller.prepareCommand(.seekToPosition, contextID: item.contextID,
            positionSeconds: 60, isAuthorized: { true }))
        controller.invalidateCommands()
        let rejected = await controller.perform(retired)
        XCTAssertEqual(rejected, .staleContext)
        XCTAssertEqual(backend.commands.count, 1)
    }

    func testSeekCapabilityRequiresFiniteBoundedTimelineAndNewScriptSupport() throws {
        for media in [chromeMedia(canSeek: nil), chromeMedia(canSeek: false),
                      chromeMedia(duration: nil), chromeMedia(duration: 0), chromeMedia(duration: .infinity),
                      chromeMedia(duration: 31_536_001), chromeMedia(elapsed: nil),
                      chromeMedia(elapsed: -1), chromeMedia(elapsed: 121), chromeMedia(elapsed: .nan)] {
            XCTAssertFalse(media.enabledCommands.contains(6))
            XCTAssertFalse(media.enabledCommands.contains(7))
            XCTAssertFalse(media.enabledCommands.contains(MacChromeCommand.seekToPosition.rawValue))
        }
        let client = ChromeTestClient(); client.media = chromeMedia(canSeek: nil)
        let backend = makeBackend(client)
        let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        XCTAssertEqual(try backend.send(.seekForward30, expected: expected, deadline: 11, isAuthorized: { true }), .unsupported)
        XCTAssertEqual(client.commandDispatches, 0)
    }

    func testIgnoredSeekAndSeekTimeoutCannotClaimReadbackOrResend() throws {
        let client = ChromeTestClient(), backend = makeBackend(client)
        let expected = try XCTUnwrap(backend.readSnapshots(deadline: 11).first)
        client.ignoreCommands = true
        XCTAssertEqual(try backend.send(.seekForward30, expected: expected, deadline: 11, isAuthorized: { true }), .failed)
        XCTAssertEqual(client.media.elapsedTime, 15)
        client.ignoreCommands = false; client.commandError = OSStatus(errAETimeout)
        XCTAssertThrowsError(try backend.send(.seekForward30, expected: expected, deadline: 11, isAuthorized: { true }))
        XCTAssertEqual(client.media.elapsedTime, 45)
        XCTAssertEqual(client.commandDispatches, 2)
        XCTAssertEqual(client.resultPolls, 0)
    }

    func testSeekTimeoutConsumesOldRuntimeAuthorityUntilFreshSnapshot() async throws {
        for command in [6, 7] {
            let backend = ChromeTestBackend(); backend.commandError = .timedOut
            let runtime = makeRuntime(backend), old = try await snapshot(runtime)
            await assertSend(runtime, command: command, snapshot: old, equals: .failed)
            await assertSend(runtime, command: command, snapshot: old, equals: .staleContext)
            let fresh = try await snapshot(runtime)
            XCTAssertFalse(old.client === fresh.client)
            await assertSend(runtime, command: command, snapshot: old, equals: .staleContext)
            backend.commandError = nil
            await assertSend(runtime, command: command, snapshot: fresh, equals: .applied)
            XCTAssertEqual(backend.commands.count, 2)
        }
    }

    func testInitialMultiplePlayingSelectionIsDeterministic() throws {
        let first = chromePlayer(tab: "7"), second = chromePlayer(tab: "3")
        XCTAssertEqual(try MacChromeAppleEventsBackend.select([first, second], preferred: nil)?.tab.tabID, "7")
        XCTAssertEqual(try MacChromeAppleEventsBackend.select([second, first], preferred: first)?.tab.tabID, "7")
    }

    func testFirstPlayingStaysSelectedUntilPausedThenPromotesRemainingPlayingTab() async throws {
        let backend = ChromeTestBackend()
        let runtime = makeRuntime(backend)
        let first = try await snapshot(runtime)
        backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)),
                             chromePlayer(tab: "3", media: chromeMedia(paused: true))]
        let sticky = try await snapshot(runtime)
        XCTAssertTrue(first.client === sticky.client)
        backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), chromePlayer(tab: "3")]
        let other = try await snapshot(runtime)
        XCTAssertFalse(first.client === other.client)
        backend.snapshots = [chromePlayer(), chromePlayer(tab: "3")]
        let retained = try await snapshot(runtime)
        XCTAssertTrue(retained.client === other.client)
        backend.snapshots = [chromePlayer(), chromePlayer(tab: "3"), chromePlayer(tab: "4")]
        let three = try await snapshot(runtime)
        XCTAssertTrue(three.client === retained.client)
        backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)),
                             chromePlayer(tab: "3", media: chromeMedia(paused: true)), chromePlayer(tab: "4")]
        let promoted = try await snapshot(runtime)
        XCTAssertFalse(promoted.client === three.client)
        await assertSend(runtime, command: 1, snapshot: promoted, equals: .applied)
        XCTAssertEqual(backend.commandTargets.last?.tabID, "4")
        backend.snapshots = [chromePlayer()]
        let returned = try await snapshot(runtime)
        XCTAssertFalse(first.client === returned.client)
        await assertSend(runtime, command: 1, snapshot: first, equals: .staleContext)
    }

    func testIndeterminateReadAndStopRotateIdentityEvenForSameItem() async throws {
        let backend = ChromeTestBackend(); let runtime = makeRuntime(backend)
        let first = try await snapshot(runtime)
        backend.error = .timedOut
        guard case .retry = await fetch(runtime) else { return XCTFail("Timeout published") }
        XCTAssertEqual(runtime.lastDiscoveryStatus, .timedOut)
        await assertSend(runtime, command: 1, snapshot: first, equals: .staleContext)
        backend.error = nil
        let second = try await snapshot(runtime)
        XCTAssertFalse(first.client === second.client)
        runtime.stop()
        let third = try await snapshot(runtime)
        XCTAssertFalse(second.client === third.client)
    }

    func testPausedOwnerRecoversAfterTimeoutWithoutRevivingOldCommandAuthority() async throws {
        let backend = ChromeTestBackend()
        let pausedOther = chromePlayer(tab: "3", media: chromeMedia(paused: true))
        backend.snapshots = [chromePlayer(), pausedOther]
        let runtime = makeRuntime(backend)
        let playing = try await snapshot(runtime)
        await assertSend(runtime, command: 1, snapshot: playing, equals: .applied)
        backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), pausedOther]
        let paused = try await snapshot(runtime)
        XCTAssertTrue(paused.client === playing.client)
        XCTAssertTrue(paused.enabledCommands.contains(0))

        backend.error = .timedOut
        guard case .retry = await fetch(runtime) else { return XCTFail("Timeout retained command authority") }
        await assertSend(runtime, command: 0, snapshot: paused, equals: .staleContext)
        backend.error = nil
        let recovered = try await snapshot(runtime)
        XCTAssertEqual(runtime.lastDiscoveryStatus, .available)
        XCTAssertFalse(recovered.client === paused.client)
        XCTAssertEqual(recovered.metadata.playbackRate, 0)
        await assertSend(runtime, command: 0, snapshot: paused, equals: .staleContext)
        await assertSend(runtime, command: 0, snapshot: recovered, equals: .applied)
        XCTAssertEqual(backend.commands, [.pause, .play])
    }

    func testTimeoutHintRequiresEveryExactOwnerTabAndItemFieldAndCannotSurviveObservedReplacement() async throws {
        let mutations = [
            chromePlayer(media: chromeMedia(paused: true), owner: .init(processID: 43, launchDate: chromeOwner.launchDate)),
            chromePlayer(media: chromeMedia(paused: true), owner: .init(processID: 42, launchDate: Date(timeIntervalSince1970: 101))),
            chromePlayer(media: chromeMedia(paused: true), window: "4"),
            chromePlayer(tab: "4", media: chromeMedia(paused: true)),
            chromePlayer(media: chromeMedia(paused: true, document: "00000000-0000-4000-8000-000000000004")),
            chromePlayer(media: chromeMedia(paused: true, item: "00000000-0000-4000-8000-000000000004")),
            chromePlayer(media: chromeMedia(paused: true, generation: 2)),
            chromePlayer(media: chromeMedia(video: "lmnopqrstuv", paused: true))
        ]
        for changed in mutations {
            let backend = ChromeTestBackend(), runtime = makeRuntime(backend)
            let old = try await snapshot(runtime)
            backend.error = .timedOut
            guard case .retry = await fetch(runtime) else { return XCTFail("Timeout published") }
            backend.error = nil
            let other = chromePlayer(tab: "3", media: chromeMedia(paused: true))
            backend.snapshots = [changed, other]
            guard case .retry = await fetch(runtime) else { return XCTFail("Changed identity reused timeout hint") }
            XCTAssertEqual(runtime.lastDiscoveryStatus, .ambiguousPlayers)
            backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), other]
            guard case .retry = await fetch(runtime) else { return XCTFail("Retired owner returned through ABA") }
            await assertSend(runtime, command: 1, snapshot: old, equals: .staleContext)
            XCTAssertTrue(backend.commands.isEmpty)
        }
    }

    func testPlayingTakeoverReplacesTimeoutHintAndRemainsStickyWhenBothPause() async throws {
        let backend = ChromeTestBackend(), runtime = makeRuntime(backend)
        let old = try await snapshot(runtime)
        backend.error = .timedOut
        guard case .retry = await fetch(runtime) else { return XCTFail("Timeout published") }
        backend.error = nil
        let firstPaused = chromePlayer(media: chromeMedia(paused: true))
        backend.snapshots = [firstPaused, chromePlayer(tab: "3", media: chromeMedia(title: "Other"))]
        let takeover = try await snapshot(runtime)
        XCTAssertEqual(takeover.metadata.title, "Other")
        backend.snapshots = [firstPaused, chromePlayer(tab: "3", media: chromeMedia(paused: true, title: "Other"))]
        let paused = try await snapshot(runtime)
        XCTAssertTrue(takeover.client === paused.client)
        XCTAssertEqual(paused.metadata.title, "Other")
        await assertSend(runtime, command: 1, snapshot: old, equals: .staleContext)
        await assertSend(runtime, command: 0, snapshot: paused, equals: .applied)
        XCTAssertEqual(backend.commands, [.play])
    }

    func testRemovedOwnerCannotStealSelectionBackFromFreshPausedPlayer() async throws {
        let backend = ChromeTestBackend(), runtime = makeRuntime(backend)
        let old = try await snapshot(runtime)
        backend.error = .timedOut
        guard case .retry = await fetch(runtime) else { return XCTFail("Timeout published") }
        backend.error = nil
        let other = chromePlayer(tab: "3", media: chromeMedia(paused: true, title: "Other"))
        backend.snapshots = [other]
        let replacement = try await snapshot(runtime)
        backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), other]
        let selected = try await snapshot(runtime)
        XCTAssertTrue(replacement.client === selected.client)
        XCTAssertEqual(selected.metadata.title, "Other")
        await assertSend(runtime, command: 1, snapshot: old, equals: .staleContext)
        await assertSend(runtime, command: 0, snapshot: selected, equals: .applied)
    }

    func testMultiplePlayingAfterTimeoutPreserveSelectionButNeverReviveOldAuthority() async throws {
        let backend = ChromeTestBackend(), runtime = makeRuntime(backend)
        let old = try await snapshot(runtime)
        backend.error = .timedOut
        guard case .retry = await fetch(runtime) else { return XCTFail("Timeout published") }
        backend.error = nil
        backend.snapshots = [chromePlayer(), chromePlayer(tab: "3")]
        let recovered = try await snapshot(runtime)
        XCTAssertFalse(recovered.client === old.client)
        backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), chromePlayer(tab: "3", media: chromeMedia(paused: true))]
        let paused = try await snapshot(runtime)
        XCTAssertTrue(paused.client === recovered.client)
        await assertSend(runtime, command: 1, snapshot: old, equals: .staleContext)
    }

    func testStopClearsOwnershipButEveryUncertainReadRetainsOnlyHint() async throws {
        let failures: [MacChromeBackendError?] = [nil, .permissionRequired, .permissionDenied,
            .javascriptPermissionRequired, .staleItem, .invalidData, .unavailable, .ambiguousPlayers]
        for failure in failures {
            let backend = ChromeTestBackend(), runtime = makeRuntime(backend)
            let old = try await snapshot(runtime)
            backend.error = .timedOut
            guard case .retry = await fetch(runtime) else { return XCTFail("Timeout published") }
            if let failure {
                backend.error = failure
                guard case .retry = await fetch(runtime) else { return XCTFail("Failure published") }
            } else { runtime.stop() }
            backend.error = nil
            backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), chromePlayer(tab: "3", media: chromeMedia(paused: true))]
            if failure == nil {
                guard case .retry = await fetch(runtime) else { return XCTFail("Retired hint survived stop") }
            } else {
                let recovered = try await snapshot(runtime)
                XCTAssertFalse(recovered.client === old.client)
                XCTAssertEqual(recovered.metadata.playbackRate, 0)
            }
            await assertSend(runtime, command: 1, snapshot: old, equals: .staleContext)
            XCTAssertTrue(backend.commands.isEmpty)
        }
    }

    func testConfirmedAbsenceRetiresButInvalidMetadataHoldsOwnershipWithoutAuthority() async throws {
        let unavailableSnapshots: [[MacChromePlayerSnapshot]] = [[], [chromePlayer(media: chromeMedia(title: ""))]]
        for unavailable in unavailableSnapshots {
            let backend = ChromeTestBackend(), runtime = makeRuntime(backend)
            _ = try await snapshot(runtime)
            backend.error = .timedOut
            guard case .retry = await fetch(runtime) else { return XCTFail("Timeout published") }
            backend.error = nil; backend.snapshots = unavailable
            if unavailable.isEmpty {
                guard case .noActiveMedia = await fetch(runtime) else { return XCTFail("Absent media published") }
            } else {
                guard case .retry = await fetch(runtime) else { return XCTFail("Invalid metadata published") }
            }
            backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), chromePlayer(tab: "3", media: chromeMedia(paused: true))]
            if unavailable.isEmpty {
                guard case .retry = await fetch(runtime) else { return XCTFail("Confirmed absence preserved old hint") }
            } else { _ = try await snapshot(runtime) }
        }
    }

    func testPendingPlayRetiredByTimeoutCannotRegainAuthorityWhenPausedOwnerRecovers() async throws {
        let backend = ChromeTestBackend()
        let queue = DispatchQueue(label: "chrome-paused-recovery-test")
        let runtime = MacChromeNowPlayingRuntime(backend: backend, queue: queue, now: { 10 })
        _ = try await snapshot(runtime)
        backend.snapshots = [chromePlayer(media: chromeMedia(paused: true)), chromePlayer(tab: "3", media: chromeMedia(paused: true))]
        let old = try await snapshot(runtime)
        queue.suspend(); backend.error = .timedOut
        let read = expectation(description: "timeout revokes pending Play")
        runtime.fetchSnapshot { value in
            guard case .retry = value else { return XCTFail("Timeout published") }
            read.fulfill()
        }
        let command = expectation(description: "old pending Play rejected")
        runtime.send(rawCommand: 0, snapshot: old, isAuthorized: { true }) { value in
            XCTAssertEqual(value, .staleContext); command.fulfill()
        }
        queue.resume()
        await fulfillment(of: [read, command], timeout: 2)
        XCTAssertTrue(backend.commands.isEmpty)
        backend.error = nil
        let fresh = try await snapshot(runtime)
        XCTAssertFalse(fresh.client === old.client)
        await assertSend(runtime, command: 0, snapshot: old, equals: .staleContext)
        await assertSend(runtime, command: 0, snapshot: fresh, equals: .applied)
        XCTAssertEqual(backend.commands, [.play])
    }

    func testPausedRecoveryAcrossRealChromeCompositeAndControllerRequiresFreshPlayContext() async throws {
        let backend = ChromeTestBackend()
        let other = chromePlayer(tab: "3", media: chromeMedia(paused: true, title: "Other"))
        backend.snapshots = [chromePlayer(), other]
        backend.onCommand = { [weak backend] command in
            guard let backend else { return }
            backend.snapshots = [chromePlayer(media: chromeMedia(paused: command == .pause)), other]
        }
        let chrome = makeRuntime(backend)
        let composite = MacSupportedNowPlayingRuntime(browser: chrome, music: ChromeRecoveryAbsentMusic())
        let controller = MacSystemNowPlayingController(runtime: composite, operationTimeout: 5,
                                                       now: { Date(timeIntervalSince1970: 1000) })
        defer { controller.stop() }
        let updates = ChromeTestBox<[WebRTCRemoteMediaStateUpdate]>([])
        let playing = expectation(description: "exact Chrome owner playing")
        let paused = expectation(description: "exact owner paused")
        let withdrawn = expectation(description: "uncertainty withdraws outer authority")
        let recovered = expectation(description: "fresh same owner paused")
        let resumed = expectation(description: "fresh Play resumes exact owner")
        controller.start { update in
            updates.update { $0.append(update) }
            switch update.revision {
            case 1: playing.fulfill()
            case 2: paused.fulfill()
            case 3: withdrawn.fulfill()
            case 4: recovered.fulfill()
            case 5: resumed.fulfill()
            default: XCTFail("Unexpected additional media publication")
            }
        }
        await fulfillment(of: [playing], timeout: 2)
        let playingItem = try XCTUnwrap(updates.get().last?.item)
        XCTAssertEqual(playingItem.title, "Video")
        let pause = try XCTUnwrap(controller.prepareCommand(.pause, contextID: playingItem.contextID,
                                                            isAuthorized: { true }))
        let pauseResult = await controller.perform(pause)
        XCTAssertEqual(pauseResult, .applied)
        await fulfillment(of: [paused], timeout: 2)
        let pausedItem = try XCTUnwrap(updates.get().last?.item)
        XCTAssertEqual(pausedItem.playbackState, .paused)
        XCTAssertTrue(pausedItem.capabilities.canPlay)
        let stalePlay = try XCTUnwrap(controller.prepareCommand(.play, contextID: pausedItem.contextID,
                                                                isAuthorized: { true }))
        backend.error = .timedOut
        controller.refresh()
        await fulfillment(of: [withdrawn], timeout: 2)
        XCTAssertNil(updates.get().last?.item)
        XCTAssertNil(controller.prepareCommand(.play, contextID: pausedItem.contextID, isAuthorized: { true }))
        let uncertainResult = await controller.perform(stalePlay)
        XCTAssertEqual(uncertainResult, .staleContext)
        backend.error = nil
        controller.refresh()
        await fulfillment(of: [recovered], timeout: 2)
        let freshItem = try XCTUnwrap(updates.get().last?.item)
        XCTAssertNotEqual(freshItem.contextID, pausedItem.contextID)
        XCTAssertEqual(freshItem.title, pausedItem.title)
        XCTAssertEqual(freshItem.playbackState, .paused)
        XCTAssertTrue(freshItem.capabilities.canPlay)
        let staleResult = await controller.perform(stalePlay)
        XCTAssertEqual(staleResult, .staleContext)
        let freshPlay = try XCTUnwrap(controller.prepareCommand(.play, contextID: freshItem.contextID,
                                                                isAuthorized: { true }))
        let playResult = await controller.perform(freshPlay)
        XCTAssertEqual(playResult, .applied)
        await fulfillment(of: [resumed], timeout: 2)
        XCTAssertEqual(updates.get().last?.item?.playbackState, .playing)
        XCTAssertEqual(backend.commands, [.pause, .play])
        XCTAssertEqual(backend.commandTargets, [chromePlayer().tab, chromePlayer().tab])
        XCTAssertEqual(updates.get().map(\.revision), [1, 2, 3, 4, 5])
    }

    func testStoppedAndExpiredQueuedReadsNeverCallBackendOrPublish() async {
        let backend = ChromeTestBackend(); let clock = ChromeTestBox<TimeInterval>(10)
        let queue = DispatchQueue(label: "chrome-read-test")
        let runtime = MacChromeNowPlayingRuntime(backend: backend, queue: queue, now: { clock.get() })
        queue.suspend()
        let done = expectation(description: "stopped read")
        runtime.fetchSnapshot { value in
            guard case .retry = value else { return XCTFail("Stopped read published") }
            done.fulfill()
        }
        runtime.stop(); queue.resume()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(backend.reads, 0)
        queue.suspend()
        let expired = expectation(description: "expired read")
        runtime.fetchSnapshot { value in
            guard case .retry = value else { return XCTFail("Expired read published") }
            expired.fulfill()
        }
        clock.set(12); queue.resume()
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertEqual(backend.reads, 0)
        XCTAssertEqual(runtime.lastDiscoveryStatus, .timedOut)
    }

    func testRevokedAndExpiredQueuedCommandsCannotCallBackend() async throws {
        for expiry in [false, true] {
            let backend = ChromeTestBackend(); let clock = ChromeTestBox<TimeInterval>(10)
            let queue = DispatchQueue(label: "chrome-command-test")
            let runtime = MacChromeNowPlayingRuntime(backend: backend, queue: queue, now: { clock.get() })
            let current = try await snapshot(runtime)
            let authorization = WebRTCControlAuthorization()
            queue.suspend()
            let done = expectation(description: "command canceled")
            runtime.send(rawCommand: 1, snapshot: current, isAuthorized: { authorization.isValid }) {
                XCTAssertEqual($0, .staleContext); done.fulfill()
            }
            if expiry { clock.set(12) } else { authorization.revoke() }
            queue.resume()
            await fulfillment(of: [done], timeout: 2)
            XCTAssertTrue(backend.commands.isEmpty)
        }
    }

    func testRelativeTimeoutConsumesOldTokenAcrossRefreshAndDoesNotDisableFreshControl() async throws {
        let backend = ChromeTestBackend(); backend.commandError = .timedOut
        let runtime = makeRuntime(backend)
        let first = try await snapshot(runtime)
        await assertSend(runtime, command: 4, snapshot: first, equals: .failed)
        await assertSend(runtime, command: 4, snapshot: first, equals: .staleContext)
        let fresh = try await snapshot(runtime)
        XCTAssertFalse(first.client === fresh.client)
        await assertSend(runtime, command: 4, snapshot: first, equals: .staleContext)
        await assertSend(runtime, command: 4, snapshot: fresh, equals: .failed)
        XCTAssertEqual(backend.commands, [.next, .next])
    }

    func testConfirmedSeekPreservesSelectionAfterFreshReadButUnknownResultRotates() async throws {
        for command in [6, 7] {
            let backend = ChromeTestBackend()
            let runtime = makeRuntime(backend)
            let first = try await snapshot(runtime)
            await assertSend(runtime, command: command, snapshot: first, equals: .applied)
            await assertSend(runtime, command: command, snapshot: first, equals: .staleContext)
            let refreshed = try await snapshot(runtime)
            XCTAssertTrue(refreshed.client === first.client)
            backend.commandError = .timedOut
            await assertSend(runtime, command: command, snapshot: refreshed, equals: .failed)
            let recovered = try await snapshot(runtime)
            XCTAssertFalse(recovered.client === refreshed.client)
            await assertSend(runtime, command: command, snapshot: refreshed, equals: .staleContext)
            backend.commandError = nil
            await assertSend(runtime, command: command, snapshot: recovered, equals: .applied)
            backend.snapshots = [chromePlayer(media: chromeMedia(item: UUID().uuidString))]
            let replacement = try await snapshot(runtime)
            XCTAssertFalse(replacement.client === recovered.client)
            await assertSend(runtime, command: command, snapshot: recovered, equals: .staleContext)
            XCTAssertEqual(backend.commands.count, 3)
        }
    }

    func testRoutineFetchAheadOfQueuedRelativeCommandDoesNotCancelItsOwnAuthority() async throws {
        let backend = ChromeTestBackend()
        let queue = DispatchQueue(label: "chrome-overlap-test")
        let runtime = MacChromeNowPlayingRuntime(backend: backend, queue: queue, now: { 10 })
        let first = try await snapshot(runtime)
        queue.suspend()
        let fetched = expectation(description: "overlapping unchanged read")
        runtime.fetchSnapshot { value in
            guard case .snapshot(let value) = value else { return XCTFail("Routine read became indeterminate") }
            XCTAssertTrue(value.client === first.client)
            fetched.fulfill()
        }
        let commanded = expectation(description: "relative command executes once")
        runtime.send(rawCommand: 4, snapshot: first, isAuthorized: { true }) {
            XCTAssertEqual($0, .applied); commanded.fulfill()
        }
        queue.resume()
        await fulfillment(of: [fetched, commanded], timeout: 2)
        XCTAssertEqual(backend.commands, [.next])
        await assertSend(runtime, command: 4, snapshot: first, equals: .staleContext)
        let refreshed = try await snapshot(runtime)
        XCTAssertFalse(refreshed.client === first.client)
    }

    func testPermissionCompletionAfterStopCannotReviveLifecycle() async {
        let backend = ChromeTestBackend(); let runtime = makeRuntime(backend)
        let started = expectation(description: "permission began")
        let gate = DispatchSemaphore(value: 0)
        backend.onPermission = { started.fulfill(); _ = gate.wait(timeout: .now() + 2) }
        let done = expectation(description: "permission completion")
        runtime.requestAutomationPermission { accepted in XCTAssertFalse(accepted); done.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        runtime.stop(); gate.signal()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(backend.permissions, 1)
        XCTAssertEqual(runtime.lastDiscoveryStatus, .idle)
    }

    private func makeBackend(_ client: ChromeTestClient, now: @escaping @Sendable () -> TimeInterval = { 10 })
        -> MacChromeAppleEventsBackend {
        .init(client: client, now: now, wallNow: { 1000 })
    }
    private func makeRuntime(_ backend: ChromeTestBackend) -> MacChromeNowPlayingRuntime {
        .init(backend: backend, now: { 10 })
    }
    private func fetch(_ runtime: MacChromeNowPlayingRuntime) async -> MacNowPlayingRuntimeSnapshotResult {
        await withCheckedContinuation { continuation in runtime.fetchSnapshot { continuation.resume(returning: $0) } }
    }
    private func snapshot(_ runtime: MacChromeNowPlayingRuntime) async throws -> MacNowPlayingRuntimeSnapshot {
        guard case .snapshot(let snapshot) = await fetch(runtime) else { throw MacChromeBackendError.unavailable }
        return snapshot
    }
    private func assertSend(_ runtime: MacChromeNowPlayingRuntime, command: Int, snapshot: MacNowPlayingRuntimeSnapshot,
                            equals expected: WebRTCRemoteMediaCommandResult,
                            file: StaticString = #filePath, line: UInt = #line) async {
        let result = await withCheckedContinuation { continuation in
            runtime.send(rawCommand: command, snapshot: snapshot, isAuthorized: { true }) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(result, expected, file: file, line: line)
    }
}
