import XCTest
@testable import BlessingCircle

final class HelpContentTests: XCTestCase {
    func testEveryTopicHasDistinctTitleAndIllustratedPlainLanguageSteps() {
        XCTAssertEqual(Set(HelpTopic.allCases.map(\.title)).count, HelpTopic.allCases.count)
        for topic in HelpTopic.allCases {
            XCTAssertFalse(topic.icon.isEmpty)
            XCTAssertFalse(topic.summary.isEmpty)
            XCTAssertGreaterThanOrEqual(topic.steps.count, 3)
            for step in topic.steps {
                XCTAssertFalse(step.icon.isEmpty)
                XCTAssertFalse(step.title.isEmpty)
                XCTAssertFalse(step.body.isEmpty)
                XCTAssertFalse(step.body.localizedCaseInsensitiveContains("supabase"))
            }
        }
    }

    func testSavingGuideTracksRetentionAndDeviceOnlyLimits() {
        XCTAssertEqual(MediaRetentionPolicy.lifetime / 86_400, 30)
        let guide = HelpTopic.saving.steps.map(\.body).joined(separator: " ")
        for concept in ["30 days", "responses", "Photos", "uninstall", "other people", "permanent", "Future responses",
                        "Automatically save locally", "Keep only my blessings", "Choose from a list", "manual saves", "while closed"] {
            XCTAssertTrue(guide.contains(concept), "Saving guide must explain \(concept)")
        }
    }

    func testPromptGuideExplainsEntryRatherThanSubmissionDeadline() {
        let guide = HelpTopic.sharing.steps.map(\.body).joined(separator: " ")
        for concept in ["enter the composer", "not when you must finish", "past midnight", "first day", "10 minutes"] {
            XCTAssertTrue(guide.contains(concept))
        }
    }

    func testAccessibilityGuideExplainsAlternativesAndDoesNotOverclaimMediaSupport() {
        let guide = HelpTopic.accessibility.steps.map(\.body).joined(separator: " ")
        for concept in ["VoiceOver", "Voice Control", "List", "Reduce Motion", "Adjust photo", "start and end verse", "not yet available"] {
            XCTAssertTrue(guide.contains(concept))
        }
        XCTAssertTrue(HelpTopic.personalization.steps.map(\.body).joined().contains("Adjust photo"))
    }
}
