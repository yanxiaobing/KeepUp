import XCTest

@MainActor
final class CalendarCardUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(_ language: String = "zh-Hans", longList: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-skip-onboarding", "-reset-test-data", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if longList { app.launchArguments.append("-ui-testing-calendar-scroll") }
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20))
        return app
    }
    private func records(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry."))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func addExercise(_ app: XCUIApplication, digit: Int) {
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["card.preset.exercise"].waitForExistence(timeout: 5))
        app.buttons["card.preset.exercise"].tap()
        app.buttons["keypad.\(digit)"].tap(); app.buttons["keypad.0"].tap()
        app.buttons["entry.save"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForNonExistence(timeout: 5))
    }
    private func openMenu(_ app: XCUIApplication, card: XCUIElement) {
        card.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["calendar.menu.delete"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["entry.close"].exists, "Long press must not also open the detail screen")
    }
    private func waitForScope(_ app: XCUIApplication, weekY: CGFloat, expanded: Bool) {
        let layout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                let y = app.buttons["calendar.scope"].frame.midY
                return expanded ? y > weekY + 50 : abs(y - weekY) < 2
            }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [layout], timeout: 5), .completed)
    }

    func testCardSwipesLinkCalendarScopeWithShortAndEmptyLists() {
        let app = launch()
        let scope = app.buttons["calendar.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        let weekY = scope.frame.midY
        let grid = app.descendants(matching: .any)["calendar.records"].firstMatch
        grid.swipeDown()
        waitForScope(app, weekY: weekY, expanded: true)
        capture("KeepUp-Card-Scroll-Month")
        grid.swipeUp()
        waitForScope(app, weekY: weekY, expanded: false)
        XCTAssertTrue(app.buttons["target.pending.punchcard.50"].exists)
        XCTAssertFalse(app.buttons["calendar.today"].exists)

        // Tomorrow contains only an add button; swipes must work in its blank area too.
        grid.swipeLeft()
        XCTAssertTrue(app.buttons["calendar.add"].waitForExistence(timeout: 5))
        grid.swipeDown()
        waitForScope(app, weekY: weekY, expanded: true)
        grid.swipeUp()
        waitForScope(app, weekY: weekY, expanded: false)
        app.buttons["calendar.today"].tap()
        XCTAssertTrue(app.buttons["target.pending.punchcard.50"].waitForExistence(timeout: 5))
    }

    func testLongCardListExpandsOnlyWhenBackAtTop() {
        let app = launch("en", longList: true)
        let scope = app.buttons["calendar.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        let weekY = scope.frame.midY
        let grid = app.descendants(matching: .any)["calendar.records"].firstMatch
        scope.tap()
        waitForScope(app, weekY: weekY, expanded: true)
        grid.swipeUp()
        waitForScope(app, weekY: weekY, expanded: false)
        for _ in 0..<3 { grid.swipeUp() }
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertEqual(scope.frame.midY, weekY, accuracy: 2, "Scrolling down within the list must keep the week view")
        for _ in 0..<12 {
            if scope.frame.midY > weekY + 50 { break }
            grid.swipeDown()
        }
        waitForScope(app, weekY: weekY, expanded: true)
        XCTAssertFalse(app.buttons["calendar.today"].exists)
        capture("KeepUp-Card-Scroll-Returned-To-Top")
    }

    func testSlowScopeDragSettlesAndKeepsSelectedWeek() {
        let app = launch("en")
        let scope = app.buttons["calendar.scope"]
        let weekY = scope.frame.midY
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "day.")).firstMatch
        let selectedID = selected.identifier
        let grid = app.descendants(matching: .any)["calendar.records"].firstMatch
        func drag(_ distance: CGFloat) {
            let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                        withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.3)
        }
        drag(35)
        waitForScope(app, weekY: weekY, expanded: false)
        drag(150)
        waitForScope(app, weekY: weekY, expanded: true)
        capture("KeepUp-Continuous-Slow-Expand")
        drag(-35)
        waitForScope(app, weekY: weekY, expanded: true)
        drag(-150)
        waitForScope(app, weekY: weekY, expanded: false)
        XCTAssertTrue(app.buttons[selectedID].isSelected)
        XCTAssertTrue(app.buttons[selectedID].isHittable)
        app.buttons["target.pending.punchcard.50"].tap()
        XCTAssertTrue(app.buttons["weight.cancel"].waitForExistence(timeout: 5))
    }
    func testFreshInstallShowsDefaultResidentCards() {
        let app = launch()
        for id in ["punchcard.2", "punchcard.50", "punchcard.63"] {
            XCTAssertTrue(app.buttons["target.pending.\(id)"].waitForExistence(timeout: 5))
        }
        XCTAssertEqual(records(app).count, 0)
        capture("KeepUp-Fresh-Install-Resident-Cards")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-test-data" }
        app.launch()
        for id in ["punchcard.2", "punchcard.50", "punchcard.63"] {
            XCTAssertTrue(app.buttons["target.pending.\(id)"].waitForExistence(timeout: 10))
        }
    }

    func testRecordRibbonsAndRadialMenuAllColumns() {
        let app = launch()
        for value in 1...3 { addExercise(app, digit: value) }
        XCTAssertEqual(records(app).count, 3)
        capture("KeepUp-Cards-Three-Columns")
        for index in 0..<3 {
            let card = records(app).element(boundBy: index)
            let frame = card.frame
            openMenu(app, card: card)
            let delete = app.buttons["calendar.menu.delete"]
            let reminder = app.buttons["calendar.menu.reminder"]
            XCTAssertTrue(app.buttons["calendar.menu.checkIn"].exists)
            XCTAssertTrue(reminder.isHittable)
            XCTAssertLessThan(abs(delete.frame.midX-frame.midX), index == 1 ? 65 : 3)
            if index == 0 { XCTAssertGreaterThan(reminder.frame.midX, frame.midX) }
            if index == 2 { XCTAssertLessThan(reminder.frame.midX, frame.midX) }
            capture("KeepUp-Card-Menu-Column-\(index)")
            app.buttons["calendar.menu.dismiss"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
            XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
        }
        openMenu(app, card: records(app).firstMatch)
        app.buttons["calendar.menu.reminder"].tap()
        XCTAssertTrue(app.buttons["reminder.close"].waitForExistence(timeout: 5))
        app.buttons["reminder.close"].tap()
        XCTAssertTrue(app.buttons["reminder.close"].waitForNonExistence(timeout: 5))
        openMenu(app, card: records(app).firstMatch)
        app.buttons["calendar.menu.checkIn"].tap()
        XCTAssertTrue(app.buttons["keypad.4"].waitForExistence(timeout: 5))
        app.buttons["keypad.4"].tap(); app.buttons["entry.save"].tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(records(app).count, 4)
        openMenu(app, card: records(app).firstMatch)
        app.buttons["calendar.menu.delete"].tap()
        XCTAssertTrue(app.buttons["calendar.deleteCancel"].waitForExistence(timeout: 5))
        capture("KeepUp-Card-Delete-Confirmation")
        app.buttons["calendar.deleteCancel"].tap()
        XCTAssertTrue(app.buttons["calendar.menu.delete"].waitForExistence(timeout: 5))
        app.buttons["calendar.menu.delete"].tap(); app.buttons["calendar.confirmDelete"].tap()
        XCTAssertTrue(app.buttons["calendar.menu.delete"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(records(app).count, 3)
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(records(app).firstMatch.waitForExistence(timeout: 20)); XCTAssertEqual(records(app).count, 3)
        records(app).firstMatch.tap()
        XCTAssertTrue(app.buttons["entry.close"].waitForExistence(timeout: 5))
    }
    func testPinnedCardMenuRemovalPreservesRecords() {
        let app = launch("en")
        addExercise(app, digit: 2)
        app.buttons["tab.calendar"].tap(); app.buttons["card.preset.exercise"].tap(); app.buttons["entry.reminder"].tap()
        XCTAssertTrue(app.switches["reminder.pin"].waitForExistence(timeout: 5)); app.switches["reminder.pin"].tap()
        app.buttons["reminder.save"].tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForExistence(timeout: 5)); app.buttons["entry.cancel"].tap()
        XCTAssertTrue(app.buttons["catalog.close"].waitForExistence(timeout: 5)); app.buttons["catalog.close"].tap()
        // Removing a completed record should reveal its pinned placeholder, not remove the target.
        XCTAssertTrue(records(app).firstMatch.waitForExistence(timeout: 5))
        openMenu(app, card: records(app).firstMatch)
        app.buttons["calendar.menu.delete"].tap(); app.buttons["calendar.confirmDelete"].tap()
        let pinned = app.buttons["target.pending.preset.exercise"]
        XCTAssertTrue(pinned.waitForExistence(timeout: 5))
        capture("KeepUp-Card-Pending-Ribbon-English")
        openMenu(app, card: pinned)
        app.buttons["calendar.menu.delete"].tap()
        capture("KeepUp-Card-Unpin-Confirmation-English")
        app.buttons["calendar.confirmDelete"].tap()
        XCTAssertTrue(pinned.waitForNonExistence(timeout: 5))
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-test-data" }; app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 20)); XCTAssertFalse(pinned.exists)
    }
    func testFutureCardMenuChecksInTodayAndDeletesOnlyPlan() {
        let app = launch("en")
        app.otherElements["calendar.records"].swipeLeft()
        app.buttons["calendar.add"].tap(); app.buttons["card.preset.exercise"].tap()
        XCTAssertTrue(app.textViews["schedule.note"].waitForExistence(timeout: 5))
        app.textViews["schedule.note"].tap(); app.textViews["schedule.note"].typeText("Bring water")
        app.buttons["schedule.save"].tap()
        let plan = app.buttons["schedule.card.preset.exercise"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5)); capture("KeepUp-Card-Planned-English")
        openMenu(app, card: plan)
        app.buttons["calendar.menu.checkIn"].tap()
        XCTAssertTrue(app.buttons["keypad.2"].waitForExistence(timeout: 5))
        app.buttons["keypad.2"].tap(); app.buttons["entry.save"].tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(plan.exists); XCTAssertEqual(records(app).count, 0)
        openMenu(app, card: plan)
        app.buttons["calendar.menu.delete"].tap(); app.buttons["calendar.confirmDelete"].tap()
        XCTAssertTrue(plan.waitForNonExistence(timeout: 5))
        app.buttons["calendar.today"].tap()
        XCTAssertTrue(records(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(records(app).count, 1)
    }
    func testWakeCardMenuSuppressesDuplicateCheckIn() {
        let app = launch("en")
        app.buttons["tab.calendar"].tap(); app.buttons["Add wake-up card"].tap()
        XCTAssertTrue(app.buttons["wake.activate"].waitForExistence(timeout: 5)); app.buttons["wake.activate"].tap()
        let pending = app.buttons["target.pending.punchcard.63"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5)); openMenu(app, card: pending)
        XCTAssertTrue(app.buttons["calendar.menu.checkIn"].exists)
        app.buttons["calendar.menu.checkIn"].tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForExistence(timeout: 5)); app.buttons["entry.save"].tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 1) { app.alerts.buttons.matching(identifier: "wake.confirm").firstMatch.tap() }
        XCTAssertTrue(records(app).firstMatch.waitForExistence(timeout: 5))
        capture("KeepUp-Card-Wake-Restored")
        openMenu(app, card: records(app).firstMatch)
        XCTAssertFalse(app.buttons["calendar.menu.checkIn"].exists)
        XCTAssertTrue(app.buttons["calendar.menu.reminder"].exists)
        capture("KeepUp-Card-Wake-Menu")
        app.buttons["calendar.menu.dismiss"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
    }
}
