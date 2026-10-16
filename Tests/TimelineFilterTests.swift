import XCTest
@testable import BlessingCircle

final class TimelineFilterTests: XCTestCase {
    func testListIsDefaultWhileThreadsRemainsAnExplicitChoice() {
        XCTAssertEqual(TimelineLayoutMode.defaultMode, .list)
        XCTAssertEqual(TimelineLayoutMode.allCases, [.list, .threads])
    }

    func testAllAndPersonSelectionsKeepNewestSubmissionOrder() {
        let ava = member("Ava")
        let ben = member("Ben")
        let first = blessingEvent(ava, promptAt: 100, sentAt: 500, id: "ava-late")
        let second = blessingEvent(ben, promptAt: 300, sentAt: 400, id: "ben")
        let third = blessingEvent(ava, promptAt: 200, sentAt: 250, id: "ava-earlier")
        let index = TimelineListIndex(lanes: [
            TimelineLane(member: ava, events: [third, first]),
            TimelineLane(member: ben, events: [second]),
        ])

        XCTAssertEqual(index.entries(for: nil).map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(index.entries(for: ava.id).map(\.id), [first.id, third.id])
        XCTAssertEqual(index.entries(for: ben.id).map(\.id), [second.id])
        XCTAssertTrue(index.entries(for: ava.id).allSatisfy { $0.member.id == ava.id })
    }

    func testFiltersRetainJoiningEventsAndExcludeAllUnsharedPlaceholders() {
        let ava = member("Ava")
        let joined = TimelineEvent(memberID: ava.id, date: date(100), status: .joinedCircle, id: "joined")
        let visible = blessingEvent(ava, promptAt: 200, sentAt: 220, id: "visible")
        let hiddenStatuses: [TimelineStatus] = [.locked, .missed, .waiting, .scheduled]
        let placeholders = hiddenStatuses.enumerated().map { offset, status in
            TimelineEvent(memberID: ava.id, date: date(300 + Double(offset)),
                status: status, promptKind: .daily, id: "placeholder-\(offset)")
        }
        let index = TimelineListIndex(lanes: [TimelineLane(member: ava, events: placeholders + [joined, visible])])

        XCTAssertEqual(index.entries(for: nil).map(\.id), [visible.id, joined.id])
        XCTAssertEqual(index.entries(for: ava.id).map(\.id), [visible.id, joined.id])
    }

    func testEmptyMemberRemainsSelectableButUnknownMemberHasNoEntries() {
        let ava = member("Ava")
        let ben = member("Ben")
        let index = TimelineListIndex(lanes: [
            TimelineLane(member: ava, events: [blessingEvent(ava, promptAt: 100, sentAt: 110, id: "ava")]),
            TimelineLane(member: ben, events: []),
        ])

        XCTAssertEqual(index.members.map(\.id), [ava.id, ben.id])
        XCTAssertEqual(index.validSelection(ben.id), ben.id)
        XCTAssertTrue(index.entries(for: ben.id).isEmpty)
        let outsider = UUID()
        XCTAssertNil(index.validSelection(outsider))
        XCTAssertTrue(index.entries(for: outsider).isEmpty)
        XCTAssertNil(index.validSelection(nil))
    }

    func testRemovedMemberSelectionReturnsToAllOnRebuiltPage() {
        let ava = member("Ava")
        let ben = member("Ben")
        let before = TimelineListIndex(lanes: [TimelineLane(member: ava, events: []), TimelineLane(member: ben, events: [])])
        let after = TimelineListIndex(lanes: [TimelineLane(member: ben, events: [])])

        XCTAssertEqual(before.validSelection(ava.id), ava.id)
        XCTAssertNil(after.validSelection(ava.id))
        XCTAssertEqual(after.validSelection(ben.id), ben.id)
    }

    func testRebuiltIndexIncludesOlderHistoryAndNewPostsWithoutLosingPersonSelection() {
        let ava = member("Ava")
        let initial = blessingEvent(ava, promptAt: 200, sentAt: 220, id: "initial")
        let older = blessingEvent(ava, promptAt: 100, sentAt: 110, id: "older")
        let newer = blessingEvent(ava, promptAt: 300, sentAt: 330, id: "newer")
        let before = TimelineListIndex(lanes: [TimelineLane(member: ava, events: [initial])])
        let after = TimelineListIndex(lanes: [TimelineLane(member: ava, events: [initial, older, newer])])

        XCTAssertEqual(before.entries(for: ava.id).map(\.id), [initial.id])
        XCTAssertEqual(after.validSelection(ava.id), ava.id)
        XCTAssertEqual(after.entries(for: ava.id).map(\.id), [newer.id, initial.id, older.id])
        XCTAssertEqual(after.entries(for: nil).map(\.id), [newer.id, initial.id, older.id])
    }

    func testEqualTimestampsHaveStableOrderAcrossLaneOrderChanges() {
        let ava = member("Ava")
        let ben = member("Ben")
        let a = TimelineLane(member: ava, events: [blessingEvent(ava, promptAt: 100, sentAt: 200, id: "a")])
        let b = TimelineLane(member: ben, events: [blessingEvent(ben, promptAt: 100, sentAt: 200, id: "b")])

        XCTAssertEqual(TimelineListIndex(lanes: [a, b]).entries(for: nil).map(\.id), ["a", "b"])
        XCTAssertEqual(TimelineListIndex(lanes: [b, a]).entries(for: nil).map(\.id), ["a", "b"])
    }

    private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    private func member(_ name: String) -> Member {
        Member(id: UUID(), displayName: name, initials: String(name.prefix(1)), tintSeed: 1)
    }

    private func blessingEvent(_ member: Member, promptAt: Double, sentAt: Double, id: String) -> TimelineEvent {
        let blessing = Blessing(id: UUID(), circleID: UUID(), promptID: UUID(), authorID: member.id,
            captureMode: .typed, body: id, audioURL: nil, videoURL: nil,
            submittedAt: date(sentAt), isLate: sentAt > promptAt + 600, scriptureReference: nil)
        return TimelineEvent(memberID: member.id, date: date(promptAt), status: .blessing(blessing),
            promptKind: .daily, id: id)
    }
}
