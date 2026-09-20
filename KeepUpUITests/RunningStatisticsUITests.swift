import XCTest

@MainActor final class RunningStatisticsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data",
                               "-ui-testing-running-details", "outdoor", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 20))
        return app
    }

    private func openStatistics(in app: XCUIApplication) {
        app.buttons["tab.profile"].tap()
        let entry = app.buttons["runningStats.title"]
        if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.buttons["running.stats.mode"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStatisticsFilterByModeAndMonth() {
        let app = launch()
        openStatistics(in: app)
        XCTAssertEqual(app.staticTexts["running.stats.count"].label, "1")
        XCTAssertEqual(app.staticTexts["running.stats.days"].label, "1")
        XCTAssertEqual(app.staticTexts["running.stats.distance"].label, "4.25")
        XCTAssertNotEqual(app.staticTexts["running.stats.duration"].label, "—")
        XCTAssertNotEqual(app.staticTexts["running.stats.energy"].label, "—")
        XCTAssertFalse(app.staticTexts["running.stats.pace"].exists)
        capture("KeepUp-Running-Statistics-All-English")
        app.buttons["running.stats.mode"].tap()
        app.buttons["running.stats.mode.cycling"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["running.stats.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["running.stats.count"].exists)
        app.buttons["running.stats.mode"].tap()
        app.buttons["running.stats.mode.outdoor"].tap()
        XCTAssertTrue(app.staticTexts["running.stats.pace"].waitForExistence(timeout: 5))
        app.buttons["running.stats.month"].tap()
        let month = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "running.stats.month.", "running.stats.month.all")).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        month.tap()
        XCTAssertEqual(app.staticTexts["running.stats.distance"].label, "4.25")
        capture("KeepUp-Running-Statistics-Month-English")
        app.buttons["running.stats.month"].tap()
        app.buttons["running.stats.month.all"].tap()
        XCTAssertEqual(app.staticTexts["running.stats.count"].label, "1")
    }

    func testDeletingRecordRefreshesStatisticsAndSurvivesRelaunch() {
        let app = launch()
        openStatistics(in: app)
        let record = app.buttons["running.stats.entry.running.ui-details-outdoor"]
        for _ in 0..<4 {
            if record.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(record.isHittable)
        record.tap()
        XCTAssertTrue(app.buttons["running.detail.actions"].waitForExistence(timeout: 10))
        app.buttons["running.detail.actions"].tap()
        app.buttons["running.detail.delete"].tap()
        app.buttons["running.detail.confirmDelete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["running.stats.close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["running.stats.empty"].exists)
        XCTAssertFalse(app.staticTexts["running.stats.count"].exists)
        capture("KeepUp-Running-Statistics-Empty-English")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 20))
        openStatistics(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["running.stats.empty"].exists)
    }
}
