import XCTest
@testable import BlessingCircle

final class LocalDemoMidnightTests: XCTestCase {
    private let circleID = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    private var midnight: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 10))!
    }

    func testFirstMinuteUsesCurrentDayStartAndExactTenMinuteWindow() async throws {
        for seconds in [0.0, 20.0, 59.0] {
            let now = midnight.addingTimeInterval(seconds)
            let repository = LocalBlessingRepository(now: now)
            let value = await repository.currentDailyPrompt(circleID: circleID, now: now)
            let prompt = try XCTUnwrap(value)
            XCTAssertEqual(prompt.startsAt, midnight)
            XCTAssertEqual(prompt.localDate, midnight)
            XCTAssertEqual(prompt.endsAt.timeIntervalSince(prompt.startsAt), 600)
            XCTAssertEqual(prompt.phase(at: now), .open)
            XCTAssertTrue(prompt.occursOnCircleDay(at: now, timeZoneIdentifier: TimeZone.current.identifier))
            XCTAssertEqual(prompt.phase(at: prompt.endsAt.addingTimeInterval(-0.001)), .open)
            XCTAssertEqual(prompt.phase(at: prompt.endsAt), .closed)
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: midnight)!
            XCTAssertFalse(prompt.occursOnCircleDay(at: tomorrow, timeZoneIdentifier: TimeZone.current.identifier))
            try await repository.beginBlessingEntry(promptID: prompt.id,
                memberID: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!, now: now)
        }
    }

    func testNoonRetainsPreviouslyElapsedMinute() async throws {
        let now = midnight.addingTimeInterval(12 * 3_600)
        let repository = LocalBlessingRepository(now: now)
        let value = await repository.currentDailyPrompt(circleID: circleID, now: now)
        let prompt = try XCTUnwrap(value)
        XCTAssertEqual(prompt.startsAt, now.addingTimeInterval(-60))
        XCTAssertEqual(prompt.endsAt, prompt.startsAt.addingTimeInterval(600))
        XCTAssertEqual(prompt.phase(at: now), .open)
    }

    func testStreakFixturePreservesItsDeliberatelyElapsedWindow() async throws {
        let now = midnight.addingTimeInterval(20)
        let repository = LocalBlessingRepository(now: now, streakTestFixture: true)
        let value = await repository.currentDailyPrompt(circleID: circleID, now: now)
        let prompt = try XCTUnwrap(value)
        XCTAssertEqual(prompt.startsAt, now.addingTimeInterval(-1_200))
        XCTAssertEqual(prompt.endsAt.timeIntervalSince(prompt.startsAt), 600)
        XCTAssertEqual(prompt.phase(at: now), .closed)
    }
}
