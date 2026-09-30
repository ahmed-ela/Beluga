import XCTest

/// Real app/extension IPC and native WebRTC loopback; not physical lock-screen evidence.
@MainActor
final class MediaNotificationIntegrationUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "org.example.AudioStreamer.dev")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw NSError(domain: "SimulatorOnlyOracle", code: 1)
        #endif
    }

    override func tearDownWithError() throws {
        // This bundle is the isolated simulator development app, never the production app.
        #if targetEnvironment(simulator)
        app.terminate()
        #endif
    }

    func testFreshNotificationControlsReachExactLoopbackHostSources() throws {
        try openFreshNotification()
        try exerciseControls()
        capture("integrated-controls-after-five-host-commands")
        XCUIDevice.shared.press(.home)
        app.activate()
        assertHostEvidence()
        app.buttons["Stop local peers"].tap()
        wait(NSPredicate(format: "label == %@", "Stopped"), on: app.staticTexts["notificationFixtureStatus"])
    }

    func testExternalHostPauseUpdatesExpandedCardBeforeNextPlayCommand() throws {
        var originalDelivery: (counter: UInt64, fingerprint: String)?
        try openFreshNotification(beforeExpansion: {
            originalDelivery = try self.inspectDeliveredNotification()
            self.wait(NSPredicate(format: "label == %@",
                "revision=1;commands=0;A=playing:120;B=paused:240;received="),
                on: self.app.staticTexts["notificationFixtureEvidence"])
            let schedule = self.app.buttons["Schedule external browser pause"]
            self.wait(NSPredicate(format: "hittable == true AND enabled == true"), on: schedule)
            schedule.tap()
            self.wait(NSPredicate(format: "label == %@", "changes=0;phase=scheduled;context=A"),
                      on: self.app.staticTexts["notificationExternalChangeEvidence"])
        })
        let original = try XCTUnwrap(originalDelivery)
        let slider = springboard.sliders["mediaPlaybackPosition"]
        wait(NSPredicate(format: "hittable == true AND enabled == true"), on: springboard.buttons["Pause"])
        XCTAssertFalse(springboard.buttons["Play"].exists)
        wait(NSPredicate(format: "value == %@", "2:00 of 15:00"), on: slider)
        capture("external-host-pause-initial-playing")

        // Do not press a notification control: only the fixture host changes playback.
        XCTAssertTrue(source("Browser", playing: false).waitForExistence(timeout: 35),
                      springboard.debugDescription)
        XCTAssertFalse(source("Browser", playing: true).exists, "External pause left a stale Playing source label")
        XCTAssertTrue(source("Music", playing: false).exists, "An external pause must not retarget the source")
        wait(NSPredicate(format: "hittable == true AND enabled == true"), on: springboard.buttons["Play"])
        XCTAssertFalse(springboard.buttons["Pause"].exists, "External pause left a stale Pause action")
        wait(NSPredicate(format: "value == %@", "2:00 of 15:00"), on: slider)
        capture("external-host-pause-observed-without-command")

        try command("Play")
        XCTAssertTrue(source("Browser", playing: true).waitForExistence(timeout: 5), springboard.debugDescription)
        XCTAssertFalse(source("Browser", playing: false).exists)
        wait(NSPredicate(format: "hittable == true AND enabled == true"), on: springboard.buttons["Pause"])
        XCTAssertFalse(springboard.buttons["Play"].exists)
        capture("external-host-pause-resumed-after-one-play")

        dismissWithHomeTwiceThenActivate()
        wait(NSPredicate(format: "label == %@",
            "revision=3;commands=1;A=playing:120;B=paused:240;received=A:play"),
            on: app.staticTexts["notificationFixtureEvidence"])
        wait(NSPredicate(format: "label == %@", "changes=1;phase=published;context=A;revision=2"),
            on: app.staticTexts["notificationExternalChangeEvidence"])
        _ = try inspectDeliveredNotification(previous: original)
        capture("external-host-pause-exact-revisions-and-single-play-receipt")
        app.buttons["Stop local peers"].tap()
        wait(NSPredicate(format: "label == %@", "Stopped"), on: app.staticTexts["notificationFixtureStatus"])
    }

    func testTimelineDragAndTrackButtonsReachExactHostWithoutRetargeting() throws {
        try openFreshNotification()
        let slider = springboard.sliders["mediaPlaybackPosition"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3), springboard.debugDescription)
        wait(NSPredicate(format: "hittable == true AND enabled == true"), on: slider)
        for label in ["Previous track", "Backward 30 seconds", "Pause", "Forward 30 seconds", "Next track"] {
            XCTAssertTrue(springboard.buttons[label].isHittable, "Missing visible control: \(label)")
        }
        // Touch the real initial thumb and release once; no accessibility set-value shortcut.
        let width = slider.frame.width
        let start = slider.coordinate(withNormalizedOffset: .init(dx: (16 + (120.0 / 900) * (width - 32)) / width, dy: 0.5))
        let end = slider.coordinate(withNormalizedOffset: .init(dx: (16 + 0.6 * (width - 32)) / width, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        wait(NSPredicate(format: "label == %@", "Updated on your Mac."),
             on: springboard.staticTexts["mediaControlsStatus"])
        wait(NSPredicate(format: "value != %@", "2:00 of 15:00"), on: slider)
        let returnedPosition = try XCTUnwrap(slider.value as? String)
        let positionText = try XCTUnwrap(returnedPosition.components(separatedBy: " of ").first)
        let timeParts = positionText.split(separator: ":").compactMap { Double($0) }
        XCTAssertEqual(timeParts.count, 2, returnedPosition)
        let shownSeconds = timeParts[0] * 60 + timeParts[1]
        XCTAssertGreaterThan(shownSeconds, 400, "Drag did not advance the video timeline")
        XCTAssertLessThan(shownSeconds, 700)
        capture("timeline-after-real-drag-and-host-ack")

        try command("Next track")
        XCTAssertFalse(slider.exists, "A retired selection must not retarget its slider")
        let second = springboard.buttons["Browser, Fixture A • Track 2, Playing"]
        XCTAssertTrue(second.waitForExistence(timeout: 3), springboard.debugDescription)
        second.tap()
        try command("Previous track")
        XCTAssertFalse(slider.exists, "A second track transition must retire selection again")
        XCTAssertTrue(springboard.buttons["Browser, Fixture A • Track 3, Playing"].waitForExistence(timeout: 3))
        capture("track-change-requires-explicit-reselection")

        XCUIDevice.shared.press(.home)
        app.activate()
        let evidence = app.staticTexts["notificationFixtureEvidence"]
        wait(NSPredicate(format: "label CONTAINS %@", "commands=3;"), on: evidence)
        let receiptText = try XCTUnwrap(evidence.label.components(separatedBy: ";received=").last)
        let receipts = receiptText.components(separatedBy: ",")
        XCTAssertEqual(receipts.count, 3, evidence.label)
        XCTAssertTrue(receipts[0].hasPrefix("A:seekToPosition@"), evidence.label)
        let hostPosition = try XCTUnwrap(Double(receipts[0].components(separatedBy: "@").last ?? ""))
        XCTAssertEqual(floor(hostPosition), shownSeconds, "The UI must show the actual fractional host seek readback")
        XCTAssertEqual(Array(receipts.dropFirst()), ["A:nextTrack", "A:previousTrack"])
        XCTAssertTrue(evidence.label.contains("A=playing:0;B=paused:240;"), evidence.label)
        app.buttons["Stop local peers"].tap()
        wait(NSPredicate(format: "label == %@", "Stopped"), on: app.staticTexts["notificationFixtureStatus"])
    }

    func testSameDeliveredNotificationReopensWithoutRescheduling() throws {
        try openFreshNotification()
        try exerciseControls()
        dismissWithHomeTwiceThenActivate()
        assertHostEvidence()
        var delivered = try inspectDeliveredNotification()
        var receipts = ["B:seekForward30", "B:play", "A:pause", "A:seekBackward30", "B:pause"]
        let cycles: [(command: String, receipt: String, beforePlaying: Bool, afterPlaying: Bool,
                      beforePosition: String, afterPosition: Int)] = [
            ("Forward 30 seconds", "B:seekForward30", false, false, "4:30 of 15:00", 300),
            ("Play", "B:play", false, true, "5:00 of 15:00", 300),
            ("Pause", "B:pause", true, false, "5:00 of 15:00", 300)
        ]
        for (index, cycle) in cycles.enumerated() {
            let number = index + 1
            openDeliveredNotificationUsingView(cycle: number)
            let browser = source("Browser", playing: false)
            let music = source("Music", playing: cycle.beforePlaying)
            XCTAssertTrue(browser.waitForExistence(timeout: 5), springboard.debugDescription)
            XCTAssertTrue(music.waitForExistence(timeout: 5), springboard.debugDescription)
            XCTAssertFalse(source("Browser", playing: true).exists, "Reopened Browser label is stale")
            XCTAssertFalse(source("Music", playing: !cycle.beforePlaying).exists, "Reopened Music label is stale")
            for label in ["Previous track", "Backward 30 seconds", "Forward 30 seconds", "Next track"] {
                XCTAssertTrue(springboard.buttons[label].exists, "Missing reopened control: \(label)")
            }
            XCTAssertNotEqual(springboard.buttons["Play"].exists, springboard.buttons["Pause"].exists,
                              "Exactly one playback toggle must be present before source selection")
            let slider = springboard.sliders["mediaPlaybackPosition"]
            XCTAssertTrue(slider.exists, "The reopened timeline must exist before source selection")
            capture("same-request-reopen-\(number)-before-selection")

            // Reopening need not choose a particular default source. Explicitly choose B,
            // then require its current timeline and command state before the first command.
            wait(NSPredicate(format: "hittable == true AND enabled == true"), on: music)
            music.tap()
            wait(NSPredicate(format: "value == %@ AND hittable == true AND enabled == true",
                             cycle.beforePosition), on: slider)
            let toggle = cycle.beforePlaying ? "Pause" : "Play"
            wait(NSPredicate(format: "hittable == true AND enabled == true"), on: springboard.buttons[toggle])
            XCTAssertFalse(springboard.buttons[cycle.beforePlaying ? "Play" : "Pause"].exists)
            try command(cycle.command)
            XCTAssertTrue(source("Music", playing: cycle.afterPlaying).waitForExistence(timeout: 5))
            capture("same-request-reopen-\(number)-after-first-command")

            dismissWithHomeTwiceThenActivate()
            receipts.append(cycle.receipt)
            let expected = "revision=\(6 + number);commands=\(5 + number);A=paused:90;"
                + "B=\(cycle.afterPlaying ? "playing" : "paused"):\(cycle.afterPosition);"
                + "received=\(receipts.joined(separator: ","))"
            wait(NSPredicate(format: "label == %@", expected), on: app.staticTexts["notificationFixtureEvidence"])
            delivered = try inspectDeliveredNotification(previous: delivered)
            capture("same-request-reopen-\(number)-exact-host-and-delivery-evidence")
        }
        app.buttons["Stop local peers"].tap()
        wait(NSPredicate(format: "label == %@", "Stopped"), on: app.staticTexts["notificationFixtureStatus"])
    }

    private func dismissWithHomeTwiceThenActivate() {
        // One Home can dismiss the expanded card without leaving Notification Center.
        // Confirm the fixture is actually reachable before tapping any fixture control.
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)
        app.activate()
        wait(NSPredicate(format: "label == %@", "Local WebRTC ready"),
             on: app.staticTexts["notificationFixtureStatus"])
        wait(NSPredicate(format: "hittable == true AND enabled == true"), on: app.buttons["Stop local peers"])
        wait(NSPredicate(format: "hittable == true AND enabled == true"),
             on: app.buttons["Inspect delivered notification"])
        XCTAssertFalse(springboard.staticTexts["Beluga · Mac playback"].exists)
    }

    private func inspectDeliveredNotification(previous: (counter: UInt64, fingerprint: String)? = nil) throws
        -> (counter: UInt64, fingerprint: String) {
        let identity = app.staticTexts["notificationDeliveredIdentity"]
        XCTAssertTrue(identity.exists, app.debugDescription)
        let oldSample = identity.label
        app.buttons["Inspect delivered notification"].tap()
        wait(NSPredicate(format: "label != %@", oldSample), on: identity)
        let parts = identity.label.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 2, identity.label)
        let counter = try XCTUnwrap(UInt64(parts[0]), identity.label)
        let fingerprint = String(parts[1])
        let fields = fingerprint.components(separatedBy: ";")
        XCTAssertEqual(fields.count, 5, identity.label)
        XCTAssertEqual(fields[0], "count=1")
        XCTAssertEqual(fields[1], "id=beluga.media.controls")
        XCTAssertTrue(fields[2].hasPrefix("date="), identity.label)
        _ = try XCTUnwrap(UInt64(fields[2].dropFirst("date=".count), radix: 16), identity.label)
        XCTAssertTrue(fields[3].hasPrefix("epoch="), identity.label)
        _ = try XCTUnwrap(UUID(uuidString: String(fields[3].dropFirst("epoch=".count))), identity.label)
        XCTAssertEqual(fields[4], "category=BelugaMediaControls")
        if let previous {
            XCTAssertGreaterThan(counter, previous.counter, "Delivery identity must come from a new explicit inspection")
            XCTAssertEqual(fingerprint, previous.fingerprint, "The delivered notification must not be replaced or rescheduled")
        }
        return (counter, fingerprint)
    }

    private func openDeliveredNotificationUsingView(cycle: Int) {
        let top = springboard.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.01))
        let bottom = springboard.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.8))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        let card = springboard.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "ListCell", "Beluga media controls")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), springboard.debugDescription)
        wait(NSPredicate(format: "hittable == true"), on: card)
        capture("same-request-reopen-\(cycle)-collapsed-card")
        let start = card.coordinate(withNormalizedOffset: .init(dx: 0.8, dy: 0.5))
        let end = card.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        let view = springboard.buttons["View"]
        XCTAssertTrue(view.waitForExistence(timeout: 5), springboard.debugDescription)
        XCTAssertTrue(springboard.buttons["Options"].exists)
        XCTAssertTrue(springboard.buttons["Clear"].exists)
        wait(NSPredicate(format: "hittable == true AND enabled == true"), on: view)
        capture("same-request-reopen-\(cycle)-system-view-action")
        view.tap()
        XCTAssertTrue(springboard.staticTexts["Beluga · Mac playback"].waitForExistence(timeout: 5),
                      springboard.debugDescription)
    }

    private func openFreshNotification(beforeExpansion: (() throws -> Void)? = nil) throws {
        app.launchArguments = ["--beluga-notification-loopback"]
        app.launch()
        wait(NSPredicate(format: "label == %@", "Local WebRTC ready"),
             on: app.staticTexts["notificationFixtureStatus"], timeout: 15)
        app.buttons["Show media notification"].tap()
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        let banner = springboard.staticTexts["Beluga media controls"]
        XCTAssertTrue(banner.waitForExistence(timeout: 8), springboard.debugDescription)
        capture("fresh-integrated-banner")
        if let beforeExpansion {
            try beforeExpansion()
            // Fixture actions can outlive the transient banner. Expand that same delivered
            // request through its system View action, without scheduling another notification.
            openDeliveredNotificationUsingView(cycle: 0)
        } else {
            banner.press(forDuration: 2)
        }
        XCTAssertTrue(source("Music", playing: false).waitForExistence(timeout: 5), springboard.debugDescription)
        XCTAssertTrue(source("Browser", playing: true).exists, springboard.debugDescription)
    }

    private func exerciseControls() throws {
        source("Music", playing: false).tap()
        try command("Forward 30 seconds")
        try command("Play")
        XCTAssertTrue(source("Music", playing: true).waitForExistence(timeout: 3), springboard.debugDescription)
        source("Browser", playing: true).tap()
        try command("Pause")
        XCTAssertTrue(source("Browser", playing: false).waitForExistence(timeout: 3), springboard.debugDescription)
        try command("Backward 30 seconds")
        source("Music", playing: true).tap()
        try command("Pause")
        XCTAssertTrue(source("Music", playing: false).waitForExistence(timeout: 3), springboard.debugDescription)
    }

    private func assertHostEvidence() {
        wait(NSPredicate(format: "label == %@",
            "revision=6;commands=5;A=paused:90;B=paused:270;received=B:seekForward30,B:play,A:pause,A:seekBackward30,B:pause"),
            on: app.staticTexts["notificationFixtureEvidence"])
        capture("host-native-data-channel-receipts")
    }

    private func source(_ name: String, playing: Bool) -> XCUIElement {
        springboard.buttons["\(name), Fixture \(name == "Browser" ? "A" : "B"), \(playing ? "Playing" : "Paused")"]
    }

    private func command(_ label: String) throws {
        let button = springboard.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 3), springboard.debugDescription)
        wait(NSPredicate(format: "hittable == true AND enabled == true"), on: button)
        button.tap()
        // Wait for an observed completion after one tap. Exact host receipts below reject a
        // missed, duplicate, wrong-source, optimistic or unacknowledged UI transition.
        let status = springboard.staticTexts["mediaControlsStatus"]
        wait(NSPredicate(format: "label BEGINSWITH %@", "Updated on your Mac."), on: status)
        if label != "Next track" && label != "Previous track" {
            wait(NSPredicate(format: "enabled == true"), on: springboard.buttons["Forward 30 seconds"])
        }
    }

    private func wait(_ predicate: NSPredicate, on element: XCUIElement, timeout: TimeInterval = 5) {
        let outcome = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
        XCTAssertEqual(outcome, .completed, "\(predicate)\n\(app.debugDescription)\n\(springboard.debugDescription)")
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let tree = XCTAttachment(string: app.debugDescription + "\n" + springboard.debugDescription)
        tree.name = name + "-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
