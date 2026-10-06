import XCTest

final class BlessingCircleUITests: XCTestCase {
    @MainActor
    func testTodayAndPinnedTimelineHeaderInLocalDemo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What feels like a blessing today?"].exists)

        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))

        let memberHeader = app.staticTexts["You"].firstMatch
        XCTAssertTrue(memberHeader.waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(memberHeader.isHittable)
    }

    @MainActor
    func testTodayAtLargestTextInDarkMode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchArguments += [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What feels like a blessing today?"].exists)
        XCTAssertTrue(app.buttons["Share a blessing"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPhotoAttachmentIsAvailableForTextAndVoiceButNotVideo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["Share a blessing"].waitForExistence(timeout: 5))
        app.buttons["Share a blessing"].tap()
        XCTAssertTrue(app.buttons["Take photo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Upload"].exists)

        app.buttons["Speak"].tap()
        XCTAssertTrue(app.buttons["Take photo"].exists)
        XCTAssertTrue(app.buttons["Upload"].exists)

        app.buttons["Video"].tap()
        XCTAssertFalse(app.buttons["Take photo"].exists)
        XCTAssertFalse(app.buttons["Upload"].exists)
    }

    @MainActor
    func testCircleOwnerCanForceLocalBlessingFromCircleSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launch()

        app.tabBars.buttons["Circle"].tap()
        let settingsButton = app.buttons["circle-settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let forceButton = app.buttons["Force blessing notification"]
        XCTAssertTrue(forceButton.waitForExistence(timeout: 3))
        forceButton.tap()
        XCTAssertTrue(app.buttons["Force blessing now"].waitForExistence(timeout: 2))
        app.buttons["Force blessing now"].tap()

        let confirmation = app.alerts["manna circle"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        let activityStatus = confirmation.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Live Activity started.")
        ).firstMatch
        XCTAssertTrue(activityStatus.exists)
        confirmation.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["Share a blessing"].waitForExistence(timeout: 3))
    }

}
