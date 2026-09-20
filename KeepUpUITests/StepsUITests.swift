import XCTest

@MainActor final class StepsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-ui-testing-steps", mode,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        return app
    }

    private func openSteps(_ app: XCUIApplication) {
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["catalog.life"].waitForExistence(timeout: 5))
        app.buttons["catalog.life"].tap()
        XCTAssertTrue(app.buttons["card.punchcard.1"].waitForExistence(timeout: 5))
        app.buttons["card.punchcard.1"].tap()
        XCTAssertTrue(app.buttons["steps.close"].waitForExistence(timeout: 5))
    }

    func testGoalCreatesOneDailyRecordAndSurvivesDeniedAccess() {
        let app = launch(mode: "ready")
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.count"].waitForExistence(timeout: 5))
        app.buttons["steps.target"].tap()
        XCTAssertTrue(app.buttons["stepsTarget.save"].waitForExistence(timeout: 5))
        app.buttons["stepsTarget.save"].tap()
        XCTAssertTrue(app.staticTexts["steps.goalReached"].waitForExistence(timeout: 8))
        app.buttons["steps.close"].tap()
        if app.buttons["catalog.close"].waitForExistence(timeout: 2) { app.buttons["catalog.close"].tap() }
        app.buttons["tab.history"].tap()
        let records = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.steps."))
        XCTAssertTrue(records.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(records.count, 1)

        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        if let index = app.launchArguments.firstIndex(of: "-ui-testing-steps") { app.launchArguments[index + 1] = "denied" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.denied"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "6,500")
        XCTAssertTrue(app.buttons["steps.settings"].exists)
    }

    func testUnsupportedDoesNotShowInventedZero() {
        let app = launch(mode: "unsupported")
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.unsupported"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "—")
    }

    func testPendingStepCardOpensMeasurementWithoutManualCheckIn() {
        let app = launch(mode: "zero")
        app.buttons["tab.profile"].tap()
        app.buttons["profile.stepTarget"].tap()
        XCTAssertTrue(app.buttons["stepsTarget.save"].waitForExistence(timeout: 5))
        app.buttons["stepsTarget.save"].tap()
        XCTAssertTrue(app.buttons["stepsTarget.save"].waitForNonExistence(timeout: 5))
        // From the profile tab, the middle button returns to the calendar.
        app.buttons["tab.calendar"].tap()
        let pending = app.buttons["target.pending.punchcard.1"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        pending.tap()
        XCTAssertTrue(app.buttons["steps.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "0")
        XCTAssertFalse(app.staticTexts["steps.goalReached"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "KeepUp-Steps-Pending-English"; shot.lifetime = .keepAlways; add(shot)
    }

}
