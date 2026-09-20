import XCTest

@MainActor final class RunningDetailsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(kind: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data",
                               "-ui-testing-running-details", kind, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.history"].waitForExistence(timeout: 20))
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openRecord(kind: String, in app: XCUIApplication) {
        app.buttons["tab.history"].tap()
        let record = app.buttons["entry.running.ui-details-" + kind]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(app.staticTexts["running.result.distance"].waitForExistence(timeout: 10))
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<9 {
            if target.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            // Use the detail page margin so a map/chart cannot consume this scroll gesture.
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25)))
        }
        XCTAssertTrue(target.isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testOutdoorSplitsExpandAndSharePreviewContainsFullActivity() {
        let app = launch(kind: "outdoor")
        openRecord(kind: "outdoor", in: app)
        XCTAssertEqual(app.staticTexts["running.result.distance"].label, "4.25")
        XCTAssertNotEqual(app.staticTexts["running.result.energy"].label, "—")
        capture("KeepUp-Running-Details-Overview-English")
        let toggle = app.buttons["running.splits.toggle"]
        reveal(toggle, in: app)
        XCTAssertNotEqual(app.staticTexts["running.bestKilometer"].label, "—")
        XCTAssertFalse(element("running.split.tail", in: app).exists)
        toggle.tap()
        reveal(element("running.split.tail", in: app), in: app)
        XCTAssertTrue(element("running.split.4", in: app).exists)
        capture("KeepUp-Running-Details-All-Splits-English")
        toggle.tap()
        XCTAssertFalse(element("running.split.tail", in: app).exists)
        reveal(element("running.chart.altitude", in: app), in: app)
        XCTAssertFalse(element("running.chart.altitude.missing", in: app).exists)
        capture("KeepUp-Running-Details-Elevation-English")
        app.buttons["running.detail.share"].tap()
        XCTAssertTrue(element("running.share.ready", in: app).waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["running.share.system"].isEnabled)
        capture("KeepUp-Running-Details-Share-English")
        app.buttons["running.share.close"].tap()
        XCTAssertTrue(app.buttons["running.detail.share"].waitForExistence(timeout: 5))
    }

    func testIndoorDetailShowsMeasuredCadenceWithoutMap() {
        let app = launch(kind: "indoor")
        openRecord(kind: "indoor", in: app)
        XCTAssertFalse(app.maps.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["running.result.steps"].exists)
        let cadence = element("running.chart.cadence", in: app)
        reveal(cadence, in: app)
        XCTAssertNotEqual(app.staticTexts["running.chart.cadence.maximum"].label, "— steps/min")
        XCTAssertFalse(element("running.chart.cadence.missing", in: app).exists)
        XCTAssertFalse(element("running.chart.altitude", in: app).exists)
        capture("KeepUp-Running-Details-Indoor-Cadence-English")
    }

    func testActivityNotesEditingAndDeletionSurviveRelaunch() {
        let app = launch(kind: "cycling")
        openRecord(kind: "cycling", in: app)
        app.buttons["running.detail.actions"].tap()
        app.buttons["running.detail.edit"].tap()
        XCTAssertTrue(app.textViews["content.text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["content.photo"].exists)
        app.textViews["content.text"].tap()
        app.textViews["content.text"].typeText("A steady morning ride")
        app.buttons["content.save"].tap()
        XCTAssertTrue(app.buttons["running.detail.actions"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["running.detail.text"], in: app)
        XCTAssertEqual(app.staticTexts["running.detail.text"].label, "A steady morning ride")
        capture("KeepUp-Running-Details-Notes-English")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.history"].waitForExistence(timeout: 20))
        openRecord(kind: "cycling", in: app)
        reveal(app.staticTexts["running.detail.text"], in: app)
        XCTAssertEqual(app.staticTexts["running.detail.text"].label, "A steady morning ride")
        app.buttons["running.detail.actions"].tap()
        app.buttons["running.detail.delete"].tap()
        XCTAssertTrue(app.buttons["running.detail.confirmDelete"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["running.detail.confirmDelete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["running.result.close"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons["entry.running.ui-details-cycling"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab.history"].waitForExistence(timeout: 20))
        app.buttons["tab.history"].tap()
        XCTAssertFalse(app.buttons["entry.running.ui-details-cycling"].exists)
    }
}
