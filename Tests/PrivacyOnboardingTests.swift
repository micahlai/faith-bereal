import XCTest
@testable import BlessingCircle

final class PrivacyOnboardingTests: XCTestCase {
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
