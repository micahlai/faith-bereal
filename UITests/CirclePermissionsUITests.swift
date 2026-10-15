import XCTest

final class CirclePermissionsUITests: XCTestCase {
    @MainActor
    func testOwnerCanEnableAndDisableMemberChangesWithoutSavingOtherSettings() {
        checkOwnerPermissions(largestText: false)
    }

    @MainActor
    func testOwnerPermissionsAtLargestTextInDarkMode() {
        checkOwnerPermissions(largestText: true)
    }

    @MainActor
    func testMemberSettingsAreReadOnlyWhenSharingIsOff() {
        let app = launchSettings(role: "member")
        XCTAssertFalse(app.switches["circle-settings-member-changes"].exists)
        XCTAssertFalse(app.textFields["circle-settings-name"].exists)
        XCTAssertFalse(app.buttons["Save"].exists)
        XCTAssertFalse(app.buttons["regenerate-invite-code"].exists)
        XCTAssertFalse(app.buttons["force-blessing-notification"].exists)
        XCTAssertFalse(app.buttons["circle-settings-transfer-ownership"].exists)
        XCTAssertTrue(app.buttons["Leave circle"].exists)
        attachScreen(app, name: "Member read-only circle settings")
    }

    @MainActor
    func testMemberCanSaveSharedSettingsButCannotChangePermissionsOrRemoveOwner() {
        let app = launchSettings(role: "member_shared")
        XCTAssertFalse(app.switches["circle-settings-member-changes"].exists)
        let name = app.textFields["circle-settings-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" Updated")
        let expectedName = name.value as? String ?? ""
        XCTAssertTrue(expectedName.contains("Updated"))
        let save = app.buttons["Save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        dismissSuccessAlert(app)
        XCTAssertTrue(app.navigationBars["Circle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[expectedName].exists)
        app.buttons["circle-settings-button"].tap()
        XCTAssertTrue(app.navigationBars["Circle settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["circle-settings-name"].value as? String, expectedName)
        attachScreen(app, name: "Member editable circle settings")

        var sawCodeRotation = false
        var sawForceNotification = false
        let removeBen = app.buttons["circle-settings-remove-A0000000-0000-0000-0000-000000000003"]
        for _ in 0..<18 {
            XCTAssertFalse(app.switches["circle-settings-member-changes"].exists)
            XCTAssertFalse(app.buttons["circle-settings-transfer-ownership"].exists)
            XCTAssertFalse(app.buttons["circle-settings-remove-A0000000-0000-0000-0000-000000000002"].exists)
            XCTAssertFalse(app.buttons["circle-settings-remove-A0000000-0000-0000-0000-000000000001"].exists)
            sawCodeRotation = sawCodeRotation || app.buttons["regenerate-invite-code"].isHittable
            sawForceNotification = sawForceNotification || app.buttons["force-blessing-notification"].isHittable
            if removeBen.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(sawCodeRotation)
        XCTAssertTrue(sawForceNotification)
        XCTAssertTrue(removeBen.isHittable)
        XCTAssertTrue(app.buttons["Leave circle"].exists)
        attachScreen(app, name: "Member management without owner removal or transfer")
    }

    @MainActor
    private func checkOwnerPermissions(largestText: Bool) {
        let app = launchSettings(role: "owner", largestText: largestText)
        let permission = app.switches["circle-settings-member-changes"]
        XCTAssertTrue(permission.waitForExistence(timeout: 5))
        XCTAssertEqual(permission.value as? String, "0")
        XCTAssertGreaterThanOrEqual(permission.frame.height, 44 - 0.01)
        permission.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForValue(permission, value: "1")
        XCTAssertTrue(app.navigationBars["Circle settings"].exists)
        XCTAssertFalse(app.alerts["manna circle"].exists)
        attachScreen(app, name: "Owner circle permissions \(largestText ? "largest dark" : "normal")")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Circle"].waitForExistence(timeout: 5))
        app.buttons["circle-settings-button"].tap()
        XCTAssertTrue(permission.waitForExistence(timeout: 5))
        XCTAssertEqual(permission.value as? String, "1")
        permission.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForValue(permission, value: "0")
        XCTAssertTrue(app.navigationBars["Circle settings"].exists)
    }

    @MainActor
    private func launchSettings(role: String, largestText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["MANNA_CIRCLE_SETTINGS_TEST_ROLE"] = role
        app.launchArguments += ["--manna-local-ui-test", "-user.appearancePreference",
            largestText ? "dark" : "light", "-UIPreferredContentSizeCategoryName",
            largestText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Circle"].tap()
        let settings = app.buttons["circle-settings-button"]
        for _ in 0..<8 where !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Circle settings"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func dismissSuccessAlert(_ app: XCUIApplication) {
        let alert = app.alerts["manna circle"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["OK"].tap()
    }

    @MainActor
    private func waitForValue(_ control: XCUIElement, value: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ AND enabled == true", value), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor
    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
