import XCTest

@MainActor
final class WeightUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func launch(_ language: String, profile: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-test-data", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if !profile { app.launchArguments.append("-ui-testing-skip-onboarding") }
        app.launch()
        if profile {
            XCTAssertTrue(app.textFields["info.nickname"].waitForExistence(timeout: 20)); app.textFields["info.nickname"].tap(); app.textFields["info.nickname"].typeText("KeepUp\n")
            app.buttons["info.next"].tap()
            for key in ["year", "height", "weight"] {
                let button = app.buttons["info.\(key)"]; if !button.isHittable { app.swipeUp() }; button.tap()
                XCTAssertTrue(app.buttons["info.ruler.confirm"].waitForExistence(timeout: 5)); app.buttons["info.ruler.confirm"].tap()
            }
            app.buttons["info.next"].tap(); XCTAssertTrue(app.buttons["info.confirm"].waitForExistence(timeout: 5)); app.buttons["info.confirm"].tap()
            XCTAssertTrue(app.buttons["membership.skip"].waitForExistence(timeout: 10)); app.buttons["membership.skip"].tap()
        }
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20)); return app
    }
    private func record(_ app: XCUIApplication) -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.")).firstMatch }
    private func openWeight(_ app: XCUIApplication) {
        app.buttons["tab.calendar"].tap(); XCTAssertTrue(app.buttons["catalog.featured.50"].waitForExistence(timeout: 5)); app.buttons["catalog.featured.50"].tap()
        XCTAssertTrue(app.buttons["weight.save"].waitForExistence(timeout: 5))
    }
    private func targetFlow(_ language: String, profile: Bool) {
        let app = launch(language, profile: profile); openWeight(app)
        capture("KeepUp-Weight-Entry-" + language)
        app.otherElements["weight.ruler"].swipeLeft(velocity: .slow)
        let firstValue = app.staticTexts["weight.value"].label
        app.buttons["weight.save"].tap(); XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(record(app).waitForExistence(timeout: 5)); let id = record(app).identifier
        openWeight(app); XCTAssertEqual(app.staticTexts["weight.value"].label, firstValue)
        app.otherElements["weight.ruler"].swipeRight(velocity: .slow); app.buttons["weight.save"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5)); XCTAssertEqual(record(app).identifier, id)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.")).count, 1)
        capture("KeepUp-Weight-Calendar-" + language)
        record(app).tap(); XCTAssertTrue(app.buttons["entry.share"].waitForExistence(timeout: 5)); capture("KeepUp-Weight-Detail-" + language)
        app.buttons["entry.share"].tap(); XCTAssertTrue(app.buttons["entry.shareSystem"].waitForExistence(timeout: 5)); app.buttons["entry.shareClose"].tap(); app.buttons["entry.close"].tap()
        app.buttons["tab.profile"].tap(); app.buttons["profile.weightTarget"].tap()
        XCTAssertTrue(app.buttons["weightTarget.save"].waitForExistence(timeout: 5)); capture("KeepUp-Weight-Target-Edit-" + language)
        let oldTarget = app.staticTexts["weightTarget.target.value"].label
        app.otherElements["weightTarget.target"].swipeRight(velocity: .slow)
        let chosenTarget = app.staticTexts["weightTarget.target.value"].label
        XCTAssertNotEqual(chosenTarget, oldTarget)
        app.buttons["weightTarget.endDate"].tap(); XCTAssertTrue(app.buttons["weightTarget.dateDone"].waitForExistence(timeout: 5)); capture("KeepUp-Weight-Target-Date-" + language); app.buttons["weightTarget.dateDone"].tap()
        app.buttons["weightTarget.save"].tap(); XCTAssertTrue(app.buttons["weightTarget.save"].waitForNonExistence(timeout: 5))
        app.buttons["profile.weightTarget"].tap(); XCTAssertTrue(app.buttons["weightTarget.save"].waitForExistence(timeout: 5)); capture("KeepUp-Weight-Target-Summary-" + language)
        XCTAssertEqual(app.staticTexts["weightTarget.savedValue"].label, chosenTarget)
        app.buttons["weightTarget.save"].tap(); app.buttons.matching(identifier: "weightTarget.confirmReset").firstMatch.tap()
        XCTAssertTrue(app.buttons["weightTarget.endDate"].waitForExistence(timeout: 5)); app.buttons["weightTarget.close"].tap()
        XCTAssertTrue(app.buttons["weightTarget.endDate"].waitForNonExistence(timeout: 5)); app.buttons["weightTarget.close"].tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(record(app).waitForExistence(timeout: 20)); XCTAssertEqual(record(app).identifier, id)
        app.buttons["tab.profile"].tap(); app.buttons["profile.weightTarget"].tap()
        XCTAssertTrue(app.buttons["weightTarget.save"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["weightTarget.endDate"].exists)
        XCTAssertEqual(app.staticTexts["weightTarget.savedValue"].label, chosenTarget)
    }
    func testEnglishWeightAndTarget() { targetFlow("en", profile: false) }
    func testChineseWeightAndTargetWithProfile() { targetFlow("zh-Hans", profile: true) }
}
