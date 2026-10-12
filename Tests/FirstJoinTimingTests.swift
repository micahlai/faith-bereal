import XCTest
@testable import BlessingCircle

final class FirstJoinTimingTests: XCTestCase {
    func testScheduledServerTargetDoesNotOpenFirstDayEarly() async throws {
        let repo = LocalBlessingRepository(now: .now)
        let bootstrap = try await repo.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        var prompt = try XCTUnwrap(bootstrap.prompt)
        prompt.notificationHasStarted = false
        XCTAssertEqual(prompt.phase(at: prompt.endsAt.addingTimeInterval(1)), .scheduled)
        XCTAssertFalse(FirstDaySubmissionPolicy.isEligible(memberJoinedAt: prompt.startsAt,
            prompt: prompt, circle: circle, now: prompt.startsAt.addingTimeInterval(1)))
        let decoded = try JSONDecoder().decode(DailyPrompt.self, from: JSONEncoder().encode(prompt))
        XCTAssertEqual(decoded.notificationHasStarted, false)
    }
    func testWelcomeTargetsYesterdayBeforeNotificationAndTodayAfterIt() async throws {
        let repo = LocalBlessingRepository(now: .now)
        let initial = try await repo.bootstrap()
        var settings = CircleConfiguration.defaults(timeZoneIdentifier: "UTC")
        settings.name = "New welcome circle"
        let cal = CircleLocalDay.calendar(timeZoneIdentifier: "UTC")
        let minute = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        guard minute < 1_438 else { throw XCTSkip("No remaining same-day future slot") }
        settings.randomWindowStartMinutes = minute + 1
        settings.randomWindowEndMinutes = 1_439
        settings.endOfDayMinutes = 1_439
        let circle = try await repo.createCircle(configuration: settings, member: initial.currentUser)
        let now = Date()
        let context = try await repo.circleContext(circleID: circle.id)
        let welcome = try XCTUnwrap(context.prompt)
        let cutoff = try XCTUnwrap(welcome.firstJoinEndsAt)
        XCTAssertEqual(welcome.localDate, cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)))
        XCTAssertTrue(FirstDaySubmissionPolicy.isEligible(memberJoinedAt: now, prompt: welcome, circle: circle, now: now))
        XCTAssertFalse(FirstDaySubmissionPolicy.isEligible(memberJoinedAt: now, prompt: welcome, circle: circle, now: cutoff))
        let blessing = try await repo.submit(promptID: welcome.id, authorID: initial.currentUser.id, mode: .typed,
            body: "Welcome", audioURL: nil, videoURL: nil, scriptureReference: nil, now: now)
        let lanes = try await repo.timeline(circleID: circle.id, viewerID: initial.currentUser.id, now: now)
        XCTAssertTrue(lanes.flatMap(\.events).contains { if case let .blessing(b) = $0.status { b.id == blessing.id } else { false } })
    }

    func testFirstJoinCalendarCutoffsUseCircleTimeZone() throws {
        let cal = CircleLocalDay.calendar(timeZoneIdentifier: "America/New_York")
        let day = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let user = Member(id: UUID(), displayName: "New", initials: "N", tintSeed: 1, joinedAt: day.addingTimeInterval(4*3600))
        let circle = CircleGroup(id: UUID(), name: "DST", inviteCode: "TEST", ownerID: user.id, members: [user], timeZoneIdentifier: "America/New_York", randomWindowStartMinutes: 720, randomWindowEndMinutes: 1_320,
            responseWindowMinutes: 10, allowsLateBlessings: false, repeatWindowMinutes: 60)
        let start = day.addingTimeInterval(12*3600)
        let prompt = DailyPrompt(id: UUID(), circleID: circle.id, localDate: day, startsAt: start, endsAt: start.addingTimeInterval(600))
        XCTAssertFalse(FirstDaySubmissionPolicy.isEligible(memberJoinedAt: user.joinedAt, prompt: prompt, circle: circle, now: start.addingTimeInterval(-1)))
        XCTAssertTrue(FirstDaySubmissionPolicy.isEligible(memberJoinedAt: user.joinedAt, prompt: prompt, circle: circle, now: start.addingTimeInterval(3600)))
        let nextDay = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: day))
        XCTAssertFalse(FirstDaySubmissionPolicy.isEligible(memberJoinedAt: user.joinedAt, prompt: prompt, circle: circle, now: nextDay))
        XCTAssertEqual(nextDay.timeIntervalSince(day), 25*3600)
    }
}
