@preconcurrency import AppKit
import CoreServices
import Darwin
import XCTest
@testable import CaptureServer
import WebRTCTransport

/// Explicit isolated-browser oracle. It never launches a host, reads a pairing key,
/// opens a native audio device, or addresses the user's normal browser.
final class NativeYouTubeHandoffOracleTests: XCTestCase {
    func testExactNativeSourcePauseAndReadback() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BELUGA_HANDOFF_ORACLE_BROWSER"],
              let text = env["BELUGA_HANDOFF_ORACLE_PID"], let pid = Int32(text) else {
            throw XCTSkip("Requires an explicitly approved isolated browser and exact PID")
        }
        let client = try IsolatedHandoffChromeClient(path: path, pid: pid)
        let permission = client.automationPermission(owner: client.owner, askUser: false)
        guard permission == noErr else { throw NativeOracleError.permission(permission) }
        let backend = MacChromeAppleEventsBackend(client: client)
        let original = try XCTUnwrap(backend.readSnapshots(deadline: uptime + 1.5).only)
        XCTAssertEqual(original.media.videoID, "M7lc1UVf-VE")
        XCTAssertFalse(original.media.paused, "The owned demo must actually be playing first")
        guard original.media.videoID == "M7lc1UVf-VE", !original.media.paused else {
            throw NativeOracleError.precondition
        }
        let browser = MacChromeNowPlayingRuntime(backend: backend)
        let controller = MacSystemNowPlayingController(runtime: browser, pollInterval: 0.25,
            stateDiagnostics: { _ in })
        let state = NativeOracleState()
        controller.start { state.store($0) }
        defer { controller.stop() }
        for _ in 0..<100 {
            if state.item?.playbackState == .playing { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let item = try XCTUnwrap(state.item)
        XCTAssertEqual(item.artwork?.videoID, original.media.videoID)
        let value = await controller.prepareHandoff(contextID: item.contextID, isAuthorized: { true })
        let prepared = try XCTUnwrap(value)
        let current = try XCTUnwrap(backend.readSnapshots(deadline: uptime + 1.5).only)
        XCTAssertTrue(current.hasSameItem(as: original))
        guard current.hasSameItem(as: original), !current.media.paused,
              let position = current.media.elapsedTime else { throw NativeOracleError.precondition }
        // This native-only probe supplies the receiving position. The joined phone oracle
        // must replace this boundary with a fresh exact-operation playback commit.
        let result = await controller.performHandoffPause(prepared, phonePositionSeconds: position)
        XCTAssertEqual(result, .applied)
        let after = try XCTUnwrap(backend.readSnapshots(deadline: uptime + 1.5).only)
        XCTAssertTrue(after.hasSameItem(as: original))
        XCTAssertTrue(after.media.paused)
        XCTAssertEqual(try XCTUnwrap(after.media.elapsedTime), position, accuracy: 1)
        let duplicate = await controller.performHandoffPause(prepared, phonePositionSeconds: position)
        XCTAssertEqual(duplicate, .staleContext)
        XCTAssertEqual(client.commands, 1, "No fallback/retry may dispatch a second native command")
        XCTAssertEqual(client.permissionPrompts, 0)
        XCTAssertEqual(client.runningOwner(), client.owner)
        let proof = XCTAttachment(string: "nativeChrome=true originalPID=\(original.tab.owner.processID) "
            + "window=\(original.tab.windowID) tab=\(original.tab.tabID) video=\(original.media.videoID) "
            + "beforePaused=\(original.media.paused) afterPaused=\(after.media.paused) "
            + "commands=\(client.commands) duplicate=\(duplicate) receiverPosition=TEST_INPUT")
        proof.name = "native-youtube-exact-pause-readback"
        proof.lifetime = .keepAlways
        add(proof)
        print("NATIVE_HANDOFF_ORACLE exactSource=true paused=\(after.media.paused) commands=\(client.commands) receiverPosition=TEST_INPUT")
    }

    private var uptime: Double { ProcessInfo.processInfo.systemUptime }
}

private enum NativeOracleError: Error { case isolation, permission(OSStatus), precondition }

private final class NativeOracleState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: WebRTCRemoteMediaItem?
    var item: WebRTCRemoteMediaItem? { lock.withLock { value } }
    func store(_ state: WebRTCRemoteMediaStateUpdate) { lock.withLock { value = state.item } }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

/// Only discovery is injected. Permission checks and every Apple Event are real,
/// process-addressed, and fenced to this exact private copy and launch generation.
private final class IsolatedHandoffChromeClient: MacChromeAppleEventsClient, @unchecked Sendable {
    let owner: MacChromePlayerIdentity
    private let path: String
    private let start: NativeOracleProcessStart
    private let lock = NSLock()
    private var commandCount = 0
    private var promptCount = 0
    var commands: Int { lock.withLock { commandCount } }
    var permissionPrompts: Int { lock.withLock { promptCount } }

