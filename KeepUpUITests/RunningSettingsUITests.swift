import XCTest

@MainActor final class RunningSettingsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(mode: String = "route") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-ui-testing-running", mode,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        return app
    }

    private func openRunning(_ app: XCUIApplication) {
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["catalog.featured.2"].waitForExistence(timeout: 5))
        app.buttons["catalog.featured.2"].tap()
        XCTAssertTrue(app.buttons["running.close"].waitForExistence(timeout: 5))
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["running.openSettings"].tap()
        XCTAssertTrue(app.switches["runningSettings.prepare"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func set(_ id: String, to value: Bool, in app: XCUIApplication) {
        let toggle = app.switches[id]
        reveal(toggle, in: app)
        if (toggle.value as? String) != (value ? "1" : "0") {
            // SwiftUI List exposes the complete label row as the switch's AX frame.
            // Target the trailing switch control instead of the center of that row.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        if (toggle.value as? String) != (value ? "1" : "0") {
            let diagnostic = XCTAttachment(string: toggle.debugDescription)
            diagnostic.name = "Switch-frame-\(id)"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            capture("Switch-failure-\(id)")
        }
        XCTAssertEqual(toggle.value as? String, value ? "1" : "0")
    }

    private func leave(_ app: XCUIApplication) {
        app.buttons["running.close"].tap()
        if app.buttons["catalog.close"].waitForExistence(timeout: 2) { app.buttons["catalog.close"].tap() }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSettingsPersistAndIndoorHidesMapConfiguration() {
        let app = launch()
        openRunning(app)
        openSettings(app)
        app.buttons["runningSettings.kind.indoor"].tap()
        set("runningSettings.countdown", to: true, in: app)
        set("runningSettings.voice", to: false, in: app)
        set("runningSettings.autoPause", to: true, in: app)
        set("runningSettings.autoLock", to: true, in: app)
        set("runningSettings.keepScreenOn", to: true, in: app)
        capture("KeepUp-Running-Settings-English")
        reveal(app.buttons["runningSettings.map"], in: app)
        app.buttons["runningSettings.map"].tap()
        XCTAssertTrue(app.buttons["runningSettings.map.satellite"].waitForExistence(timeout: 5))
        app.buttons["runningSettings.map.satellite"].tap()
        XCTAssertTrue(app.buttons["runningSettings.map.satellite"].isSelected)
        capture("KeepUp-Running-Satellite-Choice-English")
        app.navigationBars["Map display"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["runningSettings.close"].waitForExistence(timeout: 5))
        app.buttons["runningSettings.close"].tap()
        leave(app)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        if let index = app.launchArguments.firstIndex(of: "-ui-testing-running") { app.launchArguments[index + 1] = "motion" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        openRunning(app)
        XCTAssertTrue(app.buttons["running.mode.indoor"].isSelected)
        XCTAssertFalse(app.maps.firstMatch.exists)
        openSettings(app)
        XCTAssertEqual(app.switches["runningSettings.countdown"].value as? String, "1")
        set("runningSettings.keepScreenOn", to: true, in: app)
        XCTAssertFalse(app.buttons["runningSettings.map"].exists)
    }

    func testCountdownCancelsAndAutoLockRequiresIntentionalUnlock() {
        let app = launch()
        openRunning(app)
        openSettings(app)
        set("runningSettings.countdown", to: true, in: app)
        set("runningSettings.autoLock", to: true, in: app)
        app.buttons["runningSettings.close"].tap()
        app.buttons["running.start"].tap()
        XCTAssertTrue(app.buttons["running.cancelCountdown"].waitForExistence(timeout: 2))
        app.buttons["running.cancelCountdown"].tap()
        XCTAssertTrue(app.buttons["running.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["running.pause"].exists)
        app.buttons["running.start"].tap()
        XCTAssertTrue(app.buttons["running.unlock"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["running.pause"].exists)
        XCTAssertFalse(app.buttons["running.finish"].exists)
        capture("KeepUp-Running-Locked-English")
        app.buttons["running.unlock"].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["running.pause"].waitForExistence(timeout: 5))
        app.buttons["running.pause"].tap()
        XCTAssertTrue(app.buttons["running.resume"].waitForExistence(timeout: 5))
        app.buttons["running.resume"].tap()
        XCTAssertTrue(app.buttons["running.unlock"].waitForExistence(timeout: 5))
        // Settings remain reachable while the activity controls are protected.
        openSettings(app)
        set("runningSettings.autoLock", to: false, in: app)
        app.buttons["runningSettings.close"].tap()
        XCTAssertTrue(app.buttons["running.pause"].waitForExistence(timeout: 5))
    }

    func testSkipPreparationUsesDefaultAndCancelledCountdownDoesNotRestart() {
        let app = launch(mode: "motion")
        openRunning(app)
        openSettings(app)
        set("runningSettings.prepare", to: false, in: app)
        app.buttons["runningSettings.kind.indoor"].tap()
        set("runningSettings.countdown", to: true, in: app)
        app.buttons["runningSettings.close"].tap()
        leave(app)
        openRunning(app)
        XCTAssertTrue(app.buttons["running.cancelCountdown"].waitForExistence(timeout: 2))
        app.buttons["running.cancelCountdown"].tap()
        XCTAssertTrue(app.buttons["running.mode.indoor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["running.mode.indoor"].isSelected)
        XCTAssertFalse(app.buttons["running.pause"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["running.start"].exists)
        leave(app)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        if let index = app.launchArguments.firstIndex(of: "-ui-testing-running") { app.launchArguments[index + 1] = "motion-denied" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        openRunning(app)
        XCTAssertTrue(app.staticTexts["running.denied"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["running.start"].isEnabled)
        XCTAssertFalse(app.buttons["running.cancelCountdown"].exists)
    }
}
