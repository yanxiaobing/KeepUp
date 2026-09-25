import XCTest

@MainActor final class HistoryCollapseUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ language: String = "en", fixture: String = "-ui-testing-history-collapse") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data",
                               fixture, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.history"].waitForExistence(timeout: 20))
        app.buttons["tab.history"].tap()
        return app
    }

    private func capture(_ name: String) {
        // Let the system button-label transition settle before visual review.
        Thread.sleep(forTimeInterval: 0.4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testExpansionDoesNotNavigateAndPublishedChangesResetCollapse() {
        let app = launch()
        let row = app.buttons["entry.history.ui-long"]
        let toggle = app.buttons["history.toggle.history.ui-long"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertTrue(app.buttons["entry.history.ui-short"].label.contains("Short note"))
        XCTAssertFalse(app.buttons["history.toggle.history.ui-short"].exists)
        let collapsedHeight = row.frame.height
        capture("KeepUp-History-Collapsed-English")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Expanded")
        XCTAssertGreaterThan(row.frame.height, collapsedHeight + 50)
        XCTAssertFalse(app.buttons["entry.actions"].exists)
        XCTAssertFalse(app.textViews["content.text"].exists)
        capture("KeepUp-History-Expanded-English")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertEqual(row.frame.height, collapsedHeight, accuracy: 1)

        toggle.tap()
        row.press(forDuration: 1)
        app.buttons["entry.editContent"].tap()
        XCTAssertTrue(app.textViews["content.text"].waitForExistence(timeout: 5))
        let editor = app.textViews["content.text"]
        editor.tap()
        editor.typeText("\nAn updated ending")
        app.buttons["content.save"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertTrue(row.label.contains("An updated ending"))
        row.tap()
        XCTAssertTrue(app.buttons["entry.editContent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["content.text"].exists)
    }

    func testChineseToggleAndShortNoteKeepTheirOwnActions() {
        let app = launch("zh-Hans")
        let toggle = app.buttons["history.toggle.history.ui-long"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.label, "展开")
        toggle.tap()
        XCTAssertEqual(toggle.label, "收起")
        XCTAssertFalse(app.buttons["entry.close"].exists)
        toggle.tap()
        XCTAssertEqual(toggle.label, "展开")
        XCTAssertFalse(app.buttons["history.toggle.history.ui-short"].exists)
        capture("KeepUp-History-Collapsed-Chinese")
        app.buttons["entry.history.ui-short"].tap()
        XCTAssertTrue(app.buttons["entry.share"].waitForExistence(timeout: 5))
    }
}
