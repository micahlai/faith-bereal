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
        let repo = LocalBlessingRepository(now: Date().addingTimeInterval(-20 * 60))
        let data = try await repo.bootstrap()
        let circle = try XCTUnwrap(data.circle)
        let prompt = try XCTUnwrap(data.prompt)
        try await repo.beginBlessingEntry(promptID: prompt.id, memberID: data.currentUser.id, now: prompt.startsAt)
        let blessing = try await repo.submit(promptID: prompt.id, authorID: data.currentUser.id,
            mode: .typed, body: "Finished after the timer", audioURL: nil, videoURL: nil,
            scriptureReference: nil, now: prompt.endsAt.addingTimeInterval(1))
        XCTAssertTrue(blessing.isLate)
        let refreshed = try await repo.circleContext(circleID: circle.id)
        let streak = try XCTUnwrap(refreshed.circle.streaks?[data.currentUser.id])
        XCTAssertGreaterThan(streak.onTimeStreakDays, 0)
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier)
        XCTAssertEqual(streak.onTimeToday, calendar.isDate(prompt.localDate, inSameDayAs: Date()))
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

extension CircleStreakTests {
    func testFiveOverallDaysAndLastThreeTimelyRemainIndependent() async throws {
        let fixture = try await StreakFixture()
        let posts = (-4...0).map { fixture.post($0, timely: $0 >= -2) }
        let result = try fixture.summary(posts, at: fixture.date(0, hour: 13))
        XCTAssertEqual(result.days, 5)
        XCTAssertEqual(result.onTimeStreakDays, 3)
        XCTAssertEqual(result.onTimeDays, 3)
    }

    func testEveningOnlyCountsGeneralAndResetsTimelyAfterRandomWindow() async throws {
        let fixture = try await StreakFixture()
        let posts = [fixture.post(-2, timely: true), fixture.post(-1, timely: true),
            fixture.post(0, timely: true, kind: .endOfDay)]
        let result = try fixture.summary(posts, at: fixture.date(0, hour: 23))
        XCTAssertEqual(result.days, 3)
        XCTAssertEqual(result.onTimeStreakDays, 0)
        XCTAssertFalse(result.onTimeToday)
        XCTAssertEqual(result.onTimeDays, 2, "An evening submission must never earn timely recognition.")
    }

    func testDailyAndEveningCountOnceAndEveningDoesNotUndoTimelyDaily() async throws {
        let fixture = try await StreakFixture()
        let posts = [fixture.post(-1, timely: true), fixture.post(0, timely: true),
            fixture.post(0, timely: false, kind: .endOfDay)]
        let result = try fixture.summary(posts, at: fixture.date(0, hour: 23))
        XCTAssertEqual(result.days, 2)
        XCTAssertEqual(result.onTimeStreakDays, 2)
        XCTAssertEqual(result.onTimeDays, 2)
        XCTAssertTrue(result.onTimeToday)
    }

    func testRandomWindowResolvesTimelyIndependentlyFromGeneralWindow() async throws {
        let fixture = try await StreakFixture()
        let posts = [fixture.post(-2, timely: true), fixture.post(-1, timely: true)]
        let pending = try fixture.summary(posts, at: fixture.date(0, hour: 12, minute: 9))
        XCTAssertEqual(pending.days, 2)
        XCTAssertEqual(pending.onTimeStreakDays, 2)
        let randomClosed = try fixture.summary(posts, at: fixture.date(0, hour: 12, minute: 10))
        XCTAssertEqual(randomClosed.days, 2)
        XCTAssertEqual(randomClosed.onTimeStreakDays, 0)
        let eveningStillOpen = try fixture.summary(posts, at: fixture.date(1, hour: 4, minute: 59))
        XCTAssertEqual(eveningStillOpen.days, 2)
        XCTAssertEqual(eveningStillOpen.onTimeStreakDays, 0)
        let eveningClosed = try fixture.summary(posts, at: fixture.date(1, hour: 5))
        XCTAssertEqual(eveningClosed.days, 0)
        XCTAssertEqual(eveningClosed.onTimeStreakDays, 0)
    }

