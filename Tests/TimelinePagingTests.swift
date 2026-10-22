import XCTest
@testable import BlessingCircle

final class TimelinePagingTests: XCTestCase {
    func testPagingScopeChangesForAccountCircleAndTimeZone() {
        let circle = UUID(), viewer = UUID()
        let first = TimelinePaging.scope(circleID: circle, viewerID: viewer, timeZoneIdentifier: "UTC")
        XCTAssertNotEqual(first, TimelinePaging.scope(circleID: circle, viewerID: UUID(), timeZoneIdentifier: "UTC"))
        XCTAssertNotEqual(first, TimelinePaging.scope(circleID: UUID(), viewerID: viewer, timeZoneIdentifier: "UTC"))
        XCTAssertNotEqual(first, TimelinePaging.scope(circleID: circle, viewerID: viewer, timeZoneIdentifier: "America/New_York"))
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("Changing accounts or the circle's time zone resets paging"))
    }
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
        XCTAssertEqual(first.lanes[0].events.count, 14)
        let second = TimelinePaging.page(lanes, before: try XCTUnwrap(first.nextBeforeDate), calendar: cal)
        let merged = TimelinePaging.merge(first.lanes, with: second.lanes)
        XCTAssertEqual(merged[0].events.count, 28)
        XCTAssertEqual(TimelinePaging.merge(merged, with: first.lanes)[0].events.count, 28)
        var last = second
        var pageCount = 2
        while let cursor = last.nextBeforeDate {
            last = TimelinePaging.page(lanes, before: cursor, calendar: cal)
            pageCount += 1
        }
        XCTAssertEqual(pageCount, 6)
        XCTAssertNil(last.nextBeforeDate)
        XCTAssertTrue(last.lanes[0].events.contains { $0.status == .joinedCircle })
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("most recent 7 days"))
    }
}
