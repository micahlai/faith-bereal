import XCTest

final class BibleReleaseUITests: XCTestCase {
    @MainActor func testPublicDomainPassageCreditAndReferenceTag() throws { try verifyBibleRelease(largest: false) }
    @MainActor func testPublicDomainPassageCreditAtLargestDarkText() throws { try verifyBibleRelease(largest: true) }

    @MainActor private func verifyBibleRelease(largest: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["BLESSING_CIRCLE_FORCE_LOCAL": "1", "BLESSING_CIRCLE_SKIP_ONBOARDING": "1",
            "BLESSING_CIRCLE_SAVING_TEST_SESSION": UUID().uuidString]
        app.launchArguments = ["--manna-local-ui-test", "--manna-bible-ui-test", "--manna-skip-onboarding",
            "-user.appearancePreference", largest ? "dark" : "light",
            "-UIPreferredContentSizeCategoryName", largest ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch(); defer { app.terminate() }
        let share = app.buttons["Share a blessing"]
        XCTAssertTrue(share.waitForExistence(timeout: 25)); share.tap()
        let choose = app.buttons["Choose a verse"]
        reveal(choose, in: app); choose.tap()
        XCTAssertTrue(app.navigationBars["Tag a Bible verse"].waitForExistence(timeout: 15))
        let credit = app.staticTexts["bible.providerCredit"]
        reveal(credit, in: app)
        XCTAssertTrue(credit.label.contains("Synthetic WEB credit. Public Domain."))
        XCTAssertTrue(credit.label.contains("Text via Midvash."))
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = largest ? "Bible credit largest dark" : "Bible credit normal"
        proof.lifetime = .keepAlways; add(proof)
        let tag = app.buttons["Tag John 3:16"]
        reveal(tag, in: app); XCTAssertGreaterThanOrEqual(tag.frame.height, 44); tag.tap()
        XCTAssertTrue(app.staticTexts["John 3:16"].firstMatch.waitForExistence(timeout: 15))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = largest ? "Bible tag largest dark" : "Bible tag normal"
        capture.lifetime = .keepAlways; add(capture)
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for attempt in 0..<35 {
            let top = app.navigationBars.firstMatch.frame.maxY + 4
            let bottom = app.frame.maxY - 35
            // Large-text Form sections can be absent from the hierarchy until
            // scrolled into view. Absence is not a visibility pass.
            let exists = element.exists
            let f = exists ? element.frame : .zero
            let hittable = exists && element.isHittable
            if exists && !f.isEmpty && hittable && f.minY >= top && f.maxY <= bottom { return }
            let anchor = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.55))
            let delta: CGFloat = !f.isEmpty && f.midY < top ? 110 : -110
            anchor.press(forDuration: 0.05, thenDragTo: anchor.withOffset(CGVector(dx: 0, dy: delta)))
        }
        XCTFail("Could not fully reveal the target control")
    }
}
