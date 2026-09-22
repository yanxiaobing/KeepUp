import XCTest

@MainActor
final class EntryContentUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        return app
    }
    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.5)
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func addRecord(_ app: XCUIApplication) {
        app.buttons["tab.calendar"].tap()
        app.buttons["card.preset.exercise"].tap()
        app.buttons["keypad.3"].tap(); app.buttons["keypad.0"].tap(); app.buttons["entry.save"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
    }
    private func record(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.")).firstMatch
    }
    func testEnergyPreviewPosterAndHistory() throws {
        for language in ["en", "zh-Hans"] {
            let app = launch(language)
            app.buttons["tab.calendar"].tap()
            app.buttons["card.preset.exercise"].tap()
            XCTAssertFalse(app.staticTexts["energy.preview"].exists)
            app.buttons["keypad.3"].tap(); app.buttons["keypad.0"].tap()
            let expected = language == "en" ? "Est. 175 kcal burned · ≈ 4 chicken nuggets" : "预计消耗175大卡 · 约等于4个上校鸡块"
            XCTAssertEqual(app.staticTexts["energy.preview"].label, expected)
            shot("KeepUp-Energy-Input-" + language)
            app.buttons["entry.save"].tap()
            XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
            record(app).tap()
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 5), app.debugDescription)
            shot("KeepUp-Energy-Poster-" + language)
            app.buttons["entry.share"].tap()
            XCTAssertTrue(app.buttons["entry.shareSystem"].waitForExistence(timeout: 5))
            shot("KeepUp-Energy-Share-" + language)
            app.buttons["entry.shareClose"].tap()
            app.buttons["entry.close"].tap()
            app.buttons["tab.history"].tap()
            XCTAssertTrue(app.staticTexts["energy.dailyTotal"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["energy.dailyTotal"].label.contains("175"))
            XCTAssertTrue(record(app).label.contains(expected))
            shot("KeepUp-Energy-History-" + language)
            app.terminate()
            app.launchArguments.removeAll { $0 == "-reset-test-data" }
            app.launch()
            app.buttons["tab.history"].tap()
            XCTAssertTrue(app.staticTexts["energy.dailyTotal"].waitForExistence(timeout: 5))
            XCTAssertTrue(record(app).label.contains(expected))
            app.terminate()
        }
    }

    func testPhotoNoteDraftRelaunchAndDiscard() throws {
        let app = launch()
        addRecord(app)
        record(app).tap()
        XCTAssertTrue(app.buttons["entry.share"].waitForExistence(timeout: 5))
        shot("KeepUp-Entry-Poster-English")
        app.buttons["entry.share"].tap()
        XCTAssertTrue(app.buttons["entry.shareSystem"].waitForExistence(timeout: 5))
        shot("KeepUp-Entry-Share-Preview")
        app.buttons["entry.shareClose"].tap()
        XCTAssertTrue(app.buttons["entry.shareClose"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entry.actions"].waitForExistence(timeout: 5))
        app.buttons["entry.actions"].tap(); app.buttons["entry.editContent"].tap()
        XCTAssertTrue(app.textViews["content.text"].waitForExistence(timeout: 5))
        app.textViews["content.text"].tap(); app.textViews["content.text"].typeText("A great workout")
        app.buttons["content.photo"].tap()
        app.buttons.matching(identifier: "content.library").firstMatch.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["info.crop.done"].waitForExistence(timeout: 10))
        app.buttons["info.crop.done"].tap()
        XCTAssertTrue(app.buttons["content.removePhoto"].waitForExistence(timeout: 10))
        app.buttons["content.photo"].tap()
        XCTAssertTrue(app.buttons["info.crop.cancel"].waitForExistence(timeout: 10))
        app.buttons["info.crop.cancel"].tap()
        XCTAssertTrue(app.buttons["content.removePhoto"].waitForExistence(timeout: 5))
        shot("KeepUp-Entry-Content-English")
        app.buttons["content.save"].tap()
        XCTAssertTrue(app.buttons["entry.close"].waitForExistence(timeout: 5))
        app.buttons["entry.close"].tap()
        app.buttons["tab.history"].tap()
        XCTAssertTrue(record(app).label.contains("A great workout"))
        shot("KeepUp-Timeline-Photo-English")
        record(app).press(forDuration: 1)
        app.buttons["entry.editContent"].tap()
        XCTAssertTrue(app.textViews["content.text"].waitForExistence(timeout: 5))
        app.textViews["content.text"].tap(); app.textViews["content.text"].typeText(" draft")
        app.buttons["content.cancel"].tap(); app.buttons.matching(identifier: "content.keepDraft").firstMatch.tap()
        XCTAssertTrue(app.buttons["tab.history"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(app.buttons["tab.history"].waitForExistence(timeout: 15)); app.buttons["tab.history"].tap()
        record(app).tap()
        XCTAssertTrue(app.textViews["content.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["content.text"].value as? String, "A great workout draft")
        XCTAssertTrue(app.buttons["content.removePhoto"].exists)
        app.textViews["content.text"].tap(); app.textViews["content.text"].typeText(" discarded")
        app.buttons["content.cancel"].tap(); app.buttons.matching(identifier: "content.discard").firstMatch.tap()
        XCTAssertTrue(app.buttons["tab.history"].waitForExistence(timeout: 5))
        XCTAssertTrue(record(app).label.contains("A great workout"))
        XCTAssertFalse(record(app).label.contains("discarded"))
        XCTAssertFalse(record(app).label.contains("Draft"))
    }
    func testChinesePosterAndEditor() throws {
        let app = launch("zh-Hans")
        addRecord(app); record(app).tap()
        XCTAssertTrue(app.buttons["entry.share"].waitForExistence(timeout: 5))
        shot("KeepUp-Entry-Poster-Chinese")
        app.buttons["entry.actions"].tap(); app.buttons["entry.editContent"].tap()
        XCTAssertTrue(app.textViews["content.text"].waitForExistence(timeout: 5))
        shot("KeepUp-Entry-Content-Chinese")
        app.buttons["content.cancel"].tap()
        XCTAssertTrue(app.buttons["entry.close"].waitForExistence(timeout: 5))
    }
    func testPersonalInfoUpdatesAndWeightCheckIn() throws {
        let app = launch("zh-Hans")
        app.buttons["tab.profile"].tap(); app.buttons["profile.settings"].tap(); app.buttons["profile.edit"].tap()
        XCTAssertTrue(app.buttons["profile.info.gender"].waitForExistence(timeout: 5))
        shot("KeepUp-Profile-Personal-Chinese")
        app.buttons["profile.info.gender"].tap(); app.buttons["profile.info.male"].tap()
        XCTAssertTrue(app.buttons["profile.info.gender"].label.contains("男"))
        app.buttons["profile.info.height"].tap()
        XCTAssertTrue(app.buttons["info.ruler.confirm"].waitForExistence(timeout: 5))
        shot("KeepUp-Profile-Personal-Ruler")
        app.buttons["info.ruler.confirm"].tap()
        app.buttons["profile.info.weight"].tap()
        app.otherElements["info.ruler"].swipeLeft(velocity: .slow)
        app.buttons["info.ruler.confirm"].tap()
        app.buttons["profile.info.back"].tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(app.buttons["tab.history"].waitForExistence(timeout: 15)); app.buttons["tab.history"].tap()
        XCTAssertTrue(record(app).waitForExistence(timeout: 5))
        XCTAssertTrue(record(app).label.contains("体重"))
    }
    func testThemeAppliesWithoutMembershipAndPersists() throws {
        let app = launch("zh-Hans")
        app.buttons["theme.open"].tap()
        XCTAssertTrue(app.buttons["theme.1"].waitForExistence(timeout: 5))
        app.buttons["theme.1"].tap()
        XCTAssertTrue(app.buttons["theme.apply"].waitForExistence(timeout: 5))
        app.buttons["theme.apply"].tap()
        XCTAssertTrue(app.buttons["theme.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["membership.purchase"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["theme.open"].waitForExistence(timeout: 15))
        app.buttons["theme.open"].tap()
        app.buttons["theme.1"].tap()
        XCTAssertTrue(app.buttons["theme.apply"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["theme.apply"].isEnabled)
        shot("KeepUp-Theme-Applied-Without-Membership")
    }

    func testDeniedPhotoAccessOffersSettingsWithoutLosingPreview() throws {
        let app = launch()
        app.resetAuthorizationStatus(for: .photos)
        // Reset may terminate the app; relaunch before opening the card.
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        addRecord(app); record(app).tap()
        app.buttons["entry.share"].tap()
        XCTAssertTrue(app.buttons["entry.saveImage"].waitForExistence(timeout: 5))
        app.buttons["entry.saveImage"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "不允许"])).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 10))
        deny.tap()
        XCTAssertTrue(app.alerts.buttons["entry.photoSettings"].waitForExistence(timeout: 10))
        shot("KeepUp-Share-Photo-Denied-Settings")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["entry.shareSystem"].isEnabled)
        app.buttons["entry.saveImage"].tap()
        XCTAssertTrue(app.alerts.buttons["entry.photoSettings"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.buttons["entry.shareClose"].tap()
        XCTAssertTrue(app.buttons["entry.close"].waitForExistence(timeout: 5))
    }

    func testSavePosterToPhotoLibrary() throws {
        let app = launch()
        addRecord(app); record(app).tap()
        XCTAssertTrue(app.buttons["entry.share"].waitForExistence(timeout: 5))
        app.buttons["entry.share"].tap()
        XCTAssertTrue(app.buttons["entry.saveImage"].waitForExistence(timeout: 5))
        app.buttons["entry.saveImage"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Image saved to Photos."].waitForExistence(timeout: 10))
        app.alerts.buttons.firstMatch.tap()
        app.buttons["entry.shareClose"].tap()
        XCTAssertTrue(app.buttons["entry.close"].waitForExistence(timeout: 5))
    }

}
