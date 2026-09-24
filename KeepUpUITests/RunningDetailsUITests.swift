import XCTest

@MainActor final class RunningDetailsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(kind: String, chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data",
                               "-ui-testing-running-details", kind, "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
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
        record.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        XCTAssertTrue(app.staticTexts["running.overview.distance"].waitForExistence(timeout: 10))
        capture("KeepUp-Running-" + kind + "-Route")
        XCTAssertEqual(app.buttons["running.page.2"].exists, kind != "cycling")
        if kind != "cycling" {
            app.buttons["running.page.2"].tap()
            XCTAssertTrue(element("running.card", in: app).waitForExistence(timeout: 5))
            capture("KeepUp-Running-" + kind + "-Card")
        }
        app.buttons["running.page.1"].tap()
        XCTAssertTrue(app.staticTexts["running.result.distance"].waitForExistence(timeout: 5))
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<9 {
            if target.isHittable { return }
            let scroll = app.scrollViews["running.result"]
            // The restored statistics page has no interactive map; scroll its center, away from paging edges.
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        }
        if !target.isHittable { capture("Running-Detail-Unreachable"); print(app.debugDescription) }
        XCTAssertTrue(target.isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testChinesePagesAndRouteMap() {
        for kind in ["outdoor", "cycling", "indoor"] {
            let app = launch(kind: kind, chinese: true)
            openRecord(kind: kind, in: app)
            capture("KeepUp-Running-" + kind + "-Details-Chinese")
            app.buttons["running.page.0"].tap()
            if kind != "indoor" {
                app.buttons["running.map.open"].tap()
                XCTAssertTrue(app.buttons["running.map.close"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.maps.firstMatch.exists)
                app.buttons["running.map.kilometers"].tap()
                XCTAssertEqual(app.buttons["running.map.kilometers"].value as? String, "已显示")
                app.buttons["running.map.places"].tap()
                XCTAssertEqual(app.buttons["running.map.places"].value as? String, "已隐藏")
                app.buttons["running.map.fit"].tap()
                capture("KeepUp-Running-" + kind + "-Map-Chinese")
                app.buttons["running.map.close"].tap()
            }
            app.swipeLeft()
            XCTAssertTrue(app.staticTexts["running.result.distance"].waitForExistence(timeout: 5))
            app.terminate()
        }
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
