import XCTest

final class CachedLoadingUITests: XCTestCase {
    @MainActor
    func testCachedCircleShellKeepsTabsUsableWhileBlessingsLoad() {
        checkCachedLoading(largestText: false)
    }

    @MainActor
    func testCachedCircleLoadingAtLargestTextInDarkMode() {
        checkCachedLoading(largestText: true)
    }

    @MainActor
    private func checkCachedLoading(largestText: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["--manna-local-ui-test", "--manna-loading-ui-test",
            "-user.appearancePreference", largestText ? "dark" : "light",
            "-UIPreferredContentSizeCategoryName",
            largestText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.terminate()
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Current circle, Sunday Table"].exists)
        assertLoadingState(app)
        XCTAssertFalse(app.staticTexts["Wait for today’s blessing notification"].exists)
        assertNoBlessingContent(app)
        attachScreen(app, name: "Cached Today loading \(largestText ? "largest dark" : "normal")")

        let circleTab = app.tabBars.buttons["Circle"]
        XCTAssertTrue(circleTab.isHittable)
        circleTab.tap()
        XCTAssertTrue(app.navigationBars["Circle"].waitForExistence(timeout: 5))
        let settings = app.buttons["circle-settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertFalse(settings.isEnabled, "Cached membership cannot authorize settings changes")
        let share = app.buttons["Share join link"]
        XCTAssertTrue(share.exists)
        XCTAssertFalse(share.isEnabled, "A cached invitation cannot be shared before validation")
        XCTAssertFalse(app.buttons["Join another circle"].isEnabled)
        XCTAssertFalse(app.buttons["Create a circle"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "circle.pageStatus").firstMatch.exists)
        attachScreen(app, name: "Cached Circle identity and disabled changes \(largestText ? "largest dark" : "normal")")

        let streak = app.buttons["streak.details.A0000000-0000-0000-0000-000000000001"]
        reveal(streak, in: app)
        XCTAssertTrue(streak.isHittable, "Saved streak metadata should appear with the cached people")
        XCTAssertTrue(app.staticTexts["Micah (you)"].exists)
        XCTAssertTrue(app.staticTexts["Ava"].exists)
        XCTAssertTrue(app.staticTexts["Ben"].exists)
        assertNoBlessingContent(app)
        attachScreen(app, name: "Cached circle people and streak \(largestText ? "largest dark" : "normal")")

        let timelineTab = app.tabBars.buttons["Timeline"]
        XCTAssertTrue(timelineTab.isHittable)
        timelineTab.tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))
        assertLoadingState(app)
        XCTAssertFalse(app.staticTexts["No days yet"].exists, "Loading is distinct from an empty history")
        assertNoBlessingContent(app)
        attachScreen(app, name: "Cached Timeline loading \(largestText ? "largest dark" : "normal")")

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        assertLoadingState(app)
        assertNoBlessingContent(app)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let top = app.navigationBars["Circle"].frame.maxY + 4
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
            // Small held drags can reverse after passing a short row at large text sizes.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start / app.frame.height))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end / app.frame.height)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    @MainActor
    private func assertLoadingState(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "circle.pageStatus")
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "circle.blessingsLoading")
            .firstMatch.waitForExistence(timeout: 5))
        let loadingLabel = app.staticTexts["Loading circle…"]
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: loadingLabel)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed,
            "The loading text must be visibly on screen before capturing it")
        XCTAssertGreaterThan(loadingLabel.frame.width, 0)
        XCTAssertGreaterThan(loadingLabel.frame.height, 0)
        XCTAssertGreaterThanOrEqual(loadingLabel.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(loadingLabel.frame.maxY, app.tabBars.firstMatch.frame.minY)
        XCTAssertFalse(app.buttons["circle.pageRetry"].exists, "An active load must not offer a second concurrent retry")
    }

    @MainActor
    private func assertNoBlessingContent(_ app: XCUIApplication) {
        for body in ["A hard conversation that ended with more understanding.", "A quiet walk before the rain.",
                     "A friend who called at exactly the right time.", "Dinner around the same table."] {
            XCTAssertFalse(app.staticTexts[body].exists, "Cached presentation must not restore old blessing content")
        }
        XCTAssertFalse(app.buttons["Share a blessing"].exists)
        XCTAssertFalse(app.buttons["Share end-of-day blessing"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "blessing.photo").firstMatch.exists)
    }

    @MainActor
    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