    init(path: String, pid: Int32) throws {
        let url = URL(fileURLWithPath: path)
        guard pid > 0, url.standardizedFileURL.path == path,
              url.resolvingSymlinksInPath().path == path,
              url.lastPathComponent == "Google Chrome.app",
              url.deletingLastPathComponent().deletingLastPathComponent().path == "/Volumes/t7",
              url.deletingLastPathComponent().lastPathComponent.hasPrefix("beluga-native-handoff."),
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleURL?.path == path, app.bundleIdentifier == "com.google.Chrome",
              let start = NativeOracleProcessStart.read(pid) else { throw NativeOracleError.isolation }
        self.path = path
        self.start = start
        // A directly executed, fresh-profile copy has no LaunchServices launchDate.
        // Keep the exact kernel start tuple as the authority, rechecked on every event.
        owner = .init(processID: pid, launchDate: start.date)
    }

    func runningOwner() -> MacChromePlayerIdentity? {
        guard let app = NSRunningApplication(processIdentifier: owner.processID),
              !app.isTerminated, app.bundleURL?.path == path,
              app.bundleIdentifier == "com.google.Chrome",
              NativeOracleProcessStart.read(owner.processID) == start else { return nil }
        return owner
    }

    func automationPermission(owner: MacChromePlayerIdentity, askUser: Bool) -> OSStatus {
        if askUser { lock.withLock { promptCount += 1 }; return OSStatus(errAEEventNotPermitted) }
        guard runningOwner() == owner else { return OSStatus(errAEEventNotPermitted) }
        let target = NSAppleEventDescriptor(processIdentifier: owner.processID)
        guard let address = target.aeDesc else {
            return OSStatus(errAEEventNotPermitted)
        }
        return AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, false)
    }

    func sendEvent(_ event: NSAppleEventDescriptor, options: NSAppleEventDescriptor.SendOptions,
                   timeout: TimeInterval) throws -> NSAppleEventDescriptor {
        guard runningOwner() == owner,
              Self.isSafeEvent(event, ownerPID: owner.processID, options: options, timeout: timeout)
        else { throw NativeOracleError.isolation }
        if let script = event.paramDescriptor(forKeyword: 0x4A765363)?.stringValue,
           script.contains("\"operation\":\"command\"") { lock.withLock { commandCount += 1 } }
        do {
            let reply = try event.sendEvent(options: options, timeout: timeout)
            if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != 0 {
                print("NATIVE_ORACLE_REPLY_ERROR class=\(event.eventClass) id=\(event.eventID) code=\(error.int32Value) "
                    + (reply.paramDescriptor(forKeyword: keyErrorString)?.stringValue ?? "").prefix(512))
            }
            return reply
        } catch {
            let nsError = error as NSError
            print("NATIVE_ORACLE_SEND_ERROR class=\(event.eventClass) id=\(event.eventID) domain=\(nsError.domain) "
                + "code=\(nsError.code) message=\(nsError.localizedDescription.prefix(512))")
            throw error
        }
    }

