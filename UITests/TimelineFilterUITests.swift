import XCTest

final class TimelineFilterUITests: XCTestCase {
    private let avaID = "A0000000-0000-0000-0000-000000000002"
    private let benID = "A0000000-0000-0000-0000-000000000003"

    @MainActor
    func testListDefaultFiltersAndThreadsKeepsAllMembers() {
        checkFilters(largestDark: false, landscape: false)
    }

    @MainActor
    func testListFiltersAtLargestDarkTextWithReducedMotion() {
        checkFilters(largestDark: true, landscape: false)
    }

    @MainActor
    func testListFiltersAndWideLayoutControlInLandscape() {
        checkFilters(largestDark: false, landscape: true)
    }

    @MainActor
    private func checkFilters(largestDark: Bool, landscape: Bool) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["--manna-local-ui-test", "--manna-timeline-ui-test", "--manna-photo-ui-test",
            "-blessingCircle.selectedCircleID", "B0000000-0000-0000-0000-000000000001",
            "-user.appearancePreference", largestDark ? "dark" : "light",
            "-UIPreferredContentSizeCategoryName",
            largestDark ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
            "-UIAccessibilityReduceMotionEnabled", "YES"]
        app.terminate()
        app.launch()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        if landscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        }
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))

        let layout = app.buttons["timeline.layout"]
        let filter = app.buttons["timeline.personFilter"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5), app.debugDescription)
        assertValue(layout, "List")
        XCTAssertTrue(list(app).waitForExistence(timeout: 5))
        XCTAssertTrue(filter.exists)
        assertValue(filter, "All")
        assertLayoutTouchRegion(layout, app: app)
        assertTarget(filter)
        XCTAssertFalse(memberHeader(app).exists)
        assertNoPlaceholders(app)
        XCTAssertFalse(app.staticTexts["0 responses"].exists)
        attach(app, "Timeline List default \(variant(largestDark, landscape))")

        choosePerson("Ava", app: app)
        assertValue(filter, "Ava")
        assertOnlyPerson(avaID, app: app)
        let avaBlessing = list(app).buttons.matching(NSPredicate(format: "label CONTAINS %@",
            "Sunlight through the kitchen window.")).firstMatch
        XCTAssertTrue(avaBlessing.waitForExistence(timeout: 5))
        XCTAssertFalse(list(app).buttons.matching(NSPredicate(format: "label CONTAINS %@",
            "A hard conversation that ended with more understanding.")).firstMatch.exists,
            "Today's peer blessing stays locked until the current user shares.")
        let responseSummary = list(app).descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "timeline.responses.", "3 responses")).firstMatch
        XCTAssertTrue(responseSummary.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(responseSummary.label, "3 responses. From Micah, Ben",
            "Three responses from two people retain the total count and distinct responder names.")
        revealResponse(responseSummary, in: app)
        XCTAssertTrue(responseSummary.isHittable)
        attach(app, "Timeline response count and distinct people \(variant(largestDark, landscape))")
        avaBlessing.tap()
        XCTAssertTrue(app.navigationBars["Blessing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sunlight through the kitchen window."].exists)
        app.buttons["Close blessing"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))
        // The person control remains above the List while content scrolls.
        for _ in 0..<3 {
            assertOnlyPerson(avaID, app: app)
            list(app).swipeUp(velocity: .slow)
            XCTAssertTrue(filter.isHittable)
        }
        assertOnlyPerson(avaID, app: app)
        attach(app, "Timeline Ava filter \(variant(largestDark, landscape))")

        chooseLayout("Threads", app: app)
        assertValue(layout, "Threads")
        XCTAssertFalse(filter.exists, "Person filters belong only to List.")
        XCTAssertTrue(memberHeader(app).waitForExistence(timeout: 5))
        let header = memberHeader(app)
        XCTAssertTrue(header.staticTexts["You"].exists)
        XCTAssertTrue(header.staticTexts["Ava"].exists)
        XCTAssertTrue(header.staticTexts["Ben"].exists,
            "Threads keeps every member even while Ava is selected in List.")
        attach(app, "Timeline Threads all members \(variant(largestDark, landscape))")

        chooseLayout("List", app: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        assertValue(filter, "Ava")
        assertOnlyPerson(avaID, app: app)

        choosePerson("Ben", app: app)
        assertValue(filter, "Ben")
        assertOnlyPerson(benID, app: app)
        // Ben has joined but has not shared; the List must retain his joining card.
        let joining = list(app).descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Joined circle")).firstMatch
        XCTAssertTrue(joining.waitForExistence(timeout: 5))
        assertNoPlaceholders(app)
        attach(app, "Timeline Ben joining event \(variant(largestDark, landscape))")

        // Refresh the filtered page without changing which person is selected.
        list(app).swipeDown(velocity: .slow)
        assertValue(filter, "Ben")
        assertOnlyPerson(benID, app: app)

        app.buttons["Current circle, Sunday Table"].tap()
        app.buttons["Morning Prayer"].tap()
        XCTAssertTrue(app.buttons["Current circle, Morning Prayer"].waitForExistence(timeout: 10))
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        assertValue(filter, "All")
        assertValue(layout, "List")
        filter.tap()
        XCTAssertTrue(app.buttons["Grace"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Ava"].exists)
        app.buttons["All"].tap()
        attach(app, "Timeline circle filter reset \(variant(largestDark, landscape))")
    }

    @MainActor
    private func revealResponse(_ element: XCUIElement, in app: XCUIApplication) {
        let top = app.buttons["timeline.personFilter"].frame.maxY + 4
        let bottom = app.tabBars.firstMatch.frame.minY - 4
        let height = bottom - top
        for _ in 0..<30 {
            let frame = element.exists ? element.frame : .zero
            if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
            let delta = frame.height > 0 ? frame.midY - (top + bottom) / 2 : height
            let backwards = delta < 0
            let travel = min(height * 0.32, max(24, abs(delta) * 0.7))
            let start = top + height * (backwards ? 0.35 : 0.7)
            let end = min(bottom - 12, max(top + 12, start + (backwards ? travel : -travel)))
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start / app.frame.height))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end / app.frame.height)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    @MainActor
    private func choosePerson(_ name: String, app: XCUIApplication) {
        let filter = app.buttons["timeline.personFilter"]
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        let option = app.buttons[name]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        attach(app, "Photo person picker")
        option.tap()
        assertValue(filter, name)
    }

    @MainActor
    private func chooseLayout(_ name: String, app: XCUIApplication) {
        let layout = app.buttons["timeline.layout"]
        XCTAssertTrue(layout.isHittable)
        layout.tap()
        let option = app.buttons[name]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        assertValue(layout, name)
    }

    @MainActor
    private func list(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "timeline.accessibleList").firstMatch
    }

    @MainActor
    private func memberHeader(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "timeline.memberHeader").firstMatch
    }

    @MainActor
    private func assertOnlyPerson(_ memberID: String, app: XCUIApplication) {
        let rows = list(app).descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.listRow.")).allElementsBoundByIndex
        XCTAssertFalse(rows.isEmpty, "The selected person should have actual events in this fixture.")
        for row in rows {
            XCTAssertTrue(row.identifier.hasPrefix("timeline.listRow.\(memberID)."), row.identifier)
        }
        assertNoPlaceholders(app)
    }

    @MainActor
    private func assertNoPlaceholders(_ app: XCUIApplication) {
        for label in ["Missed this day", "Waiting for notification", "Locked until you share"] {
            XCTAssertFalse(list(app).staticTexts[label].exists)
        }
    }

    @MainActor
    private func assertValue(_ element: XCUIElement, _ value: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    @MainActor
    private func assertLayoutTouchRegion(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.width, 110)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44 - 0.01)
        // Exercise the complete 44-point touch square, including its corners,
        // rather than relying solely on the accessibility frame.
        for (x, y) in [(-21.5, -21.5), (21.5, -21.5), (-21.5, 21.5), (21.5, 21.5)] {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: x, dy: y)).tap()
            XCTAssertTrue(app.buttons["Threads"].waitForExistence(timeout: 3), "The full 44-point target must open the layout menu.")
            app.buttons["List"].tap()
        }
    }

    @MainActor
    private func assertTarget(_ element: XCUIElement, minimumWidth: CGFloat = 44) {
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.width, minimumWidth - 0.01)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44 - 0.01)
    }

    private func variant(_ largest: Bool, _ landscape: Bool) -> String {
        landscape ? "landscape" : largest ? "largest dark reduced motion" : "normal"
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
