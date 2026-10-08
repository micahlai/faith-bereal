import XCTest

final class BlessingCircleUITests: XCTestCase {
    @MainActor
    func testStartupOnboardingSupportsBackNavigationAndWidgetGuide() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchArguments += [
            "-onboarding.hasSeenAbout", "NO",
            "-onboarding.hasChosenAppearance", "NO",
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Step 1 of 4"].exists)
        XCTAssertTrue(app.staticTexts["circle"].exists)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Back"].exists)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 3))

        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["App icon"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding-icon-automatic"].exists)
        XCTAssertTrue(app.buttons["onboarding-icon-cream"].exists)
        XCTAssertTrue(app.buttons["onboarding-icon-midnight"].exists)
        let continueButton = app.buttons["Continue"]
        XCTAssertGreaterThan(continueButton.frame.midX, app.frame.width * 0.7)
        XCTAssertLessThan(app.buttons["Back"].frame.midX, app.frame.width * 0.3)
        XCTAssertEqual(continueButton.frame.midY, app.buttons["Back"].frame.midY, accuracy: 2)
        let onboardingLayout = XCTAttachment(screenshot: app.screenshot())
        onboardingLayout.name = "App icon page with corner-aligned navigation"
        onboardingLayout.lifetime = .keepAlways
        add(onboardingLayout)

        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Widget"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Add manna to your Home Screen"].exists)
        XCTAssertTrue(app.staticTexts["Search for “manna circle,” choose a size, and add it."].exists)
        XCTAssertTrue(app.buttons["Back"].exists)

