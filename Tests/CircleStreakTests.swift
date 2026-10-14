import XCTest
@testable import BlessingCircle

final class CircleStreakTests: XCTestCase {
    func testSingleFlameUsesTimelyEntryAcrossTheEntireCurrentStreak() async throws {
        let bootstrap = try await LocalBlessingRepository().bootstrap()
        var circle = try XCTUnwrap(bootstrap.circle)
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier)
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var member = bootstrap.currentUser
        member.joinedAt = calendar.date(byAdding: .day, value: -10, to: today)!
        circle.members = [member]
        var posts = (0...2).map { offset in
            StreakDay(circleID: circle.id, memberID: member.id,
                day: calendar.date(byAdding: .day, value: -offset, to: today)!, onTime: true)
        }
        let allTimely = try XCTUnwrap(CircleStreakPolicy.summaries(circle: circle, posts: posts, now: now)[member.id])
        XCTAssertEqual(allTimely.days, 3)
        XCTAssertTrue(allTimely.hasOnlyTimelyEntries)
        posts[1] = StreakDay(circleID: circle.id, memberID: member.id,
            day: posts[1].day, onTime: false)
        let mixed = try XCTUnwrap(CircleStreakPolicy.summaries(circle: circle, posts: posts, now: now)[member.id])
        XCTAssertEqual(mixed.days, 3)
        XCTAssertTrue(mixed.onTimeToday)
        XCTAssertFalse(mixed.hasOnlyTimelyEntries)
        let empty = try XCTUnwrap(CircleStreakPolicy.summaries(circle: circle, posts: [], now: now)[member.id])
        XCTAssertFalse(empty.hasOnlyTimelyEntries)
    }

    func testTimelyRunIsConsecutiveAndIndependentOfNormalStreak() async throws {
        let bootstrap = try await LocalBlessingRepository().bootstrap()
        var circle = try XCTUnwrap(bootstrap.circle)
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier)
        let today = calendar.startOfDay(for: .now)
        var member = bootstrap.currentUser
        member.joinedAt = calendar.date(byAdding: .day, value: -30, to: today)!
        circle.members = [member]
        func post(_ offset: Int, timely: Bool) -> StreakDay {
            StreakDay(circleID: circle.id, memberID: member.id,
                day: calendar.date(byAdding: .day, value: offset, to: today)!, onTime: timely)
        }
        let posts = [post(0, timely: true), post(-1, timely: true), post(-2, timely: false),
            post(-3, timely: true), post(-4, timely: true)]
        let mixed = try XCTUnwrap(CircleStreakPolicy.summaries(circle: circle, posts: posts, now: today)[member.id])
        XCTAssertEqual(mixed.days, 5)
        XCTAssertEqual(mixed.onTimeDays, 4)
        XCTAssertEqual(mixed.onTimeStreakDays, 2)
        XCTAssertFalse(mixed.hasOnlyTimelyEntries)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let grace = try XCTUnwrap(CircleStreakPolicy.summaries(circle: circle, posts: posts, now: tomorrow)[member.id])
        XCTAssertEqual(grace.days, 5)
        XCTAssertEqual(grace.onTimeStreakDays, 2)
        let lateToday = posts + [post(1, timely: false)]
        let reset = try XCTUnwrap(CircleStreakPolicy.summaries(circle: circle, posts: lateToday, now: tomorrow)[member.id])
        XCTAssertEqual(reset.days, 6)
        XCTAssertEqual(reset.onTimeStreakDays, 0)
        let timelySameDay = lateToday + [post(1, timely: true)]
        XCTAssertEqual(CircleStreakPolicy.summaries(circle: circle, posts: timelySameDay, now: tomorrow)[member.id]?.onTimeStreakDays, 3)
        let afterGap = calendar.date(byAdding: .day, value: 2, to: today)!
        XCTAssertEqual(CircleStreakPolicy.summaries(circle: circle, posts: posts, now: afterGap)[member.id]?.onTimeStreakDays, 0)
    }

    func testTimelyRunDecoderHandlesOldAndNewRPCShapes() throws {
        let memberID = UUID()
        func decode(days: Int, timely: Int, consecutive: Int? = nil) throws -> CircleStreak {
            var json: [String: Any] = ["member_id": memberID.uuidString, "days": days,
                "on_time_days": timely, "on_time_today": true]
            if let consecutive { json["on_time_streak_days"] = consecutive }
            return try JSONDecoder().decode(CircleStreak.self, from: JSONSerialization.data(withJSONObject: json))
        }
        XCTAssertEqual(try decode(days: 5, timely: 5).onTimeStreakDays, 5)
        XCTAssertEqual(try decode(days: 5, timely: 4).onTimeStreakDays, 0)
        let explicit = try decode(days: 5, timely: 4, consecutive: 2)
        XCTAssertEqual(explicit.onTimeStreakDays, 2)
        XCTAssertEqual(explicit.onTimeDays, 4)
        let roundTrip = try JSONDecoder().decode(CircleStreak.self, from: JSONEncoder().encode(explicit))
        XCTAssertEqual(roundTrip, explicit)
    }

    func testEachCircleUsesItsOwnCalendarAcrossDaylightSaving() async throws {
        let bootstrap = try await LocalBlessingRepository().bootstrap()
        var circle = try XCTUnwrap(bootstrap.circle)
        circle.timeZoneIdentifier = "America/New_York"
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier)
        let now = ISO8601DateFormatter().date(from: "2026-11-02T04:30:00Z")!
        let today = calendar.startOfDay(for: now)
        var member = bootstrap.currentUser
        member.joinedAt = calendar.date(byAdding: .day, value: -10, to: today)!
        circle.members = [member]
        let posts = (0...2).map { offset in
            StreakDay(circleID: circle.id, memberID: member.id,
                day: calendar.date(byAdding: .day, value: -offset, to: today)!, onTime: false)
        }
        XCTAssertEqual(CircleStreakPolicy.summaries(circle: circle, posts: posts, now: now)[member.id]?.days, 3)
        // This instant is November 1 in this circle, after the fall-back clock change.
        XCTAssertEqual(calendar.component(.day, from: today), 1)
        let otherCircleID = UUID()
        let elsewhere = posts.map { StreakDay(circleID: otherCircleID, memberID: $0.memberID, day: $0.day, onTime: $0.onTime) }
        XCTAssertEqual(CircleStreakPolicy.summaries(circle: circle, posts: elsewhere, now: now)[member.id]?.days, 0)
    }

    func testTimelyEntryEarnsRecognitionEvenWhenSendingAfterDeadline() async throws {
        let repo = LocalBlessingRepository(now: .now)
        let data = try await repo.bootstrap()
        let circle = try XCTUnwrap(data.circle)
        let prompt = try XCTUnwrap(data.prompt)
        try await repo.beginBlessingEntry(promptID: prompt.id, memberID: data.currentUser.id, now: prompt.startsAt)
        let blessing = try await repo.submit(promptID: prompt.id, authorID: data.currentUser.id,
            mode: .typed, body: "Finished after the timer", audioURL: nil, videoURL: nil,
            scriptureReference: nil, now: prompt.endsAt.addingTimeInterval(1))
        XCTAssertTrue(blessing.isLate)
        let refreshed = try await repo.circleContext(circleID: circle.id)
        XCTAssertEqual(refreshed.circle.streaks?[data.currentUser.id]?.onTimeToday, true)
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("sending afterward does not lose it"))
    }
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
