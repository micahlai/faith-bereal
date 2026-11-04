import XCTest
import UIKit

final class AccountSafetyUITests: XCTestCase {
    @MainActor private func launch(largest: Bool = false, appearance: String? = nil, failures: String = "", extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BLESSING_CIRCLE_FORCE_LOCAL"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["BLESSING_CIRCLE_SAVING_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["MANNA_SAFETY_FAILURES"] = failures
        app.launchArguments = ["--manna-local-ui-test", "--manna-safety-ui-test", "--manna-reset-safety-state", "--manna-skip-onboarding", "--manna-reset-timeline-layout",
            "-blessingCircle.selectedCircleID", "B0000000-0000-0000-0000-000000000001",
            "-user.appearancePreference", appearance ?? (largest ? "dark" : "light"), "-UIPreferredContentSizeCategoryName",
            largest ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + extra
        app.launch()
        return app
    }

    @MainActor func testPendingDeletionActionsAtLargestDarkText() {
        let app = launch(largest: true, failures: "receipt", extra: ["--manna-deletion-pending"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Account deletion requested"].waitForExistence(timeout: 15))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Pending deletion largest dark"; capture.lifetime = .keepAlways; add(capture)
        let heading = app.staticTexts["deletion.heading"]
        let titleFont = UIFont.preferredFont(forTextStyle: .title1, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        let titleHeight = (heading.label as NSString).boundingRect(with: CGSize(width: heading.frame.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: titleFont], context: nil).height
        XCTAssertGreaterThanOrEqual(heading.frame.height, titleHeight - 3, "Pending title must not be truncated at largest text")
        let status = app.buttons["Check deletion status"]
        reveal(status, app: app)
        XCTAssertGreaterThanOrEqual(status.frame.height, 44)
        status.tap()
        let message = app.staticTexts["deletionStatus"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("has not been confirmed complete"))
        let policy = app.buttons["Privacy policy"]
        reveal(policy, app: app); policy.tap()
        XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let signOut = app.buttons["Sign out"]
        reveal(signOut, app: app); signOut.tap()
        XCTAssertTrue(app.buttons["Continue with Apple"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Account deletion requested"].exists)
    }

    @MainActor func testRenderedTodayContrastInBothAppearances() throws {
        for dark in [false, true] {
            let app = launch(appearance: dark ? "dark" : "light")
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
            let share = app.buttons["Share a blessing"]
            reveal(share, app: app)
            try app.performAccessibilityAudit(for: .contrast) { issue in
                let details = XCTAttachment(string: "\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No element")")
                details.name = "Rendered contrast finding"; details.lifetime = .keepAlways; self.add(details)
                return false
            }
            app.terminate()
        }
    }

    @MainActor func testReportBlessingRetainsDetailsOnFailureAndRetrySucceeds() {
        let app = launch(failures: "report")
        defer { app.terminate() }
        openPeerBlessing(app)
        reportMenu("safety.blessing", app: app)
        let reason = app.buttons["safety.reportReason"]
        reveal(reason, app: app); reason.tap()
        let privacy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Privacy")).firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5)); privacy.tap()
        let details = app.descendants(matching: .any).matching(identifier: "safety.reportDetails").firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap(); details.typeText("Synthetic privacy report")
        app.toolbars.buttons["Done"].tap()
        let send = app.buttons["safety.reportSend"]
        reveal(send, app: app); send.tap()
        XCTAssertTrue(app.staticTexts["safety.reportError"].waitForExistence(timeout: 5))
        reveal(details, app: app, down: true)
        XCTAssertEqual(details.value as? String, "Synthetic privacy report")
        let reasonState = XCTAttachment(string: reason.debugDescription)
        reasonState.name = "Retained report reason accessibility state"; reasonState.lifetime = .keepAlways; add(reasonState)
        XCTAssertEqual(reason.value as? String, "Privacy", "The selected reason must remain after the failed report")
        let retained = XCTAttachment(screenshot: app.screenshot())
        retained.name = "Failed report retains reason and details"; retained.lifetime = .keepAlways; add(retained)
        reveal(send, app: app); send.tap()
        let alert = app.alerts["manna circle"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Report received for review. You can also block this user."].exists)
        alert.buttons["OK"].tap()
        XCTAssertFalse(app.navigationBars["Report content"].exists)
    }

    @MainActor func testResponseReportCancelAndSubmitAtLargestDarkText() {
        let app = launch(largest: true)
        defer { app.terminate() }
        openPeerBlessing(app)
        reportMenu("safety.response", app: app)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["Report content"].exists)
        reportMenu("safety.response", app: app)
        let send = app.buttons["safety.reportSend"]
        reveal(send, app: app); send.tap()
        XCTAssertTrue(app.alerts["manna circle"].waitForExistence(timeout: 5))
        app.alerts["manna circle"].buttons["OK"].tap()
    }

    @MainActor func testBlockCancelFailureRetryAndUnblock() {
        let app = launch(failures: "block,unblock")
        defer { app.terminate() }
        openPeerBlessing(app)
        blockMenu(app)
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.navigationBars["Blessing"].tap() } // iOS 26 popover dismisses by tapping outside.
        XCTAssertFalse(app.staticTexts["Block this user?"].exists)
        XCTAssertTrue(app.staticTexts["Sunlight through the kitchen window."].exists)
        blockMenu(app)
        app.buttons["Block user"].tap()
        XCTAssertTrue(app.alerts["Could not block user"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["Could not block this user. Try again."].exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Blessing"].exists)
        blockMenu(app)
        app.buttons["Block user"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Sunlight through the kitchen window."].exists)
        openSettings(app)
        let blocked = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label == %@", "safety.blockedUsersLink", "Blocked users")).firstMatch
        reveal(blocked, app: app); blocked.tap()
        let unblock = app.buttons["safety.unblock.A0000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(unblock.waitForExistence(timeout: 5))
        unblock.tap()
        XCTAssertTrue(app.staticTexts["Could not unblock. Try again."].waitForExistence(timeout: 5))
        XCTAssertTrue(unblock.exists)
        unblock.tap()
        XCTAssertTrue(app.staticTexts["No blocked users"].waitForExistence(timeout: 5))
        XCTAssertFalse(unblock.exists)
    }

    @MainActor func testBlockedUsersLoadFailureHasRetryInsteadOfFalseEmptyAtLargestText() {
        let app = launch(largest: true, failures: "load")
        defer { app.terminate() }
        openSettings(app)
        let blocked = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label == %@", "safety.blockedUsersLink", "Blocked users")).firstMatch
        reveal(blocked, app: app); blocked.tap()
        XCTAssertTrue(app.staticTexts["safety.blockedError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No blocked users"].exists)
        let retry = app.buttons["Retry"]
        reveal(retry, app: app); retry.tap()
        XCTAssertTrue(app.staticTexts["No blocked users"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["safety.blockedError"].exists)
    }

    @MainActor func testDeletionAcknowledgementFailureAcceptanceAndPendingRelaunch() {
        let app = launch(failures: "deletion")
        defer { app.terminate() }
        openSettings(app)
        let delete = app.buttons["Delete account"]
        reveal(delete, app: app); delete.tap()
        XCTAssertTrue(app.navigationBars["Delete account"].waitForExistence(timeout: 5))
        let confirmation = app.buttons["deletion.localConfirmation"]
        reveal(confirmation, app: app)
        XCTAssertFalse(confirmation.isEnabled)
        let acknowledgement = app.switches["deletion.acknowledgement"]
        reveal(acknowledgement, app: app, down: true)
        acknowledgement.switches.firstMatch.exists ? acknowledgement.switches.firstMatch.tap() : acknowledgement.tap()
        reveal(confirmation, app: app); XCTAssertTrue(confirmation.isEnabled); confirmation.tap()
        XCTAssertTrue(app.staticTexts["deletion.requestError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Account deletion requested"].exists)
        XCTAssertTrue(app.navigationBars["Delete account"].exists)
        reveal(confirmation, app: app, down: true); confirmation.tap()
        XCTAssertTrue(app.staticTexts["Account deletion requested"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Today"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--manna-reset-safety-state" }
        app.launch()
        XCTAssertTrue(app.staticTexts["Account deletion requested"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["deletionStatus"].label.contains("has not been confirmed complete"))
    }

    @MainActor func testPendingCompletedStatusAndFailedSignOutPreservesGate() {
        let app = launch(failures: "signout", extra: ["--manna-deletion-pending", "--manna-deletion-completed",
            "--manna-privacy-ui-test", "-privacy.acceptedVersion", "2026-11-02", "-onboarding.hasSeenAbout", "YES"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["deletionStatus"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["deletionStatus"].label.contains("Deletion completed in the active service"))
        let signOut = app.buttons["Sign out"]
        reveal(signOut, app: app); signOut.tap()
        XCTAssertTrue(app.alerts["manna circle"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["Account deletion requested"].exists)
        XCTAssertFalse(app.tabBars.buttons["Today"].exists)
        signOut.tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 10))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["App icon"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Your privacy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["privacy.continue"].isEnabled)
        XCTAssertFalse(app.buttons["Continue with Apple"].exists)
    }

    @MainActor private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["App menu"].waitForExistence(timeout: 15))
        app.buttons["App menu"].tap(); app.buttons["User settings"].tap()
        XCTAssertTrue(app.navigationBars["User settings"].waitForExistence(timeout: 5))
        let grabber = app.buttons["Sheet Grabber"]
        if grabber.exists, grabber.value as? String != "Expanded" {
            grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    @MainActor private func openPeerBlessing(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Timeline"].tap()
        let row = app.staticTexts["Sunlight through the kitchen window."]
        reveal(row, app: app); row.tap()
        XCTAssertTrue(app.navigationBars["Blessing"].waitForExistence(timeout: 5))
    }

    @MainActor private func reportMenu(_ identifier: String, app: XCUIApplication) {
        let safety = app.buttons[identifier].firstMatch
        reveal(safety, app: app); safety.tap(); app.buttons["Report content"].tap()
        XCTAssertTrue(app.navigationBars["Report content"].waitForExistence(timeout: 5))
    }

    @MainActor private func blockMenu(_ app: XCUIApplication) {
        let safety = app.buttons["safety.blessing"]
        reveal(safety, app: app); safety.tap(); app.buttons["Block user"].tap()
        XCTAssertTrue(app.staticTexts["Block this user?"].waitForExistence(timeout: 3))
    }

    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, down: Bool = false) {
        let scrollQuery = app.descendants(matching: .any).matching(NSPredicate(
            format: "elementType == %d OR elementType == %d",
            XCUIElement.ElementType.collectionView.rawValue, XCUIElement.ElementType.scrollView.rawValue))
        let scroll = scrollQuery.allElementsBoundByIndex.last { $0.frame.width > 200 && $0.frame.height > 100 && $0.frame.intersects(app.frame) }
        for attempt in 0..<65 {
            let bounds = scroll?.frame ?? app.frame
            let navBottom = app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? (bounds.minY + 44)
            let top = max(bounds.minY, navBottom) + 8
            let bottom = min(bounds.maxY - 8, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 8 : app.frame.maxY - 45)
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let viewport = CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top)
            if exists, element.isHittable, viewport.contains(frame) { return }
            if attempt.isMultiple(of: 15) {
                let visible = app.staticTexts.allElementsBoundByIndex.filter { $0.frame.intersects(CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top)) }.prefix(4).map(\.label)
                print("Reveal attempt \(attempt), scroll bounds \(bounds), target \(frame), visible labels \(visible)")
            }
            let height = bottom - top
            let scrollBack = exists ? frame.minY < top : down
            let delta = exists ? frame.midY - (top + bottom) / 2 : height
            let travel = min(height * 0.28, max(32, abs(delta) * 0.65))
            let startY = top + height * (scrollBack ? 0.35 : 0.7)
            let endY = min(bottom - 12, max(top + 12, startY + (scrollBack ? travel : -travel)))
            // Center of the actual scroll surface avoids the native trailing
            // scroll-indicator track and the obscured underlying screen.
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: bounds.midX, dy: startY))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: bounds.midX, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Could not fully reveal target: \(element.exists ? element.frame : .zero)")
    }
}