        app.buttons["Continue"].tap()
        XCTAssertFalse(app.navigationBars["Widget"].exists)
    }

    @MainActor
    func testTodayAndPinnedTimelineHeaderInLocalDemo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What feels like a blessing today?"].exists)

        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))

        let memberHeader = app.staticTexts["You"].firstMatch
        XCTAssertTrue(memberHeader.waitForExistence(timeout: 3))
        let frozenHeader = app.descendants(matching: .any)
            .matching(identifier: "timeline.memberHeader").firstMatch
        XCTAssertTrue(frozenHeader.waitForExistence(timeout: 3))
        let initialHeaderY = frozenHeader.frame.minY
        XCTAssertLessThanOrEqual(initialHeaderY - app.navigationBars["Timeline"].frame.maxY, 10)
        XCTAssertLessThan(memberHeader.frame.maxY - app.navigationBars["Timeline"].frame.maxY, 140)
        let initialTimeline = XCTAttachment(screenshot: app.screenshot())
        initialTimeline.name = "Compact fixed timeline header"
        initialTimeline.lifetime = .keepAlways
        add(initialTimeline)

        let dayColumn = app.descendants(matching: .any)
            .matching(identifier: "timeline.dayColumn")
            .firstMatch
        XCTAssertTrue(dayColumn.waitForExistence(timeout: 3))
        let initialDayColumnX = dayColumn.frame.minX
        app.swipeLeft()
        XCTAssertEqual(dayColumn.frame.minX, initialDayColumnX, accuracy: 2)

        // Member lanes intentionally scroll horizontally; restore You before
        // checking that its header remains visible during vertical scrolling.
        app.swipeRight()
        app.swipeUp()
        XCTAssertTrue(memberHeader.isHittable)
        XCTAssertEqual(frozenHeader.frame.minY, initialHeaderY, accuracy: 2)
        let scrolledTimeline = XCTAttachment(screenshot: app.screenshot())
        scrolledTimeline.name = "Timeline content below fixed header and date strip"
        scrolledTimeline.lifetime = .keepAlways
        add(scrolledTimeline)
    }

    @MainActor
    func testTodayBottomRemainsStableAcrossClockTicksAndRepeatedScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["Share a blessing"].waitForExistence(timeout: 5))
        app.buttons["Share a blessing"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText(String(repeating: "Thankful for the people who helped me today. ", count: 12))
        app.swipeUp()
        app.buttons["Send blessing"].tap()
        XCTAssertTrue(app.staticTexts["Today’s circle"].waitForExistence(timeout: 5))

        let scrollView = app.scrollViews["today.scrollView"]
        for _ in 0..<3 { scrollView.swipeUp() }
        let bottomComposer = app.textFields.matching(identifier: "Text response").element(boundBy: 1)
        XCTAssertTrue(bottomComposer.waitForExistence(timeout: 5))
        XCTAssertTrue(bottomComposer.isHittable)
        let initialY = bottomComposer.frame.minY
        // Multiple one-second timer updates must not change the resting bottom
        // position; a predicate also catches oscillation between sample frames.
        var samples = 0
        var maximumDrift: CGFloat = 0
        let stable = NSPredicate { _, _ in
            maximumDrift = max(maximumDrift, abs(bottomComposer.frame.minY - initialY))
            samples += 1
            return samples >= 5
        }
        expectation(for: stable, evaluatedWith: nil)
        waitForExpectations(timeout: 12)
        XCTAssertLessThanOrEqual(maximumDrift, 2)

        bottomComposer.tap()
        bottomComposer.typeText("Keep this response draft")
        scrollView.swipeDown()
        scrollView.swipeDown()
        scrollView.swipeUp()
        scrollView.swipeUp()
        XCTAssertEqual(bottomComposer.value as? String, "Keep this response draft")
        XCTAssertFalse(app.alerts["manna circle"].exists)
    }

    @MainActor
    func testTodayAtLargestTextInDarkMode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
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
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
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
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
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

    @MainActor
    func testCircleCreationCollectsSettingsBeforeSubmitting() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launch()

        app.tabBars.buttons["Circle"].tap()
        XCTAssertTrue(app.buttons["Create a circle"].waitForExistence(timeout: 5))
        app.buttons["Create a circle"].tap()

        XCTAssertTrue(app.navigationBars["New circle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Circle photo"].exists)
        XCTAssertTrue(app.buttons["Choose circle photo"].exists)
        XCTAssertTrue(app.textFields["Circle name"].exists)
        XCTAssertTrue(app.staticTexts["Random blessing time"].exists)
        XCTAssertTrue(app.staticTexts["Response window"].exists)
        let allowLate = app.switches["Allow late blessings"]
        for _ in 0..<3 where !allowLate.isHittable { app.swipeUp() }
        XCTAssertTrue(allowLate.waitForExistence(timeout: 2))
        XCTAssertEqual(allowLate.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Reuse window"].exists)
        let create = app.buttons["Create circle"]
        for _ in 0..<3 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.waitForExistence(timeout: 2))
    }

    @MainActor
    func testHelpMenuExplainsSavingAndSupportsTopicNavigation() {
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["App menu"].waitForExistence(timeout: 5))
        app.buttons["App menu"].tap()
        app.buttons["Help"].tap()
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 3))
        let saving = app.buttons["help-topic-saving"]
        for _ in 0..<3 where !saving.isHittable { app.swipeUp() }
        saving.tap()
        XCTAssertTrue(app.navigationBars["Saving & media expiry"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1. 14 days for hosted media"].exists)
        let guide = XCTAttachment(screenshot: app.screenshot())
        guide.name = "Saving help topic"
        guide.lifetime = .keepAlways
        add(guide)
        app.buttons["Jump to help topic"].tap()
        app.buttons["Your circles"].tap()
        XCTAssertTrue(app.navigationBars["Your circles"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFirstSaveExplainsPrivateStorageAndCanUnsaveFromDetail() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchArguments += ["-saving.explained.A0000000-0000-0000-0000-000000000001", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Timeline"].tap()
        let blessing = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A quiet walk before the rain.")).firstMatch
        for _ in 0..<3 where !blessing.isHittable { app.swipeUp() }
        XCTAssertTrue(blessing.waitForExistence(timeout: 3))
        blessing.tap()
        let save = app.buttons["Save blessing"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        let explanation = app.alerts["Save this blessing on your device?"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 3))
        XCTAssertTrue(explanation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Only you can use this copy")).firstMatch.exists)
        explanation.buttons["Save blessing"].tap()
        let unsave = app.buttons["Unsave blessing"]
        XCTAssertTrue(unsave.waitForExistence(timeout: 5))
        unsave.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 3))
    }

    @MainActor
    func testCircleOwnerCanRegenerateInviteCode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launch()

        app.tabBars.buttons["Circle"].tap()
        let settingsButton = app.buttons["circle-settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let regenerate = app.buttons["Regenerate invite code"]
        XCTAssertTrue(regenerate.waitForExistence(timeout: 3))
        regenerate.tap()
        XCTAssertTrue(app.buttons["Regenerate code"].waitForExistence(timeout: 2))
        app.buttons["Regenerate code"].tap()

        let confirmation = app.alerts["manna circle"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        let successMessage = confirmation.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "new circle code")
        ).firstMatch
        XCTAssertTrue(successMessage.exists)
        confirmation.buttons["OK"].tap()
    }

    @MainActor
    func testCircleSettingsConfirmsBeforeDiscardingChanges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Circle"].tap()
        let settingsButton = app.buttons["circle-settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3))
        let nameField = app.textFields["Circle name"]
        XCTAssertTrue(nameField.exists)
        nameField.tap()
        nameField.typeText(" updated")
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Keep Editing"].exists)
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
    }

}
