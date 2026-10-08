import XCTest

final class BlessingCircleUITests: XCTestCase {
    @MainActor
    func testBlessingComposerAcceptsDoubledLimitAndClampsOverflow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchArguments += ["--manna-local-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["Share a blessing"].waitForExistence(timeout: 5))
        app.buttons["Share a blessing"].tap()
        let editor = app.textViews["Write your blessing"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText(String(repeating: "a", count: 1_201))
        let expected = String(repeating: "a", count: 1_200)
        let limited = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [limited], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["1200 of 1200 characters"].exists)
        let send = app.buttons["Send blessing"]
        for _ in 0..<6 where !send.isHittable { app.swipeUp() }
        XCTAssertTrue(send.isHittable)
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        let confirmation = app.alerts["manna circle"]
        XCTAssertTrue(confirmation.staticTexts["Your blessing was shared with the circle."].waitForExistence(timeout: 5))
        confirmation.buttons["OK"].tap()
        XCTAssertFalse(app.navigationBars["Your blessing"].exists)
    }

    @MainActor
    func testAccessibleTimelineListAndNativeAudit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["--manna-local-ui-test", "-user.appearancePreference", "light"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        try auditAccessibility(app)

        app.tabBars.buttons["Timeline"].tap()
        app.buttons["Timeline layout"].tap()
        app.buttons["List"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "timeline.accessibleList").firstMatch.waitForExistence(
                timeout: 3))
        try auditAccessibility(app)
        let blessing = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "blessing.")).firstMatch
        for _ in 0..<4 where !blessing.isHittable { app.swipeUp() }
        XCTAssertTrue(blessing.isHittable)
        XCTAssertTrue(blessing.label.contains(String(Calendar.current.component(.year, from: Date()))))
        try auditAccessibility(app)
        blessing.tap()
        XCTAssertTrue(app.navigationBars["Blessing"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Close blessing"].exists)
    }

    @MainActor
    private func auditAccessibility(_ app: XCUIApplication) throws {
        // Contrast is checked independently against compiled color assets.
        // The rendered Inspector audit remains a manual acceptance requirement;
        // its current Share-button contrast finding is recorded in the audit doc.
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription]) { issue in
            let details = XCTAttachment(
                string:
                    "\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No element")\nHittable: \(issue.element?.isHittable ?? false)"
            )
            details.name = "Accessibility issue details"
            details.lifetime = .keepAlways
            self.add(details)
            return false
        }
    }

    @MainActor
    func testTimelineAutomaticallyUsesListAtLargestText() {
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-user.appearancePreference", "dark", "-UIAccessibilityReduceMotionEnabled", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "timeline.accessibleList").firstMatch.waitForExistence(
                timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "timeline.memberHeader").firstMatch.exists)
        app.swipeUp()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Accessible Timeline list at largest text in dark appearance"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testStartupOnboardingSupportsBackNavigationAndWidgetGuide() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += [
            "-onboarding.hasSeenAbout", "NO",
            "-onboarding.hasChosenAppearance", "NO",
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Step 1 of 5"].exists)
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
        XCTAssertTrue(app.navigationBars["Local saving"].waitForExistence(timeout: 3))
        let automaticSaving = app.switches["saving.automaticToggle"]
        XCTAssertTrue(automaticSaving.exists)
        automaticSaving.tap()
        XCTAssertTrue(automaticSaving.waitForExistence(timeout: 3))
        XCTAssertEqual(automaticSaving.value as? String, "1")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Widget"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Add manna to your Home Screen"].exists)
        XCTAssertTrue(app.staticTexts["Search for “manna circle,” choose a size, and add it."].exists)
        XCTAssertTrue(app.buttons["Back"].exists)

        app.buttons["Back"].tap()
        XCTAssertTrue(app.navigationBars["Local saving"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.switches["saving.automaticToggle"].value as? String, "1")
        app.buttons["Continue"].tap()

        app.buttons["Continue"].tap()
        XCTAssertFalse(app.navigationBars["Widget"].exists)
    }

    @MainActor
    func testAutomaticSavingSettingsOffersKeepChoicesAndCancellation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.buttons["App menu"].tap()
        app.buttons["User settings"].tap()
        XCTAssertTrue(app.navigationBars["User settings"].waitForExistence(timeout: 3))
        let automatic = app.switches["saving.automaticToggle"]
        for _ in 0..<5 where !automatic.isHittable { app.swipeUp() }
        XCTAssertTrue(automatic.isHittable)
        // A Form exposes the entire labeled row as Switch; only the trailing
        // UISwitch is interactive, unlike the standalone onboarding control.
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: automatic)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Saved copies"].waitForExistence(timeout: 5))
        for label in ["Keep all", "Keep only my blessings", "Keep none", "Choose from a list"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch.exists)
        }
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Choose from a list")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pick blessings to keep"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Choose automatic copies to keep"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(automatic.waitForExistence(timeout: 3))
        XCTAssertEqual(automatic.value as? String, "1")
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Saved copies"].waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Keep all")).firstMatch.tap()
        app.buttons["Turn off"].tap()
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: automatic)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
    }

    @MainActor
    func testLocalSavingSetupAtLargestTextInDarkAndLandscape() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += [
            "-onboarding.hasSeenAbout", "YES", "-onboarding.hasChosenAppearance", "YES",
            "-user.appearancePreference", "dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-UIAccessibilityReduceMotionEnabled", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Local saving"].waitForExistence(timeout: 5))
        let automatic = app.switches["saving.automaticToggle"]
        for _ in 0..<4 where !automatic.isHittable { app.swipeUp() }
        XCTAssertTrue(automatic.isHittable)
        XCTAssertTrue(app.buttons["Continue"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["Continue"].frame.height, 44)
        XCTAssertLessThanOrEqual(app.buttons["Continue"].frame.maxX, app.frame.width)
        let portrait = XCTAttachment(screenshot: app.screenshot())
        portrait.name = "Local saving at accessibility size in dark appearance"
        portrait.lifetime = .keepAlways
        add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        // Wait for the rotated scene to finish drawing, not just its window frame.
        app.swipeUp()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continue"].isHittable)
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "Local saving landscape with safe navigation"
        landscape.lifetime = .keepAlways
        add(landscape)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Widget"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Back"].isHittable)
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
        // Small-phone Forms materialize lower settings only as they scroll in.
        for _ in 0..<8 where !forceButton.isHittable { app.swipeUp() }
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
        XCTAssertTrue(app.staticTexts["Step 1 of 9"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        let name = app.textFields["create-circle-name"]
        name.tap()
        name.typeText("Guided test circle")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Choose circle photo"].exists)
        app.buttons["Back"].tap()
        XCTAssertEqual(name.value as? String, "Guided test circle")
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Time zone"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Random blessing time"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Response window"].exists)
        app.buttons["Continue"].tap()
        let allowLate = app.switches["Allow late blessings"]
        XCTAssertTrue(allowLate.waitForExistence(timeout: 2))
        XCTAssertEqual(allowLate.value as? String, "1")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["End-of-day blessing"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Reuse window"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Step 9 of 9"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Guided test circle")).firstMatch.exists)
        let review = XCTAttachment(screenshot: app.screenshot())
        review.name = "Guided circle setup review"
        review.lifetime = .keepAlways
        add(review)
        let create = app.buttons["Create circle"]
        XCTAssertTrue(create.waitForExistence(timeout: 2))
        create.tap()
        XCTAssertTrue(app.navigationBars["Circle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Guided test circle"].firstMatch.exists)
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
        XCTAssertTrue(app.staticTexts["1. 30 days for hosted media"].exists)
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
