import XCTest

final class BackendOptimizationUITests: XCTestCase {
    @MainActor
    func testStartupCircleSwitchingAndSubmissionStayIsolated() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["--manna-local-ui-test"]
        app.terminate()
        app.launch()

        let peerBody = "A hard conversation that ended with more understanding."
        let ownBody = "A blessing only for Sunday Table"
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Current circle, Sunday Table"].exists)
        XCTAssertTrue(app.buttons["Share a blessing"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[peerBody].exists)

        switchCircle(app, from: "Sunday Table", to: "Morning Prayer")
        XCTAssertTrue(app.buttons["Share a blessing"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[peerBody].exists)
        switchCircle(app, from: "Morning Prayer", to: "Sunday Table")
        XCTAssertFalse(app.staticTexts[peerBody].exists)

        app.buttons["Share a blessing"].tap()
        let editor = app.textViews["Write your blessing"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(ownBody)
        let send = app.buttons["Send blessing"]
        // The text editor consumes center-screen swipes while its keyboard is open.
        // Drag in the outer scroll view's trailing margin to reach the send action.
        for _ in 0..<6 where !send.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.55))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.2)))
        }
        XCTAssertTrue(send.isHittable)
        send.tap()
        let alert = app.alerts["manna circle"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts[ownBody].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[peerBody].exists)
        XCTAssertFalse(app.buttons["Share a blessing"].exists)

        switchCircle(app, from: "Sunday Table", to: "Morning Prayer")
        XCTAssertTrue(app.buttons["Share a blessing"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[ownBody].exists)
        XCTAssertFalse(app.staticTexts[peerBody].exists)
        switchCircle(app, from: "Morning Prayer", to: "Sunday Table")
        XCTAssertTrue(app.staticTexts[ownBody].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[peerBody].exists)
        XCTAssertFalse(app.buttons["Share a blessing"].exists)
    }

    @MainActor
    private func switchCircle(_ app: XCUIApplication, from current: String, to next: String) {
        app.buttons["Current circle, \(current)"].tap()
        app.buttons[next].tap()
        XCTAssertTrue(app.buttons["Current circle, \(next)"].waitForExistence(timeout: 10))
    }
}
