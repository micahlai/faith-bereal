import XCTest

final class SavingMenuUITests: XCTestCase {
    @MainActor func testReviewCardsPreviewPhotoVoiceVideoAndResponse() throws {
        try review(largest: false)
    }

    @MainActor func testReviewCardsAtLargestDarkText() throws {
        try review(largest: true)
    }

    @MainActor private func application(largest: Bool = false, savingOff: Bool = true) throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "save-preview", withExtension: "mp4"))
        app.launchEnvironment["MANNA_SAVE_PREVIEW_VIDEO"] = try Data(contentsOf: video).base64EncodedString()
        app.launchArguments = [
            "--manna-local-ui-test", "--manna-retention-ui-test", "--manna-save-menu-ui-test",
            "--manna-skip-onboarding",
            "-user.appearancePreference", largest ? "dark" : "light",
            "-UIPreferredContentSizeCategoryName",
            largest ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
        ]
        if savingOff { app.launchArguments.append("--manna-retention-saving-off") }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 30))
        return app
    }

    @MainActor private func review(largest: Bool) throws {
        let app = try application(largest: largest)
        defer { app.terminate() }
        app.tabBars.buttons["Timeline"].tap()
        let banner = app.buttons["retention.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        banner.tap()
        XCTAssertTrue(app.navigationBars["Save before removal"].waitForExistence(timeout: 5))
        let photo = app.buttons["saving.preview.photo"]
        reveal(photo, app: app)
        photo.tap()
        XCTAssertTrue(app.buttons["photo.close"].waitForExistence(timeout: 5))
        app.buttons["photo.close"].tap()
        let audio = app.buttons["Play recording"].firstMatch
        reveal(audio, app: app)
        XCTAssertGreaterThanOrEqual(audio.frame.height, 44)
        let position = app.sliders["Recording position"].firstMatch
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        let video = app.buttons["Play video"].firstMatch
        reveal(video, app: app, towardTop: true)
        capture(app, name: largest ? "Save cards largest dark video" : "Save cards video preview")
        let fullScreen = app.buttons["Open video full screen"].firstMatch
        XCTAssertTrue(fullScreen.exists)
        let response = app.staticTexts["Voice response · You"].firstMatch
        reveal(response, app: app)
        XCTAssertTrue(response.isHittable)
        capture(app, name: largest ? "Save cards largest dark response" : "Save cards voice response")
        let saveAll = app.buttons["retention.saveAll"]
        XCTAssertTrue(saveAll.isHittable, "Save all stays pinned while previewing cards")
        saveAll.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: saveAll)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 15), .completed)
        let empty = app.staticTexts["No unsaved recordings are due within 3 days in your accessible circles."]
        reveal(empty, app: app, towardTop: true, allowPartial: true)
        XCTAssertTrue(empty.exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(banner.exists, "No removal reminder remains after all due recordings are saved")
    }

    @MainActor func testKeepCopiesUsesPreviewCardsAndCancelPreservesAutomaticSaving() throws {
        let app = try application(savingOff: false)
        defer { app.terminate() }
        app.buttons["App menu"].tap()
        app.buttons["User settings"].tap()
        let automatic = app.switches["saving.automaticToggle"]
        for _ in 0..<10 where !automatic.isHittable { app.swipeUp() }
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Saved copies"].waitForExistence(timeout: 5))
        let selected = app.buttons["saving.keep.selected"]
        reveal(selected, app: app)
        selected.tap()
        let photo = app.buttons["saving.preview.photo"].firstMatch
        reveal(photo, app: app)
        XCTAssertTrue(photo.isHittable)
        let keep = app.buttons["Keep on this device"].firstMatch
        reveal(keep, app: app)
        keep.tap()
        XCTAssertTrue(app.buttons["Remove from this device"].firstMatch.exists)
        reveal(photo, app: app)
        photo.tap()
        XCTAssertTrue(app.buttons["photo.close"].waitForExistence(timeout: 5))
        app.buttons["photo.close"].tap()
        let removed = app.buttons["Remove from this device"].firstMatch
        reveal(removed, app: app, towardTop: true)
        XCTAssertTrue(removed.exists, "Previewing must preserve the keep selection")
        capture(app, name: "Custom saved copy selection with media")
        app.buttons["Cancel"].tap()
        XCTAssertEqual(automatic.value as? String, "1")
    }

    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false, allowPartial: Bool = false) {
        let isKeep = app.navigationBars["Saved copies"].exists
        let scroll = app.scrollViews[isKeep ? "saving.keep.scroll" : "saving.review.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let bar = app.navigationBars[isKeep ? "Saved copies" : "Save before removal"]
        for _ in 0..<60 {
            var viewport = scroll.frame.insetBy(dx: 0, dy: 20)
            let saveAll = app.buttons["retention.saveAll"]
            let bottomY = saveAll.exists ? min(viewport.maxY, saveAll.frame.minY - 16) : viewport.maxY
            viewport.origin.y = max(viewport.minY, bar.frame.maxY + 12)
            viewport.size.height = bottomY - viewport.minY
            let frame = element.exists ? element.frame : nil
            if let frame, viewport.contains(frame) || (allowPartial && viewport.intersects(frame)), element.isHittable { return }
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            let top = origin.withOffset(
                CGVector(dx: viewport.midX - scroll.frame.minX, dy: viewport.minY - scroll.frame.minY + 25))
            let bottom = origin.withOffset(
                CGVector(dx: viewport.midX - scroll.frame.minX, dy: viewport.maxY - scroll.frame.minY - 25))
            if frame.map({ $0.minY < viewport.minY }) ?? towardTop {
                top.press(forDuration: 0.05, thenDragTo: bottom)
            } else {
                bottom.press(forDuration: 0.05, thenDragTo: top)
            }
        }
        XCTFail("Could not reveal \(element.identifier)")
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
