import XCTest

final class PrivacyUITests: XCTestCase {
    @MainActor func testFirstLaunchRequiresAgeAndSharingAndKeepsDiagnosticsOff() {
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["--manna-local-ui-test", "--manna-privacy-ui-test", "--manna-reset-privacy"]
        app.launch()
        defer { app.terminate(); app.launchArguments = [] }
        XCTAssertTrue(app.navigationBars["Before you begin"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["privacy.age"].value as? String, "0")
        XCTAssertEqual(app.switches["privacy.sharing"].value as? String, "0")
        for _ in 0..<6 where !app.switches["privacy.diagnostics"].isHittable { app.swipeUp() }
        XCTAssertEqual(app.switches["privacy.diagnostics"].value as? String, "0")
        for _ in 0..<10 where !app.buttons["privacy.continue"].isHittable { app.swipeUp() }
        XCTAssertFalse(app.buttons["privacy.continue"].isEnabled)
        for _ in 0..<10 where !app.switches["privacy.age"].isHittable { app.swipeDown() }
        app.switches["privacy.age"].coordinate(withNormalizedOffset: CGVector(dx: 0.9,dy: 0.5)).tap()
        app.buttons["Read privacy policy"].tap()
        XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Who we are"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Privacy policy"; attachment.lifetime = .keepAlways; add(attachment)
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 where !app.switches["privacy.sharing"].isHittable { app.swipeUp() }
        app.switches["privacy.sharing"].coordinate(withNormalizedOffset: CGVector(dx: 0.9,dy: 0.5)).tap()
        for _ in 0..<12 where !app.buttons["privacy.continue"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["privacy.continue"].isEnabled)
        app.buttons["privacy.continue"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
    }
}
