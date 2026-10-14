import XCTest
@testable import BlessingCircle

final class TimelinePresentationTests: XCTestCase {
    func testTimelineZoomHasReadableBoundsAndReset() {
        XCTAssertEqual(TimelineSizing.clamped(0), 168)
        XCTAssertEqual(TimelineSizing.clamped(1_000), 360)
        XCTAssertEqual(TimelineSizing.clamped(.nan), 204)
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("Smaller, Larger, and Reset size"))
    }
    func testNotificationTimesDeduplicateAcrossMembersAndExcludeWelcomeAndEvening() {
        let time = Date(timeIntervalSince1970: 100)
        let event = TimelineEvent(memberID: UUID(), date: time, status: .missed,
            promptKind: .daily, notificationStartedAt: time)
        let welcome = TimelineEvent(memberID: UUID(), date: time, status: .waiting,
            promptKind: .daily, isWelcome: true, notificationStartedAt: time.addingTimeInterval(-10))
        let evening = TimelineEvent(memberID: UUID(), date: time, status: .missed,
            promptKind: .endOfDay, notificationStartedAt: time.addingTimeInterval(200))
        XCTAssertEqual(TimelinePresentation.notificationTimes([event, event, welcome, evening]).map(\.date), [time])
        XCTAssertTrue(TimelinePresentation.notificationTimes([evening]).isEmpty)
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("only the actual random blessing notification time"))
    }
    func testUnstartedPromptsHaveNoTimelinePlaceholder() {
        let member = Member(id: UUID(), displayName: "A", initials: "A", tintSeed: 1)
        let scheduled = TimelineEvent(memberID: member.id, date: .now, status: .scheduled, promptKind: .daily)
        XCTAssertTrue(TimelinePresentation.lanes([TimelineLane(member: member, events: [scheduled])], calendar: .current)[0].events.isEmpty)
    }
    func testListContainsOnlyActualEventsInNewestFirstOrder() {
        let member = Member(id: UUID(), displayName: "A", initials: "A", tintSeed: 1)
        let joined = TimelineEvent(memberID: member.id, date: Date(timeIntervalSince1970: 100), status: .joinedCircle)
        let missed = TimelineEvent(memberID: member.id, date: Date(timeIntervalSince1970: 300), status: .missed, promptKind: .daily)
        let other = TimelineEvent(memberID: UUID(), date: Date(timeIntervalSince1970: 200), status: .joinedCircle)
        let entries = TimelinePresentation.listEntries([TimelineLane(member: member, events: [joined, missed, other])])
        XCTAssertEqual(entries.map(\.id), [other.id, joined.id])
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("List does not include missed days"))
    }
    func testWelcomeDisplayMovesWithoutChangingPromptOrCollidingWithRegularEvent() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: .now)
        let member = Member(id: UUID(), displayName: "New", initials: "N", tintSeed: 1,
            joinedAt: day.addingTimeInterval(100))
        let welcome = Blessing(id: UUID(), circleID: UUID(), promptID: UUID(),
            authorID: member.id, captureMode: .typed, body: "Welcome", audioURL: nil, videoURL: nil,
            submittedAt: day.addingTimeInterval(200), isLate: true, scriptureReference: nil)
        let previous = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: day))
        let old = TimelineEvent(memberID: member.id, date: previous, status: .blessing(welcome), promptKind: .daily)
        let regular = TimelineEvent(memberID: member.id, date: day, status: .waiting, promptKind: .daily)
        let result = TimelinePresentation.lanes([TimelineLane(member: member, events: [old, regular])], calendar: calendar)[0]
        XCTAssertEqual(result.events[0].date, day)
        XCTAssertTrue(result.events[0].isWelcome)
        XCTAssertNotEqual(result.events[0].id, result.events[1].id)
        XCTAssertEqual(result.events[0].status, old.status)
        XCTAssertEqual(old.date, previous)
        XCTAssertTrue(HelpTopic.timeline.steps.map(\.body).joined().contains("changes only its display"))
    }
}
