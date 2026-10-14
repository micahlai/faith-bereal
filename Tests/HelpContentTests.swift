import XCTest
@testable import BlessingCircle

final class HelpContentTests: XCTestCase {
    func testPhotoAndTodayGuideExplainsZoomControlsAndVerticalOnlyFeed() {
        let guide = HelpTopic.timeline.steps.map(\.body).joined()
        for concept in ["enlarge it", "Profile and circle photos do not", "Pinch to zoom", "Zoom in", "Zoom out", "movement controls",
                        "Tap Close photo", "crop editor", "fixed side to side"] {
            XCTAssertTrue(guide.contains(concept), concept)
        }
    }

    func testCircleGuideExplainsSharedChangesAndLeaderOnlyExceptions() {
        let guide = HelpTopic.circles.steps.map(\.body).joined()
        for concept in ["Anyone can make circle changes", "starts off", "current members", "leader-only", "cannot remove the leader", "Leave circle"] {
            XCTAssertTrue(guide.contains(concept), concept)
        }
    }

    func testDiagnosticGuideExplainsConsentAccountAssociationAndLimits() {
        let guide = HelpTopic.personalization.steps.map(\.body).joined()
        for concept in ["Share diagnostic data", "starts with sharing on", "turn it off", "saved off setting remains off", "TestFlight", "linked to your signed-in account",
                        "14 days", "cannot read", "discards unsent", "1,000", "13 days", "Local demo"] {
            XCTAssertTrue(guide.contains(concept), concept)
        }
    }
    func testStreakGuideDescribesSingleFlameColorPhotoOverlayAndCirclePanel() {
        let guide = HelpTopic.timeline.steps.map(\.body).joined()
        XCTAssertTrue(guide.contains("One flame pill"))
        XCTAssertTrue(guide.contains("blue when every day"))
        XCTAssertTrue(guide.contains("red when it includes a late entry"))
        XCTAssertTrue(guide.contains("no verification badge"))
        XCTAssertTrue(guide.contains("small animated popup"))
        XCTAssertTrue(guide.contains("A late entry breaks the blue run"))
        XCTAssertTrue(guide.contains("without moving the name"))
        XCTAssertTrue(guide.contains("Circle People panel"))
    }

    func testCircleGuideExplainsInterruptedSwitchRecovery() {
        let guide = HelpTopic.circles.steps.map(\.body).joined()
        XCTAssertTrue(guide.contains("finish loading before sharing"))
        XCTAssertTrue(guide.contains("previous circle stays selected"))
        XCTAssertTrue(guide.contains("try again"))
    }
    func testOlderWidgetLinksDoNotRequireLoadingTimelineHistory() {
        XCTAssertTrue(HelpTopic.notifications.steps.map(\.body).joined().contains("Older blessings open without first loading"))
    }
    func testTimelineGuideDescribesLazyRendering() {
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("draws cards as they come into view"))
    }
    func testResponseGuideDescribesProfilePhotos() {
        XCTAssertTrue(HelpTopic.responses.steps.map(\.body).joined().contains("profile photo beside their name"))
    }
    func testSavingGuideExplainsManualChoiceWhenAutomaticSavingIsOff() {
        let text = HelpTopic.saving.steps.map(\.body).joined()
        XCTAssertTrue(text.contains("If this is off, you can still choose individual blessings"))
        XCTAssertTrue(text.contains("Text, Bible references, and photos remain"))
    }
    func testWelcomeGuideExplainsPreviousDayAndNotificationCutoff() {
        let guide = HelpTopic.sharing.steps.map(\.body).joined()
        XCTAssertTrue(guide.contains("welcome blessing belongs to yesterday"))
        XCTAssertTrue(guide.contains("entry closes when today's notification starts"))
    }
    func testVoiceGuideExplainsSegmentPreservation() {
        let guide = HelpTopic.sharing.steps.map(\.body).joined()
        XCTAssertTrue(guide.contains("Continue recording"))
        XCTAssertTrue(guide.contains("words and audio are kept"))
    }
    func testEveningGuideUsesSevenHourCutoff() {
        XCTAssertTrue(HelpTopic.evening.steps.map(\.body).joined().contains("seven hours"))
    }
    func testProfileSetupGuideExplainsOptionalPhoto() {
        let guide = HelpTopic.personalization.steps.map(\.body).joined(separator: " ")
        XCTAssertTrue(guide.contains("Your profile step"))
        XCTAssertTrue(guide.contains("Continue keeps your current profile"))
    }
    func testAccountGuideLocatesSignOutOnlyInSettings() {
        let guide = HelpTopic.personalization.steps.map(\.body).joined(separator: " ")
        XCTAssertTrue(guide.contains("User settings"))
        XCTAssertTrue(guide.contains("not in the app menu or Circle page"))
    }
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

    func testSharingGuideExplainsBlessingLimitWithoutChangingResponses() {
        XCTAssertEqual(BlessingTextPolicy.maximumLength, 1_200)
        let guide = HelpTopic.sharing.steps.map(\.body).joined(separator: " ")
        for concept in ["1,200 characters", "voice/video transcripts", "editing", "Responses still allow 600", "combined emoji"] {
            XCTAssertTrue(guide.contains(concept))
        }
    }

    func testReuseGuideExplainsMediaAndTargetCirclePrivacy() {
        let guide = HelpTopic.sharing.steps.map(\.body).joined(separator: " ")
        for concept in ["original format", "Bible tag", "audio, photo, or video", "Responses are not copied", "receiving circle"] {
            XCTAssertTrue(guide.contains(concept))
        }
    }

    func testCircleGuideExplainsStableCodesAndLegacyRecovery() {
        let guide = HelpTopic.circles.steps.map(\.body).joined(separator: " ")
        for concept in ["updates and relaunches", "only an authorized Regenerate", "saved join link", "regenerate once"] {
            XCTAssertTrue(guide.contains(concept))
        }
    }

    func testTimelineGuideDistinguishesScheduledAndShareableStates() {
        let guide = HelpTopic.timeline.steps.map(\.body).joined(separator: " ")
        for concept in ["Unstarted prompts are hidden", "has started", "You can still share", "first-day exception", "Future days"] {
            XCTAssertTrue(guide.contains(concept))
        }
    }

    func testNudgeGuideExplainsSamePromptPrivacyAndLimits() {
        let guide = HelpTopic.sharing.steps.map(\.body).joined(separator: " ")
        for concept in ["After sharing for a prompt", "same daily or end-of-day", "late sharing", "one nudge per prompt",
                        "never reveals", "notification switch", "window closes", "local demo"] {
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

    func testNotificationGuideExplainsFullSenderPhotoAndFallback() {
        let guide = HelpTopic.notifications.steps.map(\.body).joined(separator: " ")
        for concept in ["full profile photo", "on the left", "fallback", "app-icon badge", "responses have no right image"] {
            XCTAssertTrue(guide.contains(concept))
        }
    }
}
