import XCTest
@testable import BlessingCircle

final class LiveActivityCutoffTests: XCTestCase {
    func testLateActivityEndsAtCircleMidnightAcrossDST() throws {
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: "America/New_York")
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let deadline = day.addingTimeInterval(12 * 3600)
        let cutoff = PromptActivityDismissal.entryCutoff(endsAt: deadline, circleDay: day,
            timeZoneIdentifier: "America/New_York", allowsLateBlessings: true)
        XCTAssertEqual(cutoff.timeIntervalSince(day), 25 * 3600)
        XCTAssertEqual(PromptActivityDismissal.date(after: cutoff).timeIntervalSince(cutoff), 180)
        XCTAssertEqual(PromptActivityDismissal.entryCutoff(endsAt: deadline, circleDay: day,
            timeZoneIdentifier: "America/New_York", allowsLateBlessings: false), deadline)
    }

    func testOrdinaryWindowThatCrossesMidnightIsNotShortened() {
        let day = Date(timeIntervalSince1970: 0)
        let deadline = day.addingTimeInterval(25 * 3600)
        XCTAssertEqual(PromptActivityDismissal.entryCutoff(endsAt: deadline, circleDay: day,
            timeZoneIdentifier: "UTC", allowsLateBlessings: true), deadline)
    }

    func testHelpExplainsLateEntryDoesNotOverrideDayBoundary() {
        XCTAssertTrue(HelpTopic.sharing.steps.map(\.body).joined().contains("Late sharing does not reopen a past day"))
    }
}
