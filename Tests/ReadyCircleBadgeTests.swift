import XCTest

@testable import BlessingCircle

final class ReadyCircleBadgeTests: XCTestCase {
    func testDailyAndEveningCountOnceAndCompletionKeepsOtherOpportunity() async throws {
        let now = Date()
        let repo = LocalBlessingRepository(now: now, endOfDayStartsAt: now.addingTimeInterval(-30))
        let bootstrap = try await repo.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let daily = try XCTUnwrap(bootstrap.prompt)
        let evening = try XCTUnwrap(bootstrap.endOfDayPrompt)
        let user = bootstrap.currentUser.id
        func count(_ submitted: Set<UUID>) -> Int {
            ReadyCircleBadgePolicy.count(
                circles: [circle], prompts: [daily, evening], submitted: submitted, userID: user, now: now)
        }
        XCTAssertEqual(count([]), 1)
        XCTAssertEqual(count([daily.id]), 1)
        XCTAssertEqual(count([evening.id]), 1)
        XCTAssertEqual(count([daily.id, evening.id]), 0)
        XCTAssertEqual(
            ReadyCircleBadgePolicy.count(circles: [circle], prompts: [daily], submitted: [], userID: UUID(), now: now),
            0)
    }

    func testDistinctCirclesFuturePromptsClosedWindowsAndNotificationStart() async throws {
        let now = Date()
        let bootstrap = try await LocalBlessingRepository(now: now).bootstrap()
        var circle = try XCTUnwrap(bootstrap.circle)
        circle.allowsLateBlessings = false
        // Remove welcome-day entry exceptions from this boundary fixture.
        circle.members = circle.members.map { member in
            var member = member
            member.joinedAt = now.addingTimeInterval(-3 * 86_400)
            return member
        }
        let prompt = try XCTUnwrap(bootstrap.prompt)
        let user = bootstrap.currentUser.id
        func count(at date: Date, prompts: [DailyPrompt]? = nil) -> Int {
            ReadyCircleBadgePolicy.count(
                circles: [circle], prompts: prompts ?? [prompt], submitted: [], userID: user, now: date)
        }
        XCTAssertEqual(count(at: prompt.startsAt.addingTimeInterval(-1)), 0)
        XCTAssertEqual(count(at: prompt.startsAt), 1)
        XCTAssertEqual(count(at: prompt.endsAt), 0)
        var scheduled = prompt
        scheduled.notificationHasStarted = false
        XCTAssertEqual(count(at: now, prompts: [scheduled]), 0)
        circle.allowsLateBlessings = true
        XCTAssertEqual(count(at: prompt.endsAt), 1)
        XCTAssertEqual(count(at: now.addingTimeInterval(2 * 86_400)), 0)
        let other = try XCTUnwrap(bootstrap.circles.first { $0.id != circle.id })
        let otherPrompt = DailyPrompt(
            id: UUID(), circleID: other.id, localDate: prompt.localDate,
            startsAt: now.addingTimeInterval(-10), endsAt: now.addingTimeInterval(590))
        XCTAssertEqual(
            ReadyCircleBadgePolicy.count(
                circles: [circle, other], prompts: [prompt, otherPrompt], submitted: [], userID: user, now: now), 2)
    }
}
