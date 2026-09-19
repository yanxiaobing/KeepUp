import XCTest

@MainActor
final class KeepUpUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func app(language: String = "en", reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if reset { app.launchArguments.append("-reset-test-data") }
        return app
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openCatalog(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["card.preset.exercise"].waitForExistence(timeout: 5))
    }

    func testEnglishSaveRelaunchAndDelete() throws {
        let app = app()
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        attach("PunchCard-Calendar-English")
        openCatalog(app)
        attach("PunchCard-Catalog-English")
        app.buttons["card.preset.exercise"].tap()
        XCTAssertTrue(app.buttons["keypad.3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["entry.save"].isEnabled)
        app.buttons["keypad.3"].tap()
        app.buttons["keypad.0"].tap()
        attach("PunchCard-Keypad-English")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 5))
        attach("PunchCard-Calendar-Record")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 15))
        app.buttons["tab.history"].tap()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        attach("PunchCard-Timeline-English")
        record.press(forDuration: 1.0)
        app.buttons["entry.viewCard"].tap()
        app.buttons["entry.actions"].tap()
        XCTAssertTrue(app.buttons["entry.delete"].waitForExistence(timeout: 5))
        app.buttons["entry.delete"].tap()
        let confirmDelete = app.sheets.buttons.matching(identifier: "entry.confirmDelete").firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(app.otherElements["history.empty"].waitForExistence(timeout: 5) || app.staticTexts["No records yet. Time to check in!"].exists)
        attach("PunchCard-Timeline-Empty")
    }

    func testChineseAndInAppLanguageChange() throws {
        let app = app(language: "zh-Hans")
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        attach("PunchCard-Calendar-Chinese")
        openCatalog(app)
        XCTAssertTrue(app.buttons["catalog.health"].exists)
        XCTAssertTrue(app.buttons["catalog.featured.50"].label.contains("体重"))
        XCTAssertTrue(app.buttons["catalog.featured.2"].label.contains("跑步"))
        XCTAssertTrue(app.buttons["catalog.featured.96"].label.contains("骑行"))
        attach("PunchCard-Catalog-Chinese")
        app.buttons["card.preset.exercise"].tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForExistence(timeout: 5))
        attach("PunchCard-Keypad-Chinese")
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForNonExistence(timeout: 5))
        app.buttons["catalog.close"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
        app.buttons["tab.profile"].tap()
        attach("PunchCard-Profile-Chinese")
        app.buttons["profile.settings"].tap()
        app.buttons["settings.language"].tap()
        app.buttons["language.en"].tap()
        XCTAssertTrue(app.staticTexts["Premium"].waitForExistence(timeout: 5))
        attach("PunchCard-Profile-English")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 20))
        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.staticTexts["Premium"].waitForExistence(timeout: 5))
    }

    func testLargeTextAndDarkAppearance() throws {
        let app = app()
        app.launchArguments += ["-ui-testing-large-type", "-ui-testing-dark"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        attach("PunchCard-Calendar-LargeText-Dark")
        openCatalog(app)
        app.buttons["card.preset.exercise"].tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForExistence(timeout: 5))
        attach("PunchCard-Keypad-LargeText-Dark")
        app.buttons["entry.cancel"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)).tap()
    }

    func testHomeCardAreaChangesDayAndReturnsToToday() throws {
        let app = app()
        app.launch()
        let records = app.otherElements["calendar.records"]
        XCTAssertTrue(records.waitForExistence(timeout: 20))
        let today = Date()
        let calendar = Calendar(identifier: .gregorian)
        func dayID(_ offset: Int) -> String {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "day.%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
        records.swipeLeft()
        XCTAssertTrue(app.buttons["calendar.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[dayID(1)].isSelected)
        attach("KeepUp-Home-Swipe-Future")
        app.buttons["calendar.today"].tap()
        XCTAssertTrue(app.buttons["calendar.today"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[dayID(0)].isSelected)
        records.swipeRight()
        XCTAssertTrue(app.buttons["calendar.today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[dayID(-1)].isSelected)
        records.swipeRight()
        XCTAssertTrue(app.buttons["calendar.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[dayID(-2)].isSelected)
        attach("KeepUp-Home-Swipe-Past")
        app.buttons["calendar.add"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForExistence(timeout: 5))
        app.buttons["catalog.close"].tap()
        XCTAssertTrue(records.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[dayID(-2)].isSelected)
    }

    func testCalendarScopeAndBackfill() throws {
        let app = app()
        app.launch()
        XCTAssertTrue(app.buttons["calendar.scope"].waitForExistence(timeout: 20))
        let weekY = app.buttons["calendar.scope"].frame.midY
        attach("PunchCard-Calendar-Week")
        app.buttons["calendar.scope"].tap()
        let monthLayout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { app.buttons["calendar.scope"].frame.midY > weekY + 50 }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [monthLayout], timeout: 5), .completed)
        attach("PunchCard-Calendar-Month")
        let previous = app.staticTexts["calendar.month"].label
        app.otherElements["calendar.grid"].swipeRight()
        let monthChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", previous), object: app.staticTexts["calendar.month"])
        XCTAssertEqual(XCTWaiter.wait(for: [monthChanged], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["calendar.add"].waitForExistence(timeout: 5))
        app.buttons["calendar.add"].tap()
        app.buttons["catalog.health"].tap()
        app.buttons["card.preset.fruit"].tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForExistence(timeout: 5))
        attach("PunchCard-Unitless-Confirmation")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendar.add"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["calendar.month"].label, previous)
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.")).firstMatch
        XCTAssertTrue(record.exists)
        attach("PunchCard-Calendar-Backfill")
    }
}
