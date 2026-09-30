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

    func testSameDeliveredNotificationReopensWithoutRescheduling() throws {
        try openFreshNotification()
        try exerciseControls()
        XCUIDevice.shared.press(.home)
        app.activate()
        assertHostEvidence()
        let top = springboard.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.01))
        let bottom = springboard.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.8))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        let card = springboard.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "ListCell", "Beluga media controls")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), springboard.debugDescription)
        wait(NSPredicate(format: "hittable == true"), on: card)
        capture("same-request-before-reopen")
        card.press(forDuration: 2)
        XCTAssertTrue(source("Music", playing: false).waitForExistence(timeout: 5), springboard.debugDescription)
        capture("same-request-reopened")
        source("Music", playing: false).tap()
        try command("Forward 30 seconds")
        XCUIDevice.shared.press(.home)
        app.activate()
        wait(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                         "commands=6;", "B=paused:300;"), on: app.staticTexts["notificationFixtureEvidence"])
        app.buttons["Stop local peers"].tap()
    }

    private func openFreshNotification() throws {
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
        banner.press(forDuration: 2)
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
        wait(NSPredicate(format: "label == %@", "Updated on your Mac."), on: status)
        wait(NSPredicate(format: "enabled == true"), on: springboard.buttons["Forward 30 seconds"])
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
