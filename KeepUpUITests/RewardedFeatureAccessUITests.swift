import XCTest

@MainActor final class RewardedFeatureAccessUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDisabledAdvertisingKeepsAllThreeProfileFeaturesFree() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 20))
        app.buttons["tab.profile"].tap()
        let features = [
            ("profile.stepTarget", "stepsTarget.close"),
            ("profile.weightTarget", "weightTarget.close"),
            ("profile.alarms", "reminder.listClose")
        ]
        for (entry, close) in features {
            XCTAssertTrue(app.buttons[entry].waitForExistence(timeout: 5))
            if !app.buttons[entry].isHittable { app.swipeUp() }
            app.buttons[entry].tap()
            XCTAssertTrue(app.buttons[close].waitForExistence(timeout: 5), "Free feature did not open: \(entry)")
            XCTAssertFalse(app.buttons["reward.watch"].exists)
            XCTAssertFalse(app.buttons["reward.continueOnce"].exists)
            app.buttons[close].tap()
            XCTAssertTrue(app.buttons[close].waitForNonExistence(timeout: 5))
        }
    }
}
