import XCTest

@MainActor
final class ProfileMembershipUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func screenshot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.5) // Capture the settled screen, after the original page transition.
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func launch(_ language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-test-data", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["startup.agree"].waitForExistence(timeout: 20))
        app.buttons["startup.agree"].tap()
        return app
    }
    func testPrivacyConsentPersistsBeforeProfileCompletion() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-test-data", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["startup.agree"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["info.next"].exists)
        XCTAssertFalse(app.buttons["tab.calendar"].exists)
        screenshot("KeepUp-Startup-Privacy-Chinese")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(app.buttons["startup.agree"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["startup.agree"].waitForExistence(timeout: 15))
        app.buttons["startup.agree"].tap()
        XCTAssertTrue(app.buttons["info.next"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["info.next"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["startup.agree"].exists)
        XCTAssertFalse(app.buttons["tab.calendar"].exists)
    }

    func testEnglishPrivacyPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-test-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["startup.agree"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["startup.agree"].label, "Agree and Continue")
        screenshot("KeepUp-Startup-Privacy-English")
        app.buttons["startup.agree"].tap()
        XCTAssertTrue(app.buttons["info.next"].waitForExistence(timeout: 5))
    }

    func testOnboardingReachesHomeAfterMembershipDismisses() {
        let app = launch("zh-Hans")
        XCTAssertTrue(app.buttons["info.next"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["tab.calendar"].exists)
        app.buttons["info.next"].tap()
        for key in ["year", "height", "weight"] {
            let button = app.buttons["info.\(key)"]
            if !button.isHittable { app.swipeUp() }
            button.tap()
            XCTAssertTrue(app.buttons["info.ruler.confirm"].waitForExistence(timeout: 5))
            app.buttons["info.ruler.confirm"].tap()
        }
        app.buttons["info.next"].tap()
        XCTAssertTrue(app.buttons["info.confirm"].waitForExistence(timeout: 5))
        app.buttons["info.confirm"].tap()
        XCTAssertTrue(app.buttons["membership.skip"].waitForExistence(timeout: 10))
        app.buttons["membership.skip"].tap()
        XCTAssertTrue(app.buttons["membership.skip"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 5))
        for id in ["punchcard.2", "punchcard.50", "punchcard.63"] {
            XCTAssertTrue(app.buttons["target.pending.\(id)"].waitForExistence(timeout: 5))
        }
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["info.next"].exists)
        XCTAssertFalse(app.buttons["membership.skip"].exists)
    }

    func testChineseProfileAndMembership() throws {
        let app = launch("zh-Hans")
        XCTAssertTrue(app.textFields["info.nickname"].waitForExistence(timeout: 20))
        app.textFields["info.nickname"].tap()
        app.textFields["info.nickname"].typeText("KeepUp\n")
        screenshot("KeepUp-Profile-Social-Chinese")
        app.buttons["info.avatar"].tap()
        XCTAssertTrue(app.buttons["info.library"].waitForExistence(timeout: 5))
        screenshot("KeepUp-Profile-Avatar-Actions")
        app.buttons["取消"].tap()
        app.buttons["info.male"].tap()
        app.buttons["info.next"].tap()
        screenshot("KeepUp-Profile-Body-Chinese")
        for key in ["year", "height", "weight"] {
            let button = app.buttons["info.\(key)"]
            if !button.isHittable { app.swipeUp() }
            button.tap()
            XCTAssertTrue(app.buttons["info.ruler.confirm"].waitForExistence(timeout: 5))
            if key == "year" { screenshot("KeepUp-Profile-Ruler-Chinese") }
            app.otherElements["info.ruler"].swipeLeft(velocity: .slow)
            app.buttons["info.ruler.confirm"].tap()
        }
        app.buttons["info.next"].tap()
        XCTAssertTrue(app.buttons["info.confirm"].waitForExistence(timeout: 5))
        screenshot("KeepUp-Profile-Confirm-Chinese")
        app.buttons["info.confirm"].tap()
        XCTAssertTrue(app.buttons["membership.skip"].waitForExistence(timeout: 10))
        screenshot("KeepUp-Membership-Onboarding-Chinese")
        app.buttons["membership.skip"].tap()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["info.nickname"].exists)
        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.staticTexts["KeepUp"].exists)
        app.buttons["profile.premium"].tap()
        XCTAssertTrue(app.buttons["membership.restore"].waitForExistence(timeout: 5))
        screenshot("KeepUp-Membership-Chinese")
        app.buttons["membership.purchase"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons.firstMatch.tap()
        app.buttons["membership.close"].tap()
        XCTAssertTrue(app.buttons["membership.close"].waitForNonExistence(timeout: 5))
        app.buttons["profile.settings"].tap()
        XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 5))
        app.buttons["profile.edit"].tap()
        XCTAssertEqual(app.textFields["info.nickname"].value as? String, "KeepUp")
        app.textFields["info.nickname"].tap()
        app.textFields["info.nickname"].typeText("X\n")
        let editedNickname = app.textFields["info.nickname"].value as? String
        XCTAssertTrue(editedNickname?.contains("X") == true)
        app.buttons["profile.info.back"].tap()
        app.buttons["profile.edit"].tap()
        XCTAssertEqual(app.textFields["info.nickname"].value as? String, editedNickname)
        screenshot("KeepUp-Profile-Personal-Info")
        app.buttons["profile.info.back"].tap()
    }
    func testAvatarSelectionAndSquareCrop() throws {
        let app = launch("en")
        XCTAssertTrue(app.buttons["info.avatar"].waitForExistence(timeout: 20))
        app.buttons["info.avatar"].tap()
        app.buttons["info.library"].tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["info.crop.done"].waitForExistence(timeout: 10))
        screenshot("KeepUp-Profile-Avatar-Crop")
        app.buttons["info.crop.done"].tap()
        XCTAssertTrue(app.buttons["info.next"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["info.avatar"].label.contains("Set your avatar"))
        screenshot("KeepUp-Profile-Avatar-Selected")
    }

    func testMembershipCloseButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 20))
        app.buttons["tab.profile"].tap()
        app.buttons["profile.premium"].tap()
        XCTAssertTrue(app.buttons["membership.close"].waitForExistence(timeout: 5))
        app.buttons["membership.close"].tap()
        XCTAssertTrue(app.buttons["membership.close"].waitForNonExistence(timeout: 5))
    }

    func testEnglishProfileAndMembership() throws {
        let app = launch("en")
        XCTAssertTrue(app.textFields["info.nickname"].waitForExistence(timeout: 20))
        app.textFields["info.nickname"].tap(); app.textFields["info.nickname"].typeText("Jamie\n")
        screenshot("KeepUp-Profile-Social-English")
        app.buttons["info.next"].tap()
        screenshot("KeepUp-Profile-Body-English")
        app.buttons["info.next"].tap()
        screenshot("KeepUp-Profile-Confirm-English")
        app.buttons["info.confirm"].tap()
        XCTAssertTrue(app.buttons["membership.skip"].waitForExistence(timeout: 10))
        screenshot("KeepUp-Membership-English")
        app.buttons["membership.skip"].tap()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 5))
    }
}
