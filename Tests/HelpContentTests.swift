import XCTest
@testable import BlessingCircle

final class HelpContentTests: XCTestCase {
    func testTrafficSavingGuideExplainsTemporaryCacheAndNetworkChoices() {
        let timeline = HelpTopic.timeline.steps.map(\.body).joined()
        for concept in ["most recent 7 days", "temporary cache", "256 MB", "up to seven days", "720p", "small previews", "full size"] {
            XCTAssertTrue(timeline.contains(concept), concept)
        }
        let saving = HelpTopic.saving.steps.map(\.body).joined()
        for concept in ["Wi-Fi only", "cellular", "Include older history", "starts off", "last seven days"] {
            XCTAssertTrue(saving.contains(concept), concept)
        }
    }

    func testOfflineArchiveAndLegacyRecordingHelpExplainsLocalLimits() {
        let guide = HelpTopic.saving.steps.map(\.body).joined()
        for concept in ["automatically in Timeline", "without internet", "closing and reopening", "read-only", "until you sign out", "other accounts cannot read", "Missing local files"] {
            XCTAssertTrue(guide.contains(concept), concept)
        }
        XCTAssertFalse(guide.contains("Use Saved on this device"))
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("no new download is needed"))
    }

    func testIdentityAndAppearanceHelpExplainsDurableOfflinePhotosAndTheme() {
        let circles = HelpTopic.circles.steps.map(\.body).joined()
        for concept in ["load locally first", "appear without internet", "never downloaded need a connection", "removed photos disappear"] {
            XCTAssertTrue(circles.contains(concept), concept)
        }
        let appearance = HelpTopic.personalization.steps.map(\.body).joined()
        XCTAssertTrue(appearance.contains("opening and closing a photo"))
        XCTAssertTrue(appearance.contains("iPhone switches appearance"))
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("no thread line or circle markers"))
    }

    func testMediaGuideExplainsDemandLoadingCompressionAndLocalReuse() {
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("download only when you tap Play"))
        XCTAssertTrue(HelpTopic.responses.steps.map(\.body).joined().contains("compressed before sending"))
        let saving = HelpTopic.saving.steps.map(\.body).joined()
        for concept in ["use the local copy", "including before expiry", "does not download saved files again", "only newly available media"] {
            XCTAssertTrue(saving.contains(concept), concept)
        }
    }

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
    func testDiagnosticGuideExplainsSanitizedCaptureFailuresAndPriority() {
        let guide = HelpTopic.personalization.steps.map(\.body).joined()
        for concept in ["failure sources", "short error codes", "speech", "recording", "diagnostic-upload",
                        "connection limits", "messages themselves are not sent", "ahead of routine timing",
                        "original batch unchanged", "only one error record", "routine records first"] {
            XCTAssertTrue(guide.contains(concept), concept)
        }
    }
    func testStreakGuideDescribesIndependentCountsAndWindowClosures() {
        let guide = HelpTopic.timeline.steps.map(\.body).joined()
        XCTAssertTrue(guide.contains("One flame pill"))
        XCTAssertTrue(guide.contains("always shows the overall count"))
        XCTAssertTrue(guide.contains("blue only when both streak counts are equal"))
        XCTAssertTrue(guide.contains("Evening blessings never earn an on time day"))
        XCTAssertTrue(guide.contains("random for on time"))
        XCTAssertTrue(guide.contains("final evening opportunity for overall"))
        XCTAssertTrue(guide.contains("continuing after midnight"))
        XCTAssertTrue(guide.contains("5 overall and 3 on time"))
        XCTAssertTrue(guide.contains("shows both positive counts"))
        XCTAssertTrue(guide.contains("only red when on time is zero"))
        XCTAssertTrue(guide.contains("no flame when both are zero"))
        XCTAssertTrue(guide.contains("no verification badge"))
        XCTAssertTrue(guide.contains("small animated popup"))
        XCTAssertTrue(guide.contains("A late random entry breaks the blue run"))
        XCTAssertTrue(guide.contains("without moving the name"))
        XCTAssertTrue(guide.contains("Circle People panel"))
    }

    func testRecordingHelpExplainsRefreshAndPrivateFailureDiagnostics() {
        let guide = HelpTopic.timeline.steps.map(\.body).joined()
        for concept in ["updated recording link", "missing or unreadable", "failed recording downloads and playback",
                        "download status", "short audio error code", "contents and links are never included"] {
            XCTAssertTrue(guide.contains(concept), concept)
        }
    }

    func testCircleGuideExplainsVisibleLoadingAndInterruptedSwitchRecovery() {
        let guide = HelpTopic.circles.steps.map(\.body).joined()
        XCTAssertTrue(guide.contains("finish loading before sharing"))
        XCTAssertTrue(guide.contains("previous circle returns"))
        XCTAssertTrue(guide.contains("select the other circle again"))
        XCTAssertTrue(guide.contains("move between tabs"))
        XCTAssertTrue(guide.contains("Retry refreshes the circle currently shown"))
        XCTAssertTrue(guide.contains("Retry reloads them"))
        XCTAssertTrue(guide.contains("streaks, and profile/circle photos"))
        XCTAssertTrue(guide.contains("until you sign out"))
        XCTAssertTrue(guide.contains("signing out clears them"))
        XCTAssertTrue(guide.contains("Basic circle details are saved before blessings finish loading"))
        XCTAssertTrue(guide.contains("Blessings still need a fresh connection"))
        XCTAssertTrue(guide.contains("Old blessings from another circle are never shown"))
        XCTAssertTrue(guide.contains("try again"))
    }
    func testOlderWidgetLinksDoNotRequireLoadingTimelineHistory() {
        XCTAssertTrue(HelpTopic.notifications.steps.map(\.body).joined().contains("Older blessings open without first loading"))
    }
    func testTimelineGuideExplainsListDefaultPersonFilterAndResponseCounts() {
        let guide = HelpTopic.timeline.steps.map(\.body).joined()
        for concept in ["remembers your last List or Threads choice", "wide Timeline layout button", "filter starts at All",
                        "only to List", "Threads always shows everyone", "changing circles resets it to All", "picker shows profile photos", "initials when no photo", "photo stays beside their name"] {
            XCTAssertTrue(guide.contains(concept), concept)
        }
        let responses = HelpTopic.responses.steps.map(\.body).joined()
        XCTAssertTrue(responses.contains("number of responses"))
        XCTAssertTrue(responses.contains("slightly overlapping profile photos"))
        XCTAssertTrue(responses.contains("count includes every response"))
        XCTAssertTrue(responses.contains("no responses leave this line hidden"))
        XCTAssertTrue(HelpTopic.accessibility.steps.map(\.body).joined().contains("remembers your last layout"))
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

    func testNotificationGuideExplainsIndependentRegistrationAndRetry() {
        let guide = HelpTopic.notifications.steps.map(\.body).joined(separator: " ")
        for concept in ["Alerts and Live Activities can become ready separately", "reopen the app to retry",
                        "iOS controls delivery", "does not guarantee"] {
            XCTAssertTrue(guide.contains(concept))
        }
    }
}
