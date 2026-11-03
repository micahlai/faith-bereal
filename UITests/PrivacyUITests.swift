import XCTest

final class PrivacyUITests: XCTestCase {
    @MainActor func testPrivacyFollowsLogoBeforeAccountSetupWithRequiredConsent() {
        verifyPrivacy(largest: false)
    }
    @MainActor func testPrivacyUsesOnboardingCardsAtLargestDarkText() {
        verifyPrivacy(largest: true)
    }
    @MainActor private func verifyPrivacy(largest: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["--manna-local-ui-test", "--manna-privacy-ui-test", "--manna-reset-privacy",
            "-onboarding.hasSeenAbout", "NO", "-onboarding.hasChosenAppearance", "NO",
            "-user.appearancePreference", largest ? "dark" : "light",
            "-UIPreferredContentSizeCategoryName", largest ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        defer { app.terminate(); app.launchArguments = [] }
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["Before you begin"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 3))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["App icon"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding-icon-automatic"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Your privacy"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Edit name and photo"].exists)
        XCTAssertFalse(app.tabBars.buttons["Today"].exists)
        XCTAssertFalse(app.buttons["privacy.continue"].isEnabled)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.navigationBars["App icon"].waitForExistence(timeout: 3))
        app.buttons["Continue"].tap()
        let age = app.switches["privacy.age"]
        scrollIntoView(age, in: app)
        XCTAssertEqual(age.value as? String, "0")
        age.coordinate(withNormalizedOffset: CGVector(dx: 0.9,dy: 0.5)).tap()
        XCTAssertEqual(age.value as? String, "1")
        XCTAssertFalse(app.buttons["privacy.continue"].isEnabled)
        let policy = app.buttons["Read privacy policy"]
        scrollIntoView(policy, in: app)
        policy.tap()
        XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let sharing = app.switches["privacy.sharing"]
        scrollIntoView(sharing, in: app)
        sharing.coordinate(withNormalizedOffset: CGVector(dx: 0.9,dy: 0.5)).tap()
        XCTAssertEqual(sharing.value as? String, "1")
        let diagnostics = app.switches["privacy.diagnostics"]
        scrollIntoView(diagnostics, in: app)
        XCTAssertEqual(diagnostics.value as? String, "0")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = largest ? "Privacy onboarding largest dark" : "Privacy onboarding cards"
        attachment.lifetime = .keepAlways; add(attachment)
        let proceed = app.buttons["privacy.continue"]
        XCTAssertTrue(proceed.isEnabled)
        XCTAssertGreaterThanOrEqual(proceed.frame.height, 44)
        XCTAssertLessThanOrEqual(proceed.frame.maxX, app.frame.width)
        XCTAssertGreaterThanOrEqual(proceed.frame.minX, 0)
        proceed.tap()
        XCTAssertTrue(app.navigationBars["Your profile"].waitForExistence(timeout: 15))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Local saving"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Widget"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["--manna-local-ui-test", "--manna-privacy-ui-test",
            "-user.appearancePreference", largest ? "dark" : "light",
            "-UIPreferredContentSizeCategoryName", largest ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
    }

    @MainActor private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        // SwiftUI may report an offscreen control as hittable because a normal
        // tap can auto-scroll. Coordinate taps need its actual visible frame.
        for _ in 0..<40 {
            var viewport = scroll.frame.insetBy(dx: 0, dy: 8)
            let footerTop = min(app.buttons["Back"].frame.minY, app.buttons["privacy.continue"].frame.minY)
            viewport.size.height = max(0, min(viewport.maxY, footerTop - 12) - viewport.minY)
            let frame = element.frame
            if viewport.contains(frame), element.isHittable { return }
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            let top = origin.withOffset(CGVector(dx: viewport.midX - scroll.frame.minX, dy: viewport.minY - scroll.frame.minY + 20))
            let bottom = origin.withOffset(CGVector(dx: viewport.midX - scroll.frame.minX, dy: viewport.maxY - scroll.frame.minY - 20))
            if frame.minY < viewport.minY { top.press(forDuration: 0.05, thenDragTo: bottom) }
            else { bottom.press(forDuration: 0.05, thenDragTo: top) }
        }
        XCTFail("Could not scroll \(element.identifier) fully into view")
    }
}
