import XCTest

@MainActor final class RunningUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-ui-testing-running", mode,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        return app
    }

    private func openRunning(_ app: XCUIApplication) {
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["catalog.fitness"].waitForExistence(timeout: 5))
        app.buttons["catalog.fitness"].tap()
        XCTAssertTrue(app.buttons["card.punchcard.2"].waitForExistence(timeout: 5))
        app.buttons["card.punchcard.2"].tap()
        XCTAssertTrue(app.buttons["running.openSettings"].waitForExistence(timeout: 5))
    }

    private func start(_ app: XCUIApplication) {
        let button = app.buttons["running.start"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(button, predicate: "enabled == true"))
        button.tap()
        XCTAssertTrue(app.buttons["running.pause"].waitForExistence(timeout: 5))
    }

    private func waitFor(_ element: XCUIElement, predicate: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: 10) == .completed
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func leaveRunning(_ app: XCUIApplication) {
        app.buttons["running.close"].tap()
        if app.buttons["catalog.close"].waitForExistence(timeout: 2) { app.buttons["catalog.close"].tap() }
    }

    func testDeniedLocationExplainsPermissionAndBlocksStart() {
        let app = launch(mode: "denied")
        openRunning(app)
        XCTAssertTrue(app.staticTexts["running.denied"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["running.settings"].exists)
        XCTAssertFalse(app.buttons["running.start"].isEnabled)
        XCTAssertFalse(app.buttons["running.pause"].exists)
        capture("KeepUp-Running-Permission-Denied-English")
    }

    func testStartPauseResumeFinishCreatesOneRecord() {
        let app = launch(mode: "route")
        openRunning(app)
        capture("KeepUp-Outdoor-Prepare-English")
        start(app)
        app.buttons["running.openMap"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        capture("KeepUp-Outdoor-Map-English")
        app.buttons["running.closeMap"].tap()
        XCTAssertTrue(app.buttons["running.pause"].waitForExistence(timeout: 5))
        app.buttons["running.lock"].tap()
        XCTAssertTrue(app.buttons["running.unlock"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["running.pause"].exists)
        app.buttons["running.openMap"].tap()
        app.buttons["running.closeMap"].tap()
        XCTAssertTrue(app.buttons["running.unlock"].waitForExistence(timeout: 5))
        app.buttons["running.unlock"].swipeRight()
        XCTAssertTrue(app.buttons["running.pause"].waitForExistence(timeout: 5))
        // The explicit DEBUG route fixture supplies >100 m after the session starts.
        XCTAssertTrue(waitFor(app.staticTexts["running.distance"], predicate: "label != '0.00'"))
        capture("KeepUp-Outdoor-Active-English")
        app.buttons["running.pause"].tap()
        XCTAssertTrue(app.buttons["running.resume"].waitForExistence(timeout: 5))
        capture("KeepUp-Running-Paused-English")
        app.buttons["running.resume"].tap()
        XCTAssertTrue(app.buttons["running.pause"].waitForExistence(timeout: 5))
        app.buttons["running.pause"].tap()
        XCTAssertTrue(app.buttons["running.finish"].waitForExistence(timeout: 5))
        app.buttons["running.finish"].tap()
        XCTAssertTrue(app.buttons["running.confirmFinish"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["running.confirmFinish"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["running.result.distance"].waitForExistence(timeout: 10))
        capture("KeepUp-Running-Result-English")
        app.buttons["running.result.share"].tap()
        XCTAssertTrue(app.scrollViews["running.share.style.details"].waitForExistence(timeout: 5))
        app.buttons["running.share.close"].tap()
        app.buttons["running.page.0"].tap()
        app.buttons["running.result.share"].tap()
        XCTAssertTrue(app.scrollViews["running.share.style.overview"].waitForExistence(timeout: 5))
        app.buttons["running.share.close"].tap()
        leaveRunning(app)
        app.buttons["tab.history"].tap()
        let records = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry."))
        XCTAssertTrue(records.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(records.count, 1)
        records.firstMatch.tap()
        XCTAssertTrue(app.buttons["running.page.1"].waitForExistence(timeout: 5))
        app.buttons["running.page.1"].tap()
        XCTAssertTrue(app.staticTexts["running.result.distance"].waitForExistence(timeout: 5))
    }

    func testBackgroundKeepsSessionAndRelaunchRecoversPaused() {
        let app = launch(mode: "route")
        openRunning(app)
        start(app)
        XCTAssertTrue(waitFor(app.staticTexts["running.distance"], predicate: "label != '0.00'"))
        XCTAssertFalse(app.buttons["running.close"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["running.pause"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        openRunning(app)
        XCTAssertTrue(app.staticTexts["running.recovered"].waitForExistence(timeout: 5))
        capture("KeepUp-Running-Recovered-English")
        XCTAssertTrue(app.buttons["running.resume"].exists)
        XCTAssertFalse(app.buttons["running.pause"].exists)
        app.buttons["running.resume"].tap()
        XCTAssertTrue(app.buttons["running.pause"].waitForExistence(timeout: 5))
    }

    private func openCycling(_ app: XCUIApplication) {
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["catalog.featured.96"].waitForExistence(timeout: 5))
        app.buttons["catalog.featured.96"].tap()
        XCTAssertTrue(app.buttons["running.close"].waitForExistence(timeout: 5) || app.buttons["running.resume"].exists)
    }

    private func finishAndOpenHistory(_ app: XCUIApplication) {
        app.buttons["running.pause"].tap()
        XCTAssertTrue(app.buttons["running.finish"].waitForExistence(timeout: 5))
        app.buttons["running.finish"].tap()
        XCTAssertTrue(app.buttons["running.confirmFinish"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["running.confirmFinish"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["running.result.distance"].waitForExistence(timeout: 10))
        leaveRunning(app)
        app.buttons["tab.history"].tap()
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.running."))
        XCTAssertTrue(entries.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(entries.count, 1)
        entries.firstMatch.tap()
        XCTAssertTrue(app.buttons["running.page.1"].waitForExistence(timeout: 5))
        app.buttons["running.page.1"].tap()
        XCTAssertTrue(app.staticTexts["running.result.distance"].waitForExistence(timeout: 5))
    }

    func testIndoorUsesMotionAndSavesStepsWithoutMap() {
        let app = launch(mode: "motion")
        openRunning(app)
        app.buttons["running.mode.indoor"].tap()
        XCTAssertTrue(app.staticTexts["running.motionStatus"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["running.gpsWaiting"].exists)
        XCTAssertFalse(app.maps.firstMatch.exists)
        capture("KeepUp-Indoor-Prepare-English")
        start(app)
        XCTAssertTrue(app.staticTexts["running.steps"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(app.staticTexts["running.distance"], predicate: "label != '0.00'"))
        app.buttons["running.pause"].tap()
        XCTAssertTrue(app.buttons["running.resume"].waitForExistence(timeout: 5))
        capture("KeepUp-Indoor-Paused-English")
        // Active screens no longer offer Close. Reopen through another sport after process recovery.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        openCycling(app)
        XCTAssertTrue(app.staticTexts["running.steps"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["running.speed"].exists)
        app.buttons["running.resume"].tap()
        XCTAssertTrue(app.buttons["running.pause"].waitForExistence(timeout: 5))
        finishAndOpenHistory(app)
        XCTAssertEqual(app.staticTexts["running.result.kind"].label, "Indoor run")
        XCTAssertTrue(app.staticTexts["running.result.cadence"].exists)
        XCTAssertFalse(app.maps.firstMatch.exists)
        capture("KeepUp-Indoor-Result-English")
    }

    func testIndoorDeniedMotionBlocksStartWithoutRequestingGPS() {
        let app = launch(mode: "motion-denied")
        openRunning(app)
        app.buttons["running.mode.indoor"].tap()
        XCTAssertTrue(app.staticTexts["running.denied"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["running.settings"].exists)
        XCTAssertFalse(app.buttons["running.start"].isEnabled)
        XCTAssertFalse(app.maps.firstMatch.exists)
        capture("KeepUp-Indoor-Permission-Denied-English")
    }

    func testCyclingShowsSpeedAndSavesCyclingHistory() {
        let app = launch(mode: "route")
        openCycling(app)
        XCTAssertTrue(app.buttons["running.mode.cycling"].waitForExistence(timeout: 5))
        capture("KeepUp-Cycling-Prepare-English")
        XCTAssertTrue(app.buttons["running.mode.cycling"].isSelected)
        XCTAssertTrue(app.buttons["running.mode.indoor"].exists)
        start(app)
        XCTAssertTrue(app.staticTexts["running.speed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["running.pace"].exists)
        app.buttons["running.openMap"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        capture("KeepUp-Cycling-Map-English")
        app.buttons["running.closeMap"].tap()
        XCTAssertTrue(app.staticTexts["running.speed"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(app.staticTexts["running.distance"], predicate: "label != '0.00'"))
        capture("KeepUp-Cycling-Active-English")
        finishAndOpenHistory(app)
        XCTAssertEqual(app.staticTexts["running.result.kind"].label, "Cycling")
        XCTAssertFalse(app.staticTexts["running.result.steps"].exists)
        capture("KeepUp-Cycling-Result-English")
    }

}
