import XCTest

final class StreakPresentationUITests: XCTestCase {
    @MainActor
    func testMixedStreakPresentationAndPopup() {
        checkMixedStreak(largestText: false)
    }

    @MainActor
    func testMixedStreakPresentationAtLargestTextInDarkMode() {
        checkMixedStreak(largestText: true)
    }

    @MainActor
    func testCircleStreakCountsAndPopupInLandscape() {
        let app = launchFixture(largestText: false)
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        app.tabBars.buttons["Circle"].tap()
        XCTAssertTrue(app.navigationBars["Circle"].waitForExistence(timeout: 5))
        let streak = badge(app, memberID: "A0000000-0000-0000-0000-000000000001")
        reveal(streak, in: app, page: "Circle")
        assertCounts(streak, overall: 5, timely: 3)
        attachScreen(app, name: "Circle dual positive streaks landscape")
        streak.tap()
        checkPopup(app, overall: 5, timely: 3)
        attachScreen(app, name: "Circle mixed streak popup landscape")
        dismissPopup(app)
        XCTAssertFalse(badge(app, memberID: "A0000000-0000-0000-0000-000000000003").exists)
    }

    @MainActor
    private func launchFixture(largestText: Bool) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["--manna-local-ui-test", "--manna-streak-ui-test",
            "-user.appearancePreference", largestText ? "dark" : "light",
            "-UIPreferredContentSizeCategoryName",
            largestText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func checkMixedStreak(largestText: Bool) {
        let app = launchFixture(largestText: largestText)
        defer { app.terminate() }
        let micah = "A0000000-0000-0000-0000-000000000001"
        let ava = "A0000000-0000-0000-0000-000000000002"
        let ben = "A0000000-0000-0000-0000-000000000003"

        let todayBadge = badge(app, memberID: micah)
        reveal(todayBadge, in: app, page: "Today")
        assertCounts(todayBadge, overall: 5, timely: 3, profile: true)
        todayBadge.tap()
        checkPopup(app, overall: 5, timely: 3)
        attachScreen(app, name: "Today mixed streak popup \(largestText ? "largest dark" : "normal")")
        dismissPopup(app)

        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))
        let timelineBadge = badge(app, memberID: micah)
        XCTAssertTrue(timelineBadge.waitForExistence(timeout: 5))
        assertCounts(timelineBadge, overall: 5, timely: 3, profile: true)
        timelineBadge.tap()
        checkPopup(app, overall: 5, timely: 3)
        attachScreen(app, name: "Timeline mixed streak popup \(largestText ? "largest dark" : "normal")")
        dismissPopup(app)

        app.tabBars.buttons["Circle"].tap()
        XCTAssertTrue(app.navigationBars["Circle"].waitForExistence(timeout: 5))
        let circleBadge = badge(app, memberID: micah)
        reveal(circleBadge, in: app, page: "Circle")
        assertCounts(circleBadge, overall: 5, timely: 3)
        attachScreen(app, name: "Circle dual positive streaks \(largestText ? "largest dark" : "normal")")
        circleBadge.tap()
        checkPopup(app, overall: 5, timely: 3)
        dismissPopup(app)
        let avaBadge = badge(app, memberID: ava)
        reveal(avaBadge, in: app, page: "Circle")
        assertCounts(avaBadge, overall: 1, timely: 0)
        avaBadge.tap()
        checkPopup(app, overall: 1, timely: 0)
        attachScreen(app, name: "Circle general-only streak popup \(largestText ? "largest dark" : "normal")")
        dismissPopup(app)
        XCTAssertFalse(badge(app, memberID: ben).exists, "A member with neither streak has no flame action.")
        attachScreen(app, name: "Circle separate streak counts \(largestText ? "largest dark" : "normal")")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Mixed streak accessibility \(largestText ? "largest dark" : "normal")"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor
    private func badge(_ app: XCUIApplication, memberID: String) -> XCUIElement {
        app.buttons.matching(identifier: "streak.details.\(memberID)").firstMatch
    }

    @MainActor
    private func assertCounts(_ badge: XCUIElement, overall: Int, timely: Int, profile: Bool = false) {
        XCTAssertTrue(badge.exists)
        let value = badge.value as? String ?? ""
        let expected: String
        if profile && overall == timely {
            expected = "Blue flame, \(overall) on time days"
        } else if profile || timely == 0 {
            expected = "Red flame, \(overall) overall days"
        } else {
            expected = "Red flame, \(overall) overall days; Blue flame, \(timely) on time days"
        }
        XCTAssertEqual(value, expected)
        XCTAssertGreaterThanOrEqual(badge.frame.width, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(badge.frame.height, 44 - 0.01)
    }

    @MainActor
    private func checkPopup(_ app: XCUIApplication, overall: Int, timely: Int) {
        let generalLabel = app.staticTexts["\(overall) days in a row"]
        let timelyLabel = app.staticTexts["\(timely) on time days in a row"]
        XCTAssertTrue(generalLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(timelyLabel.exists)
        for label in [generalLabel, timelyLabel] {
            XCTAssertTrue(label.isHittable)
            XCTAssertGreaterThan(label.frame.width, 0)
            XCTAssertGreaterThan(label.frame.height, 0)
            XCTAssertTrue(app.frame.contains(label.frame), "The complete popup text frame must remain on screen.")
        }
        XCTAssertLessThanOrEqual(generalLabel.frame.maxY, timelyLabel.frame.minY,
            "The two streak descriptions must not overlap.")
    }

    @MainActor
    private func dismissPopup(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.11)).tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, page: String) {
        let navigation = app.navigationBars[page]
        XCTAssertTrue(navigation.exists)
        let contentTop = max(app.frame.minY, navigation.frame.maxY) + 4
        let contentBottom = min(app.frame.maxY, app.tabBars.firstMatch.frame.minY) - 4
        let contentHeight = contentBottom - contentTop
        XCTAssertGreaterThan(contentHeight, 44)
        func isVisible() -> Bool {
            element.exists && element.isHittable
                && element.frame.width >= 44 - 0.01 && element.frame.height >= 44 - 0.01
                && element.frame.minY >= contentTop && element.frame.maxY <= contentBottom
                && element.frame.minX >= app.frame.minX && element.frame.maxX <= app.frame.maxX
        }
        for _ in 0..<30 {
            if isVisible() { return }
            let frame = element.exists ? element.frame : .zero
            let delta = frame.height > 0 ? frame.midY - (contentTop + contentBottom) / 2 : contentHeight
            let scrollBack = delta < 0
            let travel = min(contentHeight * 0.32, max(24, abs(delta) * 0.7))
            let startY = contentTop + contentHeight * (scrollBack ? 0.35 : 0.7)
            let endY = min(contentBottom - 12, max(contentTop + 12,
                startY + (scrollBack ? travel : -travel)))
            // Drag the visible page's center, rather than a retained offscreen tab's ScrollView.
            // The held endpoint prevents momentum from skipping a short member row.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: (startY - app.frame.minY) / app.frame.height))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: (endY - app.frame.minY) / app.frame.height)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(isVisible(), "Expected the complete 44-point streak control on \(page): \(element.frame); content \(contentTop)...\(contentBottom); hittable \(element.isHittable)")
    }

    @MainActor
    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
