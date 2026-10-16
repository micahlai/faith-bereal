import XCTest
@testable import BlessingCircle

final class StreakPresentationTests: XCTestCase {
    func testMixedProfileRetainsOverallCountAndBothPopupCounts() {
        let streak = summary(overall: 5, timely: 3)
        XCTAssertEqual(streak.profileIndicator?.kind, .overall)
        XCTAssertEqual(streak.profileIndicator?.count, 5)
        XCTAssertEqual(streak.days, 5)
        XCTAssertEqual(streak.onTimeStreakDays, 3)
    }

    func testEqualPositiveRunsUseBlueProfileWithoutChangingCount() {
        let streak = summary(overall: 5, timely: 5)
        XCTAssertEqual(streak.profileIndicator?.kind, .onTime)
        XCTAssertEqual(streak.profileIndicator?.count, 5)
    }

    func testProfileColorUsesConsecutiveTimelyRunRatherThanTimelyTotal() {
        let streak = CircleStreak(memberID: UUID(), days: 5, onTimeDays: 5,
            onTimeToday: false, onTimeStreakDays: 0)
        XCTAssertEqual(streak.profileIndicator?.kind, .overall)
        XCTAssertEqual(streak.profileIndicator?.count, 5)
    }

    func testCircleShowsBothPositiveCountsEvenWhenEqual() {
        for timely in [3, 5] {
            let indicators = summary(overall: 5, timely: timely).circleIndicators
            XCTAssertEqual(indicators.map(\.kind), [.overall, .onTime])
            XCTAssertEqual(indicators.map(\.count), [5, timely])
        }
    }

    func testCircleShowsGeneralOnlyWhenTimelyIsZeroAndNoneWhenBothZero() {
        let generalOnly = summary(overall: 5, timely: 0)
        XCTAssertEqual(generalOnly.circleIndicators.map(\.kind), [.overall])
        XCTAssertEqual(generalOnly.circleIndicators.map(\.count), [5])
        let empty = summary(overall: 0, timely: 0)
        XCTAssertNil(empty.profileIndicator)
        XCTAssertTrue(empty.circleIndicators.isEmpty)
    }

    private func summary(overall: Int, timely: Int) -> CircleStreak {
        CircleStreak(memberID: UUID(), days: overall, onTimeDays: timely,
            onTimeToday: timely > 0, onTimeStreakDays: timely)
    }
}