    static func isSafeEvent(_ event: NSAppleEventDescriptor, ownerPID: Int32,
                            options: NSAppleEventDescriptor.SendOptions, timeout: TimeInterval) -> Bool {
        guard ownerPID > 0, options == MacChromeAppleEventsBackend.sendOptions,
              timeout.isFinite, timeout > 0, timeout <= 0.35,
              (event.eventClass == kAECoreSuite && event.eventID == kAEGetData)
                || (event.eventClass == 0x43725375 && event.eventID == 0x45784A61),
              let target = event.attributeDescriptor(forKeyword: keyAddressAttr),
              target.descriptorType == typeKernelProcessID,
              target.data.count == MemoryLayout<Int32>.size else { return false }
        return target.data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) } == ownerPID
    }
}

private struct NativeOracleProcessStart: Equatable {
    let seconds: UInt64
    let microseconds: UInt64
    var date: Date { Date(timeIntervalSince1970: Double(seconds) + Double(microseconds) / 1_000_000) }

    static func read(_ pid: Int32) -> Self? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_pid == UInt32(pid), info.pbi_start_tvsec > 0,
              info.pbi_start_tvusec < 1_000_000 else { return nil }
        return .init(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }
}

final class NativeYouTubeHandoffIsolationTests: XCTestCase {
    func testKernelIdentityUsesExactStartTupleAndRejectsMissingProcesses() throws {
        XCTAssertNil(NativeOracleProcessStart.read(0))
        XCTAssertNil(NativeOracleProcessStart.read(-1))
        let current = try XCTUnwrap(NativeOracleProcessStart.read(getpid()))
        XCTAssertEqual(current, NativeOracleProcessStart.read(getpid()))
        XCTAssertNotEqual(current, .init(seconds: current.seconds + 1, microseconds: current.microseconds))
        XCTAssertNotEqual(current, .init(seconds: current.seconds, microseconds: current.microseconds + 1))
    }

    func testNormalBrowserAndNonPrivatePathsAreRejectedBeforeEvents() {
        for path in ["/Applications/Google Chrome.app", "/tmp/Google Chrome.app",
                     "/Volumes/t7/beluga-native-handoff.fixture/../Google Chrome.app"] {
            XCTAssertThrowsError(try IsolatedHandoffChromeClient(path: path, pid: getpid()))
        }
    }

    func testEventFenceRejectsOtherPIDsCommandsAndPermissionPromptOptions() {
        func event(_ pid: Int32, _ eventClass: AEEventClass = kAECoreSuite,
                   _ eventID: AEEventID = kAEGetData) -> NSAppleEventDescriptor {
            .init(eventClass: eventClass, eventID: eventID, targetDescriptor: .init(processIdentifier: pid),
                  returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        }
        let options = MacChromeAppleEventsBackend.sendOptions
        XCTAssertTrue(IsolatedHandoffChromeClient.isSafeEvent(event(42), ownerPID: 42, options: options, timeout: 0.35))
        XCTAssertTrue(IsolatedHandoffChromeClient.isSafeEvent(event(42, 0x43725375, 0x45784A61),
            ownerPID: 42, options: options, timeout: 0.1))
        XCTAssertFalse(IsolatedHandoffChromeClient.isSafeEvent(event(43), ownerPID: 42, options: options, timeout: 0.1))
        XCTAssertFalse(IsolatedHandoffChromeClient.isSafeEvent(event(42, kCoreEventClass, kAEQuitApplication),
            ownerPID: 42, options: options, timeout: 0.1))
        XCTAssertFalse(IsolatedHandoffChromeClient.isSafeEvent(event(42), ownerPID: 42, options: [], timeout: 0.1))
        for timeout in [0, -1, 0.351, .infinity, .nan] {
            XCTAssertFalse(IsolatedHandoffChromeClient.isSafeEvent(event(42), ownerPID: 42, options: options, timeout: timeout))
        }
    }
}
