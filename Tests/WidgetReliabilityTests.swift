import XCTest
@testable import BlessingCircle

final class WidgetReliabilityTests: XCTestCase {
    func testHelpExplainsWidgetRefreshAndFirstUnlock() {
        let text = HelpTopic.notifications.steps.map(\.body).joined(separator: " ")
        XCTAssertTrue(text.contains("unlock it once"))
        XCTAssertTrue(text.contains("iOS controls refresh timing"))
    }
    func testTimelinePreloadsExactPromptBoundariesAndRotations() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let prompt = BlessingWidgetPrompt(promptID: UUID(), circleID: UUID(), circleName: "Friends",
            startsAt: now.addingTimeInterval(127), endsAt: now.addingTimeInterval(727),
            viewerHasSubmitted: false, isOnCurrentCircleDay: true)
        let snapshot = BlessingWidgetSnapshot(generatedAt: now, refreshIntervalMinutes: 30, prompts: [prompt], blessings: [])
        let dates = snapshot.timelineDates(after: now)
        XCTAssertEqual(dates.first, now)
        XCTAssertTrue(dates.contains(prompt.startsAt))
        XCTAssertTrue(dates.contains(prompt.endsAt))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(1800)))
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertEqual(snapshot.content(at: prompt.startsAt), .share(prompt))
        XCTAssertEqual(snapshot.content(at: prompt.endsAt), .empty)
    }
}
