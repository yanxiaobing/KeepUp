import XCTest

@MainActor final class StepsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(mode: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-ui-testing-steps", mode,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
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

    func testIntradayChartAndMissingIntervals() {
        let app = launch(mode: "partial")
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.intradayPartial"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["steps.activeMinutes"].label, "—")
        XCTAssertTrue(app.buttons["steps.retryIntraday"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "KeepUp-Steps-Intraday-Partial"; shot.lifetime = .keepAlways; add(shot)
    }

    func testZeroIntradayHasKnownZeroActiveTime() {
        let app = launch(mode: "zero", language: "zh-Hans")
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.activeMinutes"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["steps.activeMinutes"].label, "0 分钟")
        XCTAssertEqual(app.staticTexts["steps.energy"].label, "0 大卡")
        XCTAssertFalse(app.staticTexts["steps.intradayPartial"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "KeepUp-Steps-Intraday-Zero-Chinese"; shot.lifetime = .keepAlways; add(shot)
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
        XCTAssertEqual(app.staticTexts["energy.dailyTotal"].label, "Est. 195 kcal burned today")
        app.buttons["BackButton"].tap()
        XCTAssertTrue(records.firstMatch.waitForExistence(timeout: 5))
        records.firstMatch.tap()
        XCTAssertTrue(app.buttons["steps.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "6,500")
        XCTAssertEqual(app.staticTexts["steps.energy"].label, "195 kcal")
        app.buttons["steps.close"].tap()

        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        if let index = app.launchArguments.firstIndex(of: "-ui-testing-steps") { app.launchArguments[index + 1] = "denied" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.denied"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "6,500")
        XCTAssertEqual(app.staticTexts["steps.energy"].label, "195 kcal")
        XCTAssertTrue(app.buttons["steps.settings"].exists)
        XCTAssertTrue(app.buttons["steps.share"].isEnabled)
        app.buttons["steps.share"].tap()
        XCTAssertTrue(app.buttons["entry.saveImage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entry.shareSystem"].exists)
    }

    func testUnsupportedDoesNotShowInventedZero() {
        let app = launch(mode: "unsupported")
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.unsupported"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "—")
        XCTAssertEqual(app.staticTexts["steps.energy"].label, "—")
        XCTAssertFalse(app.buttons["steps.share"].isEnabled)
    }

    func testPendingStepCardOpensMeasurementWithoutManualCheckIn() {
        let app = launch(mode: "zero")
        app.buttons["tab.profile"].tap()
        app.buttons["profile.stepTarget"].tap()
        XCTAssertTrue(app.buttons["stepsTarget.save"].waitForExistence(timeout: 5))
        app.buttons["stepsTarget.save"].tap()
        XCTAssertTrue(app.buttons["stepsTarget.save"].waitForNonExistence(timeout: 5))
        // Profile is pushed from the calendar in the current navigation structure.
        app.buttons["BackButton"].tap()
        let pending = app.buttons["target.pending.punchcard.1"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        pending.tap()
        XCTAssertTrue(app.buttons["steps.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "0")
        XCTAssertFalse(app.staticTexts["steps.goalReached"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "KeepUp-Steps-Pending-English"; shot.lifetime = .keepAlways; add(shot)
    }

    func testEnglishDetailsAndCardSharing() { verifySharing(language: "en") }
    func testChineseDetailsAndCardSharing() { verifySharing(language: "zh-Hans") }

    private func verifySharing(language: String) {
        let app = launch(mode: "ready", language: language)
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.count"].waitForExistence(timeout: 5))
        let share = app.buttons["steps.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: share)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        share.tap()
        XCTAssertTrue(app.buttons["entry.saveImage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entry.shareSystem"].exists)
        app.buttons["entry.shareClose"].tap()
        let picker = app.segmentedControls["steps.view"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons[language == "en" ? "Card" : "卡片"].tap()
        XCTAssertTrue(app.staticTexts["steps.poster.count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.poster.count"].label, "6,500")
        XCTAssertEqual(app.staticTexts["steps.energy"].label, language == "en" ? "195 kcal" : "195 大卡")
        let cardShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        cardShot.name = "Steps-Card-\(language)"; cardShot.lifetime = .keepAlways; add(cardShot)
        share.tap()
        XCTAssertTrue(app.buttons["entry.saveImage"].waitForExistence(timeout: 5))
        let shareShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shareShot.name = "Steps-Share-\(language)"; shareShot.lifetime = .keepAlways; add(shareShot)
        app.buttons["entry.shareClose"].tap()
        picker.buttons[language == "en" ? "Details" : "详情"].tap()
        XCTAssertTrue(app.staticTexts["steps.count"].waitForExistence(timeout: 5))
    }

}
