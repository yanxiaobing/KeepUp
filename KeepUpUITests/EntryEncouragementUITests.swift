import XCTest

@MainActor final class EntryEncouragementUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testEnglishPostersAndSavedWeightGoal() { verify("en") }
    func testChinesePostersAndSavedWeightGoal() { verify("zh-Hans") }

    private func verify(_ language: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-ui-testing-entry-posters",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        let total = language == "en" ? "Exercise total: 45.5 min. Every effort counts!" : "累计健身45.5分钟，每一次坚持都有收获！"
        let achieved = language == "en" ? "Weight-loss goal reached! 10 days, 5.5 kg lost." : "达成减重目标！用10天减重5.5公斤。"
        open(app, id: "poster.ui-total.1")
        XCTAssertTrue(app.staticTexts[total].waitForExistence(timeout: 5), app.debugDescription)
        capture("KeepUp-Poster-Total-" + language)
        shareAndReturn(app, language: language, name: "Total")
        XCTAssertTrue(app.staticTexts[total].exists)
        app.buttons["entry.close"].tap()
        open(app, id: "poster.ui-weight")
        XCTAssertTrue(app.staticTexts[achieved].waitForExistence(timeout: 5), app.debugDescription)
        capture("KeepUp-Poster-Weight-Goal-" + language)
        shareAndReturn(app, language: language, name: "Weight-Goal")
        app.buttons["entry.close"].tap()
        app.buttons["tab.profile"].tap()
        let duration = language == "en" ? "KeepUp · Day 11 together" : "KeepUp - 与你相遇的第11天"
        XCTAssertTrue(app.staticTexts[duration].waitForExistence(timeout: 5), app.debugDescription)
        capture("KeepUp-Profile-Duration-" + language)

        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        open(app, id: "poster.ui-weight")
        XCTAssertTrue(app.staticTexts[achieved].waitForExistence(timeout: 5))
        app.buttons["entry.close"].tap()
        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.staticTexts[duration].waitForExistence(timeout: 5))
        app.terminate()
    }

    private func open(_ app: XCUIApplication, id: String) {
        // The selected Calendar tab is the check-in action; switch away before returning.
        app.buttons["tab.history"].tap()
        app.buttons["tab.calendar"].tap()
        let row = app.buttons["entry." + id]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["entry.share"].waitForExistence(timeout: 5))
    }

    private func shareAndReturn(_ app: XCUIApplication, language: String, name: String) {
        app.buttons["entry.share"].tap()
        XCTAssertTrue(app.buttons["entry.shareSystem"].waitForExistence(timeout: 5))
        capture("KeepUp-Poster-Share-\(name)-\(language)")
        app.buttons["entry.shareClose"].tap()
        XCTAssertTrue(app.buttons["entry.shareClose"].waitForNonExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
