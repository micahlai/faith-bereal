import XCTest

final class DiagnosticCollectionUITests: XCTestCase {
    @MainActor
    func testFieldTestingScreensAtNormalText() {
        captureFieldTestingScreens(largestText: false)
    }

    @MainActor
    func testFieldTestingScreensAtLargestText() {
        captureFieldTestingScreens(largestText: true)
    }

    @MainActor
    func testFieldBuildDefaultsOnAndRemembersOptOutAcrossRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["--manna-local-ui-test"]
        app.terminate()
        app.launch()

        openDiagnostics(app)
        let consent = app.switches["diagnostics.consent"]
        XCTAssertEqual(consent.value as? String, "1")
        XCTAssertTrue(app.buttons["diagnostics.sendNow"].exists)
        XCTAssertFalse(app.buttons["diagnostics.sendNow"].isEnabled, "Local demo has no remote uploader")
        changeConsent(consent, to: "0")

        app.terminate()
        app.launch()
        openDiagnostics(app)
        XCTAssertEqual(consent.value as? String, "0")
        XCTAssertFalse(app.buttons["diagnostics.sendNow"].exists)
        changeConsent(consent, to: "1")

        app.terminate()
        app.launch()
        openDiagnostics(app)
        XCTAssertEqual(consent.value as? String, "1")
        changeConsent(consent, to: "0")
        XCTAssertFalse(app.buttons["diagnostics.sendNow"].exists)
    }

    @MainActor
    private func openDiagnostics(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.buttons["App menu"].tap()
        app.buttons["User settings"].tap()
        XCTAssertTrue(app.navigationBars["User settings"].waitForExistence(timeout: 5))
        let consent = app.switches["diagnostics.consent"]
        for _ in 0..<10 where !consent.isHittable { app.swipeUp() }
        XCTAssertTrue(consent.isHittable)
    }

    @MainActor
    private func changeConsent(_ element: XCUIElement, to expected: String) {
        // A SwiftUI Form exposes its whole row as a switch; hit its trailing control.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    @MainActor
    private func captureFieldTestingScreens(largestText: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["--manna-local-ui-test"]
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        let share = app.buttons["Share a blessing"]
        for _ in 0..<8 where !share.isHittable { app.swipeUp() }
        XCTAssertTrue(share.isHittable)
        share.tap()
        let editor = app.textViews["Write your blessing"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Grateful for a quiet moment together.")
        let send = app.buttons["Send blessing"]
        for _ in 0..<12 where !send.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.55))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.2)))
        }
        XCTAssertTrue(send.isHittable)
        send.tap()
        let alert = app.alerts["manna circle"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["Grateful for a quiet moment together."].waitForExistence(timeout: 10))
        for _ in 0..<4 { app.swipeDown() }
        let streak = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "day streak in Sunday Table")).firstMatch
        for _ in 0..<8 where !streak.isHittable { app.swipeUp() }
        attachScreen(app, name: "Today blue streak pill", largestText: largestText)

        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))
        attachScreen(app, name: "Timeline default layout", largestText: largestText)
        if largestText {
            app.buttons["Timeline layout"].tap()
            app.buttons["Threads"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "timeline.memberHeader")
                .firstMatch.waitForExistence(timeout: 5))
            attachScreen(app, name: "Timeline Threads blue streak pill", largestText: largestText)
        }

        app.tabBars.buttons["Circle"].tap()
        XCTAssertTrue(app.navigationBars["Circle"].waitForExistence(timeout: 5))
        let people = app.staticTexts["People"]
        for _ in 0..<8 where !people.isHittable { app.swipeUp() }
        XCTAssertTrue(people.isHittable)
        if largestText { app.swipeUp() }
        attachScreen(app, name: "Circle People right side streak pills", largestText: largestText)

        app.tabBars.buttons["Today"].tap()
        openDiagnostics(app)
        attachScreen(app, name: "Diagnostic collection opt-in Form", largestText: largestText)
        XCTAssertEqual(app.switches["diagnostics.consent"].value as? String, "1")
    }

    @MainActor
    private func attachScreen(_ app: XCUIApplication, name: String, largestText: Bool) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(name) — \(largestText ? "largest text" : "normal text")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
