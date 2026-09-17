import XCTest

@MainActor
final class ScheduleWakeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(_ language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20)); return app
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func tomorrow(_ app: XCUIApplication) {
        let date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        let day = app.buttons["day." + formatter.string(from: date)]
        if !day.exists { app.otherElements["calendar.grid"].swipeLeft() }
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
    }
    private func plannedFlow(_ language: String) {
        let app = launch(language); tomorrow(app)
        app.buttons["calendar.add"].tap()
        XCTAssertTrue(app.buttons["card.preset.exercise"].waitForExistence(timeout: 5)); app.buttons["card.preset.exercise"].tap()
        XCTAssertTrue(app.textViews["schedule.note"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["schedule.save"].isEnabled)
        capture("KeepUp-Schedule-Empty-" + language)
        app.textViews["schedule.note"].tap(); app.textViews["schedule.note"].typeText(language == "en" ? "Bring water" : "记得带水")
        app.buttons["schedule.save"].tap()
        XCTAssertTrue(app.buttons["schedule.card.preset.exercise"].waitForExistence(timeout: 5))
        capture("KeepUp-Schedule-Calendar-" + language)
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20)); tomorrow(app)
        app.buttons["schedule.card.preset.exercise"].tap()
        XCTAssertTrue(app.textViews["schedule.note"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["schedule.note"].value as? String, language == "en" ? "Bring water" : "记得带水")
        capture("KeepUp-Schedule-Edit-" + language)
        app.buttons["schedule.delete"].tap(); app.buttons.matching(identifier: "schedule.confirmDelete").firstMatch.tap()
        XCTAssertTrue(app.buttons["schedule.card.preset.exercise"].waitForNonExistence(timeout: 5))
    }
    func testFutureCardEnglishSaveReopenDelete() { plannedFlow("en") }
    func testFutureCardChineseSaveReopenDelete() { plannedFlow("zh-Hans") }
    private func wakeFlow(_ language: String) {
        let app = launch(language); app.buttons["tab.calendar"].tap()
        app.buttons[language == "en" ? "Add wake-up card" : "添加起床卡"].tap()
        XCTAssertTrue(app.buttons["wake.activate"].waitForExistence(timeout: 5)); capture("KeepUp-Wake-Intro-" + language)
        app.buttons["wake.activate"].tap()
        XCTAssertTrue(app.buttons["target.pending.punchcard.63"].waitForExistence(timeout: 5)); app.buttons["target.pending.punchcard.63"].tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForExistence(timeout: 5)); capture("KeepUp-Wake-Time-" + language)
        app.buttons["entry.save"].tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 1) { app.alerts.buttons.matching(identifier: "wake.confirm").firstMatch.tap() }
        XCTAssertTrue(app.buttons["entry.save"].waitForNonExistence(timeout: 5))
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); capture("KeepUp-Wake-Calendar-" + language)
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(record.waitForExistence(timeout: 20)); record.tap()
        XCTAssertTrue(app.buttons["entry.share"].waitForExistence(timeout: 5)); capture("KeepUp-Wake-Detail-" + language)
        app.buttons["entry.share"].tap(); XCTAssertTrue(app.buttons["entry.shareSystem"].waitForExistence(timeout: 5)); capture("KeepUp-Wake-Share-" + language)
    }
    func testWakeUpReminderAndScheduleDiscard() {
        let app = launch("en"); app.buttons["tab.calendar"].tap(); app.buttons["Add wake-up card"].tap()
        XCTAssertTrue(app.buttons["wake.setAlarm"].waitForExistence(timeout: 5)); app.buttons["wake.setAlarm"].tap()
        XCTAssertTrue(app.buttons["reminder.save"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["reminder.time"].label, "08:00")
        app.switches["reminder.enabled"].tap(); app.buttons["reminder.save"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons.matching(NSPredicate(format: "label == 'Allow' OR label == '允许'")).firstMatch
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        XCTAssertTrue(app.buttons["reminder.save"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["target.pending.punchcard.63"].waitForExistence(timeout: 5))
        tomorrow(app); app.buttons["calendar.add"].tap(); app.buttons["card.preset.exercise"].tap()
        XCTAssertTrue(app.textViews["schedule.note"].waitForExistence(timeout: 5))
        app.textViews["schedule.note"].tap(); app.textViews["schedule.note"].typeText("Unsaved")
        app.buttons["schedule.close"].tap(); app.buttons.matching(identifier: "schedule.discard").firstMatch.tap()
        XCTAssertTrue(app.textViews["schedule.note"].waitForNonExistence(timeout: 5)); app.buttons["catalog.close"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5)); XCTAssertFalse(app.buttons["schedule.card.preset.exercise"].exists)
    }
    func testWakeUpEnglishFlow() { wakeFlow("en") }
    func testWakeUpChineseFlow() { wakeFlow("zh-Hans") }
}
