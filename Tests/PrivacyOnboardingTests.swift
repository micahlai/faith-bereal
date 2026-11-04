import XCTest
@testable import BlessingCircle

final class PrivacyOnboardingTests: XCTestCase {
    func testCurrentPolicyDisclosesBibleProviderAndAuthorizedNotificationPreviews() {
        let policy = PrivacyContent.sections.map { $0.1 }.joined(separator: " ")
        for phrase in ["Midvash", "reference and version", "ordinary connection information", "without your manna account token", "log retention has not been confirmed", "same daily or end-of-day prompt", "Share to see", "Response and nudge alerts use generic wording", "Notification Center"] {
            XCTAssertTrue(policy.contains(phrase), phrase)
        }
        XCTAssertFalse(policy.contains("Notifications are optional and use generic alerts rather than blessing/reply contents or media"))
        let guide = HelpTopic.privacy.steps.map(\.body).joined(separator: " ")
        for phrase in ["policy changes", "sharing choice again", "Midvash", "ordinary connection information"] {
            XCTAssertTrue(guide.contains(phrase), phrase)
        }
    }

    func testPrivacyFollowsLogoAndPrecedesProfileAndSaving() {
        XCTAssertEqual(StartupOnboardingPage.allCases, [.about, .appearance, .appIcon, .privacy, .profile, .saving, .widget])
    }
    func testAgeAndSharingAreRequiredAndDiagnosticsIsOptionalOff() {
        var choices = PrivacyChoices()
        XCTAssertFalse(choices.canContinue)
        XCTAssertFalse(choices.diagnostics)
        choices.ageConfirmed = true
        XCTAssertFalse(choices.canContinue)
        choices.ageConfirmed = false; choices.sharingConsent = true
        XCTAssertFalse(choices.canContinue)
        choices.ageConfirmed = true
        XCTAssertTrue(choices.canContinue)
        choices.diagnostics = true
        XCTAssertTrue(choices.canContinue)
    }
}
