import XCTest

@MainActor final class StepsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(mode: String, language: String = "en", themeID: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-ui-testing-steps", mode,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if let themeID { app.launchArguments += ["-themeID", String(themeID)] }
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
        if app.buttons["stepsTarget.save"].waitForExistence(timeout: 2) {
            app.buttons["stepsTarget.save"].tap()
            XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 5))
            app.buttons["tab.calendar"].tap()
            app.buttons["catalog.life"].tap()
            app.buttons["card.punchcard.1"].tap()
        }
        XCTAssertTrue(app.buttons["steps.close"].waitForExistence(timeout: 5))
    }

    func testCatalogAddsStepCardAndCancelDoesNotAdd() {
        let app = launch(mode: "zero")
        app.buttons["tab.calendar"].tap()
        let card = app.buttons["card.punchcard.1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["stepsTarget.save"].waitForExistence(timeout: 5))
        app.buttons["stepsTarget.close"].tap()
        app.buttons["catalog.close"].tap()
        XCTAssertFalse(app.buttons["target.pending.punchcard.1"].exists)
        app.buttons["tab.calendar"].tap()
        app.buttons["card.punchcard.1"].tap()
        app.buttons["stepsTarget.save"].tap()
        let pending = app.buttons["target.pending.punchcard.1"]
        XCTAssertTrue(pending.waitForExistence(timeout: 8))
        let homeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        homeShot.name = "Steps-Added-Calendar"; homeShot.lifetime = .keepAlways; add(homeShot)
        pending.tap()
        XCTAssertTrue(app.buttons["steps.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "0")
        app.buttons["steps.close"].tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(pending.waitForExistence(timeout: 20))
        pending.press(forDuration: 0.7)
        app.buttons["calendar.menu.delete"].tap()
        app.buttons["calendar.confirmDelete"].tap()
        XCTAssertTrue(pending.waitForNonExistence(timeout: 5))
        let nextPage = app.buttons["calendar.nextMonth"].exists ? app.buttons["calendar.nextMonth"] : app.buttons["calendar.nextWeek"]
        nextPage.tap()
        app.buttons["tab.calendar"].tap()
        app.buttons["catalog.life"].tap()
        app.buttons["card.punchcard.1"].tap()
        XCTAssertTrue(app.buttons["stepsTarget.save"].waitForExistence(timeout: 5))
        app.buttons["stepsTarget.save"].tap()
        XCTAssertTrue(pending.waitForExistence(timeout: 8))
    }

    func testRecentHistoryOpensSelectedDay() {
        let app = launch(mode: "ready")
        openSteps(app)
        app.buttons["steps.actions"].tap()
        app.buttons["steps.history"].tap()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: yesterday)
        let row = app.buttons["steps.history.\(day)"]
        for _ in 0..<6 {
            if row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.staticTexts[day].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["steps.count"].waitForExistence(timeout: 5))
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
        XCTAssertEqual(app.staticTexts["steps.activeMinutes"].label, "0h 0m")
        XCTAssertEqual(app.staticTexts["steps.energy"].label, "0")
        XCTAssertFalse(app.staticTexts["steps.intradayPartial"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "KeepUp-Steps-Intraday-Zero-Chinese"; shot.lifetime = .keepAlways; add(shot)
    }

    func testGoalCreatesOneDailyRecordAndSurvivesDeniedAccess() {
        let app = launch(mode: "ready")
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.count"].waitForExistence(timeout: 5))
        app.buttons["steps.actions"].tap()
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
        XCTAssertEqual(app.staticTexts["energy.dailyTotal"].label, "195 kcal burned")
        app.buttons["BackButton"].tap()
        XCTAssertTrue(records.firstMatch.waitForExistence(timeout: 5))
        records.firstMatch.tap()
        XCTAssertTrue(app.buttons["steps.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "6,500")
        XCTAssertEqual(app.staticTexts["steps.energy"].label, "195")
        app.buttons["steps.close"].tap()

        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        if let index = app.launchArguments.firstIndex(of: "-ui-testing-steps") { app.launchArguments[index + 1] = "denied" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        openSteps(app)
        XCTAssertTrue(app.staticTexts["steps.denied"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.count"].label, "6,500")
        XCTAssertEqual(app.staticTexts["steps.energy"].label, "195")
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

    func testLhasaDetailsStayFixedAfterVerticalSwipes() {
        let app = launch(mode: "ready", language: "zh-Hans", themeID: 9)
        openSteps(app)
        let count = app.staticTexts["steps.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let originalFrame = count.frame
        app.swipeUp()
        app.swipeDown()
        XCTAssertEqual(count.frame.minY, originalFrame.minY, accuracy: 1)
        XCTAssertGreaterThan(count.frame.minY, app.navigationBars.firstMatch.frame.maxY + 24)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Steps-Lhasa-Fixed-Details"; shot.lifetime = .keepAlways; add(shot)
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
        let detailsShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detailsShot.name = "Steps-Original-Details-\(language)"; detailsShot.lifetime = .keepAlways; add(detailsShot)
        XCTAssertFalse(app.segmentedControls["steps.view"].exists)
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["steps.poster.count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["steps.poster.count"].label, language == "en" ? "Walked 6,500 steps" : "走路6,500步")
        let cardShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        cardShot.name = "Steps-Card-\(language)"; cardShot.lifetime = .keepAlways; add(cardShot)
        share.tap()
        XCTAssertTrue(app.buttons["entry.saveImage"].waitForExistence(timeout: 5))
        let shareShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shareShot.name = "Steps-Share-\(language)"; shareShot.lifetime = .keepAlways; add(shareShot)
        app.buttons["entry.shareClose"].tap()
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["steps.count"].waitForExistence(timeout: 5))
    }

}
