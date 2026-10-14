import XCTest

final class PhotoViewerUITests: XCTestCase {
    @MainActor
    func testTodayPhotoZoomAndHorizontalStability() {
        checkTodayAndPhoto(largestText: false)
    }

    @MainActor
    func testPhotoViewerAtLargestTextInDarkMode() {
        checkTodayAndPhoto(largestText: true)
    }

    @MainActor
    func testCircleAndMemberPhotosOpenWithoutReplacingSettingsActions() {
        let app = launchPhotoFixture()
        app.tabBars.buttons["Circle"].tap()
        XCTAssertTrue(app.navigationBars["Circle"].waitForExistence(timeout: 5))
        let circlePhoto = app.buttons["Sunday Table circle photo"]
        XCTAssertTrue(circlePhoto.waitForExistence(timeout: 5))
        circlePhoto.tap()
        checkViewer(app)
        app.buttons["photo.close"].tap()
        XCTAssertTrue(app.buttons["circle-settings-button"].isHittable)
        let avatar = app.buttons["Ava profile photo"]
        for _ in 0..<8 where !avatar.isHittable { app.swipeUp() }
        XCTAssertTrue(avatar.isHittable)
        avatar.tap()
        checkViewer(app)
        app.buttons["photo.close"].tap()
        XCTAssertTrue(app.navigationBars["Circle"].exists)
    }

    @MainActor
    private func launchPhotoFixture(largestText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["--manna-local-ui-test", "--manna-photo-ui-test"]
        if largestText {
            app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func checkTodayAndPhoto(largestText: Bool) {
        let app = launchPhotoFixture(largestText: largestText)
        let scroll = app.scrollViews["today.scrollView"]
        let heading = app.staticTexts["What feels like a blessing today?"]
        let originalX = heading.frame.minX
        scroll.swipeLeft()
        XCTAssertEqual(heading.frame.minX, originalX, accuracy: 1)
        scroll.swipeRight()
        XCTAssertEqual(heading.frame.minX, originalX, accuracy: 1)
        // Peer photos stay locked before the viewer submits for this prompt.
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "blessing.photo").firstMatch.exists)
        let share = app.buttons["Share a blessing"]
        for _ in 0..<10 where !share.isHittable { scroll.swipeUp() }
        XCTAssertTrue(share.isHittable)
        share.tap()
        let editor = app.textViews["Write your blessing"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Photo viewer acceptance")
        let send = app.buttons["Send blessing"]
        for _ in 0..<15 where !send.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.55))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.2)))
        }
        XCTAssertTrue(send.isHittable)
        send.tap()
        let alert = app.alerts["manna circle"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        let photo = app.descendants(matching: .any).matching(identifier: "blessing.photo").firstMatch
        for _ in 0..<15 where !photo.isHittable { scroll.swipeUp() }
        XCTAssertTrue(photo.isHittable)
        photo.tap()
        checkViewer(app)
        let image = app.descendants(matching: .any).matching(identifier: "photo.zoomImage").firstMatch
        waitForZoom(image, contains: "100")
        app.buttons["Zoom in"].tap()
        waitForZoom(image, contains: "150")
        attachScreen(app, name: "Photo enlarged \(largestText ? "largest dark" : "normal")")
        app.buttons["Zoom out"].tap()
        waitForZoom(image, contains: "100")
        image.pinch(withScale: 2, velocity: 1)
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = image.value as? String ?? ""
            return !value.isEmpty && !value.hasPrefix("100 ")
        }, object: image)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)
        image.doubleTap()
        waitForZoom(image, contains: "100")
        app.buttons["photo.close"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["photo.close"].exists)
        attachScreen(app, name: "Today photo feed \(largestText ? "largest dark" : "normal")")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Today photo and streak accessibility \(largestText ? "largest dark" : "normal")"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor
    private func checkViewer(_ app: XCUIApplication) {
        let image = app.descendants(matching: .any).matching(identifier: "photo.zoomImage").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        for label in ["photo.close", "Zoom in", "Zoom out", "Reset", "Move photo"] {
            XCTAssertTrue(app.buttons[label].exists, label)
            XCTAssertGreaterThanOrEqual(app.buttons[label].frame.height, 44 - 0.01, label)
            XCTAssertLessThanOrEqual(app.buttons[label].frame.maxX, app.frame.width, label)
        }
    }

    @MainActor
    private func waitForZoom(_ image: XCUIElement, contains text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: image)
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