    func testPostingResolvesEachCountBeforeItsDeadline() async throws {
        let fixture = try await StreakFixture()
        let history = [fixture.post(-2, timely: true), fixture.post(-1, timely: true)]
        let timely = try fixture.summary(history + [fixture.post(0, timely: true)],
            at: fixture.date(0, hour: 12, minute: 5))
        XCTAssertEqual(timely.days, 3)
        XCTAssertEqual(timely.onTimeStreakDays, 3)
        let late = try fixture.summary(history + [fixture.post(0, timely: false)],
            at: fixture.date(0, hour: 12, minute: 5))
        XCTAssertEqual(late.days, 3)
        XCTAssertEqual(late.onTimeStreakDays, 0)
        var earlyEveningPrompts = fixture.prompts
        earlyEveningPrompts.removeAll { $0.kind == .endOfDay && $0.localDate == fixture.date(0) }
        earlyEveningPrompts.append(DailyPrompt(id: UUID(), circleID: fixture.circle.id,
            localDate: fixture.date(0), startsAt: fixture.date(0, hour: 12, minute: 1),
            endsAt: fixture.date(0, hour: 19, minute: 1), kind: .endOfDay))
        let evening = try fixture.summary(history + [fixture.post(0, timely: true, kind: .endOfDay)],
            prompts: earlyEveningPrompts, at: fixture.date(0, hour: 12, minute: 5))
        XCTAssertEqual(evening.days, 3)
        XCTAssertEqual(evening.onTimeStreakDays, 2, "Evening cannot resolve an unfinished random prompt.")
    }

    func testNextRandomPromptClosesPreviousEveningBeforeSevenHours() async throws {
        let fixture = try await StreakFixture()
        let posts = [fixture.post(-2, timely: true), fixture.post(-1, timely: true)]
        var prompts = fixture.prompts
        prompts.removeAll { $0.kind == .daily && $0.localDate == fixture.date(1) }
        let nextStart = fixture.date(1, hour: 3)
        prompts.append(DailyPrompt(id: UUID(), circleID: fixture.circle.id, localDate: fixture.date(1),
            startsAt: nextStart, endsAt: nextStart.addingTimeInterval(600)))
        let before = try fixture.summary(posts, prompts: prompts, at: nextStart.addingTimeInterval(-1))
        XCTAssertEqual(before.days, 2)
        let after = try fixture.summary(posts, prompts: prompts, at: nextStart)
        XCTAssertEqual(after.days, 0)
    }

    func testScheduledTargetPassingDoesNotResolveUnstartedRandomWindow() async throws {
        let fixture = try await StreakFixture()
        let history = [fixture.post(-2, timely: true), fixture.post(-1, timely: true)]
        var prompts = fixture.prompts
        let index = try XCTUnwrap(prompts.firstIndex { $0.kind == .daily && $0.localDate == fixture.date(0) })
        prompts[index].notificationHasStarted = false
        let scheduled = try fixture.summary(history, prompts: prompts, at: fixture.date(0, hour: 13))
        XCTAssertEqual(scheduled.days, 2)
        XCTAssertEqual(scheduled.onTimeStreakDays, 2)
        prompts[index].notificationHasStarted = true
        let authored = try fixture.summary(history, prompts: prompts, at: fixture.date(0, hour: 13))
        XCTAssertEqual(authored.days, 2)
        XCTAssertEqual(authored.onTimeStreakDays, 0)
    }

