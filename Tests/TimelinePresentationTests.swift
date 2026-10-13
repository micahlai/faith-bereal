import XCTest
@testable import BlessingCircle

final class TimelinePresentationTests: XCTestCase {
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
