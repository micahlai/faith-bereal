import XCTest
@testable import BlessingCircle

final class CircleStreakTests: XCTestCase {
    func testDistinctDaysLateSharingGapsAndCircleIsolation() async throws {
        let bootstrap = try await LocalBlessingRepository().bootstrap()
        var circle = try XCTUnwrap(bootstrap.circle)
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier)
        let today = calendar.startOfDay(for: .now)
        var member = bootstrap.currentUser
        member.joinedAt = calendar.date(byAdding: .day, value: -100, to: today)!
        circle.members = [member]
        func day(_ offset: Int, timely: Bool, circleID: UUID? = nil) -> StreakDay {
            StreakDay(circleID: circleID ?? circle.id, memberID: member.id,
                day: calendar.date(byAdding: .day, value: offset, to: today)!, onTime: timely)
        }
        let posts = [day(0, timely: false), day(0, timely: true), day(-1, timely: false),
            day(-2, timely: true), day(-4, timely: true), day(-3, timely: true, circleID: UUID())]
        let summary = try XCTUnwrap(CircleStreakPolicy.summaries(circle: circle, posts: posts, now: .now)[member.id])
        XCTAssertEqual(summary.days, 3)
        XCTAssertEqual(summary.onTimeDays, 2)
        XCTAssertTrue(summary.onTimeToday)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        XCTAssertEqual(CircleStreakPolicy.summaries(circle: circle, posts: posts, now: tomorrow)[member.id]?.days, 3)
        let later = calendar.date(byAdding: .day, value: 2, to: today)!
        XCTAssertEqual(CircleStreakPolicy.summaries(circle: circle, posts: posts, now: later)[member.id]?.days, 0)
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("sharing in another circle doesn't add"))
    }
}