    func testDeadlineMetadataRoundTripsAndLegacyPayloadHasNoDeadline() throws {
        let memberID = UUID()
        let deadline = ISO8601DateFormatter().date(from: "2026-10-15T12:10:00Z")!
        let summary = CircleStreak(memberID: memberID, days: 5, onTimeDays: 3,
            onTimeToday: false, onTimeStreakDays: 3, nextUpdateAt: deadline)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(CircleStreak.self, from: encoder.encode(summary)), summary)
        let legacy = ["member_id": memberID.uuidString, "days": 5, "on_time_days": 3,
                      "on_time_today": false] as [String: Any]
        XCTAssertNil(try decoder.decode(CircleStreak.self,
            from: JSONSerialization.data(withJSONObject: legacy)).nextUpdateAt)
    }

    func testRepositoryEveningSubmissionImmediatelyIncrementsGeneralOnly() async throws {
        let now = Date()
        let repo = LocalBlessingRepository(now: now, endOfDayStartsAt: now.addingTimeInterval(-60))
        let bootstrap = try await repo.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let evening = try XCTUnwrap(bootstrap.endOfDayPrompt)
        let before = try XCTUnwrap(circle.streaks?[bootstrap.currentUser.id])
        try await repo.beginBlessingEntry(promptID: evening.id, memberID: bootstrap.currentUser.id, now: now)
        _ = try await repo.submit(promptID: evening.id, authorID: bootstrap.currentUser.id,
            mode: .typed, body: "Evening only", audioURL: nil, videoURL: nil,
            scriptureReference: nil, now: now)
        let refreshed = try await repo.circleContext(circleID: circle.id)
        let after = try XCTUnwrap(refreshed.circle.streaks?[bootstrap.currentUser.id])
        XCTAssertEqual(after.days, before.days + 1)
        XCTAssertEqual(after.onTimeStreakDays, before.onTimeStreakDays)
        XCTAssertFalse(after.onTimeToday)
    }

    func testRepositoryDailyThenEveningImmediatelyCountsOneGeneralDay() async throws {
        let now = Date()
        let repo = LocalBlessingRepository(now: now, endOfDayStartsAt: now.addingTimeInterval(-60))
        let bootstrap = try await repo.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let before = try XCTUnwrap(circle.streaks?[bootstrap.currentUser.id])
        for prompt in [try XCTUnwrap(bootstrap.prompt), try XCTUnwrap(bootstrap.endOfDayPrompt)] {
            try await repo.beginBlessingEntry(promptID: prompt.id, memberID: bootstrap.currentUser.id, now: now)
            _ = try await repo.submit(promptID: prompt.id, authorID: bootstrap.currentUser.id,
                mode: .typed, body: "Shared for this prompt", audioURL: nil, videoURL: nil,
                scriptureReference: nil, now: now)
        }
        let refreshed = try await repo.circleContext(circleID: circle.id)
        let after = try XCTUnwrap(refreshed.circle.streaks?[bootstrap.currentUser.id])
        XCTAssertEqual(after.days, before.days + 1)
        XCTAssertEqual(after.onTimeStreakDays, before.onTimeStreakDays + 1)
        XCTAssertTrue(after.onTimeToday)
    }

    func testNextUpdateTracksTheNextUnresolvedWindowAndClearsAfterPosting() async throws {
        let fixture = try await StreakFixture()
        let history = [fixture.post(-2, timely: true), fixture.post(-1, timely: true)]
        let pending = try fixture.summary(history, at: fixture.date(0, hour: 12, minute: 5))
        XCTAssertEqual(pending.nextUpdateAt, fixture.date(0, hour: 12, minute: 10))
        let randomClosed = try fixture.summary(history, at: fixture.date(0, hour: 13))
        XCTAssertEqual(randomClosed.nextUpdateAt, fixture.date(1, hour: 5))
        let posted = try fixture.summary(history + [fixture.post(0, timely: true)],
            at: fixture.date(0, hour: 12, minute: 5))
        XCTAssertNil(posted.nextUpdateAt)
    }

}

private struct StreakFixture {
    var circle: CircleGroup
    let memberID: UUID
    let origin = ISO8601DateFormatter().date(from: "2026-10-15T00:00:00Z")!
    var prompts: [DailyPrompt] {
        (-5...1).flatMap { offset in
            [DailyPrompt(id: UUID(), circleID: circle.id, localDate: date(offset),
                startsAt: date(offset, hour: 12), endsAt: date(offset, hour: 12, minute: 10)),
             DailyPrompt(id: UUID(), circleID: circle.id, localDate: date(offset),
                startsAt: date(offset, hour: 22), endsAt: date(offset + 1, hour: 5), kind: .endOfDay)]
        }
    }

    init() async throws {
        let bootstrap = try await LocalBlessingRepository().bootstrap()
        var circle = try XCTUnwrap(bootstrap.circle)
        circle.timeZoneIdentifier = "UTC"
        var member = bootstrap.currentUser
        member.joinedAt = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        circle.members = [member]
        self.circle = circle
        self.memberID = member.id
    }

    func date(_ offset: Int, hour: Int = 0, minute: Int = 0) -> Date {
        origin.addingTimeInterval(Double(offset * 86_400 + hour * 3_600 + minute * 60))
    }

    func post(_ offset: Int, timely: Bool, kind: PromptKind = .daily) -> StreakDay {
        StreakDay(circleID: circle.id, memberID: memberID, day: date(offset), onTime: timely, kind: kind)
    }

    func summary(_ posts: [StreakDay], prompts: [DailyPrompt]? = nil, at now: Date) throws -> CircleStreak {
        try XCTUnwrap(CircleStreakPolicy.summaries(circle: circle, posts: posts,
            prompts: prompts ?? self.prompts, now: now)[memberID])
    }
}
