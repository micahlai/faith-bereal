import XCTest
@testable import BlessingCircle

final class TimelinePagingTests: XCTestCase {
    func testPagesPreserveWholeDaysAndMergeWithoutDuplicates() throws {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: .now)
        let member = Member(id: UUID(), displayName: "A", initials: "A", tintSeed: 1,
            joinedAt: cal.date(byAdding: .day, value: -40, to: today)!)
        let events = (0..<40).flatMap { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            return [PromptKind.daily, .endOfDay].map { TimelineEvent(memberID: member.id, date: day, status: .missed, promptKind: $0) }
        } + [TimelineEvent(memberID: member.id, date: member.joinedAt, status: .joinedCircle)]
        let lanes = [TimelineLane(member: member, events: events)]
        let first = TimelinePaging.page(lanes, before: nil, calendar: cal)
        XCTAssertEqual(first.lanes[0].events.count, 28)
        let second = TimelinePaging.page(lanes, before: try XCTUnwrap(first.nextBeforeDate), calendar: cal)
        let merged = TimelinePaging.merge(first.lanes, with: second.lanes)
        XCTAssertEqual(merged[0].events.count, 56)
        XCTAssertEqual(TimelinePaging.merge(merged, with: first.lanes)[0].events.count, 56)
        let last = TimelinePaging.page(lanes, before: second.nextBeforeDate, calendar: cal)
        XCTAssertNil(last.nextBeforeDate)
        XCTAssertTrue(last.lanes[0].events.contains { $0.status == .joinedCircle })
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("most recent 14 days"))
    }
}
