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
        app.launchArguments += ["--manna-local-ui-test", "-user.appearancePreference", "light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.terminate()
        app.launch()

        openDiagnostics(app)
        let consent = app.switches["diagnostics.consent"]
        XCTAssertEqual(consent.value as? String, "1")
        reveal(app.buttons["diagnostics.sendNow"], in: app, requiresHittable: false)
        XCTAssertTrue(app.buttons["diagnostics.sendNow"].exists)
        XCTAssertFalse(app.buttons["diagnostics.sendNow"].isEnabled, "Local demo has no remote uploader")
        changeConsent(consent, in: app, to: "0")

        app.terminate()
        app.launch()
        openDiagnostics(app)
        XCTAssertEqual(consent.value as? String, "0")
        XCTAssertFalse(app.buttons["diagnostics.sendNow"].exists)
        changeConsent(consent, in: app, to: "1")

        app.terminate()
        app.launch()
        openDiagnostics(app)
        XCTAssertEqual(consent.value as? String, "1")
        changeConsent(consent, in: app, to: "0")
        XCTAssertFalse(app.buttons["diagnostics.sendNow"].exists)
    }

    @MainActor
    private func openDiagnostics(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        app.buttons["App menu"].tap()
        app.buttons["User settings"].tap()
        XCTAssertTrue(app.navigationBars["User settings"].waitForExistence(timeout: 5))
        let consent = app.switches["diagnostics.consent"]
        reveal(consent, in: app)
    }

    @MainActor
    private func changeConsent(_ element: XCUIElement, in app: XCUIApplication, to expected: String) {
        reveal(element, in: app)
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
        app.launchArguments += ["--manna-local-ui-test", "-user.appearancePreference", largestText ? "dark" : "light",
            "-UIPreferredContentSizeCategoryName",
            largestText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
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
        // Dismiss the keyboard through the composer's interactive scroll before
        // moving to Send. The outermost screen edge can miss a presented sheet.
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.42))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.82)))
        }
        let send = app.buttons["Send blessing"]
        func sendIsVisible() -> Bool {
            let keyboard = app.keyboards.firstMatch
            let visibleBottom = keyboard.exists ? keyboard.frame.minY : app.frame.maxY
            return send.isHittable && send.frame.maxY <= visibleBottom
        }
        for _ in 0..<15 where !sendIsVisible() {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.47))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.2)))
        }
        XCTAssertTrue(sendIsVisible(), "The whole Send target must be above the software keyboard")
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
        reveal(app.buttons["diagnostics.sendNow"], in: app, requiresHittable: false)
        XCTAssertFalse(app.buttons["diagnostics.sendNow"].isEnabled, "Local fixtures must never upload diagnostics")
        attachScreen(app, name: "Diagnostic collection send controls", largestText: largestText)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, requiresHittable: Bool = true) {
        let navigationBottom = app.navigationBars["User settings"].frame.maxY
        let visibleBottom = app.frame.maxY - 24
        func isVisible() -> Bool {
            element.exists && (!requiresHittable || element.isHittable)
                && element.frame.minY >= navigationBottom && element.frame.maxY <= visibleBottom
        }
        for _ in 0..<30 {
            if isVisible() { return }
            if element.exists {
                let delta = element.frame.midY - (navigationBottom + visibleBottom) / 2
                let needsDownwardScroll = delta < 0
                let travel = min(0.28, max(0.06, abs(delta) / app.frame.height * 0.6))
                let start = needsDownwardScroll ? 0.35 : 0.7
                // Use the Form's content, away from its scroll indicator and
                // trailing switches. Long text rows span several viewports.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
                    .press(forDuration: 0.05, thenDragTo:
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start + (needsDownwardScroll ? travel : -travel))),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
            } else { app.swipeUp() }
        }
        XCTAssertTrue(isVisible(), "Expected the whole control to be visible: \(element.identifier), frame \(element.frame), nav bottom \(navigationBottom), visible bottom \(visibleBottom), hittable \(element.isHittable)")
    }

    @MainActor
    private func attachScreen(_ app: XCUIApplication, name: String, largestText: Bool) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(name) — \(largestText ? "largest text" : "normal text")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
