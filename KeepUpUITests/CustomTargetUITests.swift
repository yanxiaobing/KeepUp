import XCTest

@MainActor
final class CustomTargetUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(_ language: String = "en", reminderRoute: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if reminderRoute { app.launchArguments.append("-ui-testing-reminder-route") }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        return app
    }
    private func screenshot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func openCustom(_ app: XCUIApplication) {
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["catalog.create"].waitForExistence(timeout: 5))
        app.buttons["catalog.create"].tap()
        XCTAssertTrue(app.textFields["custom.name"].waitForExistence(timeout: 5))
    }
    private func customCard(_ app: XCUIApplication) -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card.custom.")).firstMatch }
    private func record(_ app: XCUIApplication) -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.")).firstMatch }

    func testCreateNumericCustomCardAndRelaunch() {
        let app = launch(); openCustom(app)
        app.textFields["custom.name"].tap(); app.textFields["custom.name"].typeText("Reading\n")
        screenshot("KeepUp-Custom-Name-English")
        app.buttons["custom.next"].tap()
        XCTAssertTrue(app.buttons["custom.finish"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["custom.finish"].isEnabled)
        app.staticTexts["custom.unit.minutes"].tap()
        screenshot("KeepUp-Custom-Units-English")
        app.buttons["custom.finish"].tap(); app.buttons.matching(identifier: "custom.confirm").firstMatch.tap()
        XCTAssertTrue(customCard(app).waitForExistence(timeout: 5))
        let originalID = customCard(app).identifier
        screenshot("KeepUp-Custom-Recent-English")
        customCard(app).tap(); app.buttons["keypad.2"].tap(); app.buttons["keypad.5"].tap(); app.buttons["entry.save"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(record(app).waitForExistence(timeout: 5)); XCTAssertTrue(record(app).label.contains("Reading"))
        screenshot("KeepUp-Custom-Calendar-English")
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(record(app).waitForExistence(timeout: 20)); XCTAssertTrue(record(app).label.contains("25"))
        record(app).tap(); XCTAssertTrue(app.buttons["entry.share"].waitForExistence(timeout: 5))
        screenshot("KeepUp-Custom-Detail-English")
        app.buttons["entry.close"].tap(); app.buttons["tab.calendar"].tap()
        app.textFields["catalog.search"].tap(); app.textFields["catalog.search"].typeText("Reading")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "custom.more.")).firstMatch.tap()
        app.buttons.matching(identifier: "custom.removeConfirm").firstMatch.tap()
        XCTAssertTrue(customCard(app).waitForNonExistence(timeout: 5))
        app.buttons["catalog.close"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(record(app).label.contains("Reading"))
        openCustom(app); app.textFields["custom.name"].tap(); app.textFields["custom.name"].typeText("Reading\n")
        app.buttons["custom.next"].tap(); app.staticTexts["custom.unit.minutes"].tap(); app.buttons["custom.finish"].tap()
        app.buttons.matching(identifier: "custom.confirm").firstMatch.tap()
        XCTAssertTrue(customCard(app).waitForExistence(timeout: 5)); XCTAssertEqual(customCard(app).identifier, originalID)
    }

    func testChineseCustomValidationAndNoUnit() {
        let app = launch("zh-Hans"); openCustom(app)
        app.buttons["custom.next"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons.firstMatch.tap()
        app.textFields["custom.name"].tap(); app.textFields["custom.name"].typeText("阅读\n")
        app.otherElements["custom.carousel"].swipeLeft()
        screenshot("KeepUp-Custom-Name-Chinese")
        app.buttons["custom.next"].tap(); app.staticTexts["custom.unit.none"].tap()
        screenshot("KeepUp-Custom-Units-Chinese")
        app.buttons["custom.finish"].tap(); app.buttons.matching(identifier: "custom.confirm").firstMatch.tap()
        XCTAssertTrue(customCard(app).waitForExistence(timeout: 5)); customCard(app).tap()
        XCTAssertFalse(app.buttons["keypad.1"].exists)
        app.buttons["entry.save"].tap()
        XCTAssertTrue(record(app).waitForExistence(timeout: 5)); XCTAssertTrue(record(app).label.contains("阅读"))
    }

    func testEnglishReminderPermissionAndWeekdays() {
        let app = launch()
        app.buttons["tab.calendar"].tap(); app.buttons["card.preset.exercise"].tap(); app.buttons["entry.reminder"].tap()
        XCTAssertTrue(app.switches["reminder.enabled"].waitForExistence(timeout: 5)); app.switches["reminder.enabled"].tap()
        app.buttons["reminder.day.6"].tap(); app.buttons["reminder.day.1"].tap()
        app.buttons["reminder.time"].tap()
        XCTAssertTrue(app.buttons["reminder.timeDone"].waitForExistence(timeout: 5))
        screenshot("KeepUp-Reminder-Time-English")
        app.buttons["reminder.timeDone"].tap()
        screenshot("KeepUp-Reminder-Top-English")
        app.buttons["reminder.save"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons.matching(NSPredicate(format: "label == 'Allow' OR label == '允许'")).firstMatch
        if allow.waitForExistence(timeout: 4) { allow.tap() }
        XCTAssertTrue(app.buttons["reminder.save"].waitForNonExistence(timeout: 10))
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 20)); app.buttons["tab.profile"].tap(); app.buttons["profile.alarms"].tap()
        let target = app.buttons["reminder.target.preset.exercise"]
        XCTAssertTrue(target.waitForExistence(timeout: 5)); XCTAssertTrue(target.label.contains("Sat")); XCTAssertFalse(target.label.contains("Mon"))
        screenshot("KeepUp-Reminder-List-English")
        target.tap(); XCTAssertEqual(app.switches["reminder.enabled"].value as? String, "1")
        app.switches["reminder.enabled"].tap(); app.buttons["reminder.save"].tap()
        XCTAssertTrue(target.waitForNonExistence(timeout: 5))
    }

    func testNotificationTapOpensMatchingCard() {
        let app = launch("en", reminderRoute: true)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'KeepUp route verification'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        banner.tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Exercise"].exists)
        XCTAssertTrue(app.buttons["entry.reminder"].exists)
        screenshot("KeepUp-Notification-Opens-Card-English")
    }

    func testPinnedCardWeeklyProgressAndRemoveSettings() {
        let app = launch("zh-Hans")
        app.buttons["tab.calendar"].tap(); app.buttons["card.preset.exercise"].tap(); app.buttons["entry.reminder"].tap()
        XCTAssertTrue(app.switches["reminder.pin"].waitForExistence(timeout: 5)); app.switches["reminder.pin"].tap()
        screenshot("KeepUp-Reminder-Top-Chinese")
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.switches["reminder.progress"].waitForExistence(timeout: 5)); app.switches["reminder.progress"].tap()
        screenshot("KeepUp-Reminder-Progress-Chinese")
        app.buttons["reminder.save"].tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForExistence(timeout: 5)); app.buttons["entry.cancel"].tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForNonExistence(timeout: 5))
        app.buttons["catalog.close"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["target.pending.preset.exercise"].waitForExistence(timeout: 5))
        screenshot("KeepUp-Pinned-Card-Chinese")
        app.buttons["target.pending.preset.exercise"].tap(); app.buttons["keypad.3"].tap(); app.buttons["keypad.0"].tap(); app.buttons["entry.save"].tap()
        XCTAssertTrue(app.buttons["target.pending.preset.exercise"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(record(app).waitForExistence(timeout: 5))
        screenshot("KeepUp-Weekly-Progress-Chinese")
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 20)); app.buttons["tab.profile"].tap(); app.buttons["profile.alarms"].tap()
        XCTAssertTrue(app.buttons["reminder.target.preset.exercise"].waitForExistence(timeout: 5))
        screenshot("KeepUp-Reminder-List-Chinese")
        app.buttons["reminder.target.preset.exercise"].tap(); app.switches["reminder.pin"].tap()
        app.scrollViews.firstMatch.swipeUp(); app.switches["reminder.progress"].tap(); app.buttons["reminder.save"].tap()
        XCTAssertTrue(app.buttons["reminder.target.preset.exercise"].waitForNonExistence(timeout: 5))
        app.buttons["reminder.listClose"].tap(); app.buttons["tab.calendar"].tap()
        XCTAssertTrue(record(app).exists)
    }
}
