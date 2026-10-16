import XCTest
@testable import BlessingCircle

final class StreakRefreshTests: XCTestCase {
    @MainActor
    func testSendingAfterDeadlineRefreshesDisplayedGeneralAndTimelyRunsFromEntryGrant() async throws {
        let fixture = try await StreakRefreshFixture()
        defer { fixture.removeFiles() }
        let prompt = try XCTUnwrap(fixture.model.prompt)
        let before = try fixture.displayedStreak()
        XCTAssertEqual(before.days, 4)
        XCTAssertEqual(before.onTimeStreakDays, 0, "The random window has already closed without a completed post.")
        XCTAssertLessThan(prompt.endsAt, Date())
        let entered = await fixture.model.openCapture(for: prompt, now: prompt.startsAt.addingTimeInterval(1))
        XCTAssertTrue(entered)

        let sent = await fixture.model.submit(mode: .typed, body: "Finished after entering on time",
            audioURL: nil, videoURL: nil, scriptureReference: nil)
        XCTAssertTrue(sent)
        let blessing = try XCTUnwrap(fixture.model.submittedBlessing)
        XCTAssertTrue(blessing.isLate)
        let displayed = try fixture.displayedStreak()
        XCTAssertEqual(displayed.days, before.days + 1)
        XCTAssertEqual(displayed.onTimeStreakDays, before.days + 1,
            "The displayed timely run uses entry, even when sending finishes after the random deadline.")
        try fixture.assertCircleListMatchesDisplayed()
        XCTAssertTrue(fixture.model.lanes.flatMap(\.events).contains { event in
            if case let .blessing(item) = event.status { return item.id == blessing.id }
            return false
        })
    }

    @MainActor
    func testEveningOnlySubmissionRefreshesDisplayedGeneralWithoutAwardingTimelyDay() async throws {
        let fixture = try await StreakRefreshFixture()
        defer { fixture.removeFiles() }
        let evening = try XCTUnwrap(fixture.model.endOfDayPrompt)
        let before = try fixture.displayedStreak()
        let entered = await fixture.model.openCapture(for: evening, now: fixture.now)
        XCTAssertTrue(entered)

        let sent = await fixture.model.submit(mode: .typed, body: "An evening blessing",
            audioURL: nil, videoURL: nil, scriptureReference: nil)
        XCTAssertTrue(sent)
        let displayed = try fixture.displayedStreak()
        XCTAssertEqual(displayed.days, before.days + 1)
        XCTAssertEqual(displayed.onTimeStreakDays, 0)
        XCTAssertFalse(displayed.onTimeToday)
        try fixture.assertCircleListMatchesDisplayed()
    }

    @MainActor
    func testLateRandomEntryRefreshesGeneralButKeepsTimelyRunBroken() async throws {
        let fixture = try await StreakRefreshFixture()
        defer { fixture.removeFiles() }
        let prompt = try XCTUnwrap(fixture.model.prompt)
        let before = try fixture.displayedStreak()
        let entered = await fixture.model.openCapture(for: prompt, now: prompt.endsAt.addingTimeInterval(1))
        XCTAssertTrue(entered)

        let sent = await fixture.model.submit(mode: .typed, body: "Entered late",
            audioURL: nil, videoURL: nil, scriptureReference: nil)
        XCTAssertTrue(sent)
        let displayed = try fixture.displayedStreak()
        XCTAssertEqual(displayed.days, before.days + 1)
        XCTAssertEqual(displayed.onTimeStreakDays, 0)
        XCTAssertFalse(displayed.onTimeToday)
        try fixture.assertCircleListMatchesDisplayed()
    }

    @MainActor
    func testReusingBlessingFetchesFreshStreakMetadataAlongsideTimeline() async throws {
        let fixture = try await StreakRefreshFixture()
        defer { fixture.removeFiles() }
        let evening = try XCTUnwrap(fixture.model.endOfDayPrompt)
        let user = try XCTUnwrap(fixture.model.currentUser)
        let before = try fixture.displayedStreak()
        // Reuse requires a source from another circle. Complete that source
        // after this presentation loads, then reuse it into the current evening.
        let sourceCircle = try XCTUnwrap(fixture.model.circles.first { $0.id != fixture.model.circle?.id })
        let sourceContext = try await fixture.repository.circleContext(circleID: sourceCircle.id)
        let sourcePrompt = try XCTUnwrap(sourceContext.prompt)
        try await fixture.repository.beginBlessingEntry(promptID: sourcePrompt.id, memberID: user.id,
            now: sourcePrompt.startsAt.addingTimeInterval(1))
        let source = try await fixture.repository.submit(promptID: sourcePrompt.id, authorID: user.id,
            mode: .typed, body: "A recent source blessing", audioURL: nil, videoURL: nil,
            scriptureReference: nil, now: fixture.now)
        XCTAssertNotEqual(source.circleID, fixture.model.circle?.id)
        XCTAssertEqual(try fixture.displayedStreak().days, before.days)
        let entered = await fixture.model.openCapture(for: evening, now: fixture.now)
        XCTAssertTrue(entered)

        let reused = await fixture.model.repeatBlessing(source, now: fixture.now)
        XCTAssertTrue(reused, fixture.model.message ?? "Reuse should succeed for the recent source from another circle.")
        let displayed = try fixture.displayedStreak()
        XCTAssertEqual(displayed.days, before.days + 1)
        XCTAssertEqual(displayed.onTimeStreakDays, 0, "Reusing into an evening prompt earns no random on-time day.")
        try fixture.assertCircleListMatchesDisplayed()
    }
}

@MainActor
private struct StreakRefreshFixture {
    let now = Date()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StreakRefresh-\(UUID())")
    let repository: LocalBlessingRepository
    let model: AppModel

    init() async throws {
        // Keep all authored submission timestamps in the past without waiting
        // for a wall-clock deadline or launching optional background readers.
        repository = LocalBlessingRepository(now: now.addingTimeInterval(-1_200),
            endOfDayStartsAt: now.addingTimeInterval(-60))
        let seed = try await repository.bootstrap()
        model = AppModel(repository: repository,
            savedBlessingStore: SavedBlessingStore(root: root.appendingPathComponent("saved")),
            draftStore: BlessingDraftStore(root: root.appendingPathComponent("drafts")),
            diagnosticCollection: DiagnosticCollectionController(
                store: BackendDiagnosticStore(root: root.appendingPathComponent("diagnostics"))),
            metadataStore: CircleMetadataStore(directory: root.appendingPathComponent("metadata")),
            registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
        model.currentUser = seed.currentUser
        model.circles = seed.circles
        model.circle = seed.circle
        model.prompt = seed.prompt
        model.endOfDayPrompt = seed.endOfDayPrompt
        model.loadState = .ready
        try await model.refreshTimeline(now: now, freshCircle: seed.circle)
    }

    func displayedStreak() throws -> CircleStreak {
        let userID = try XCTUnwrap(model.currentUser?.id)
        return try XCTUnwrap(model.circle?.streaks?[userID])
    }

    func assertCircleListMatchesDisplayed(file: StaticString = #filePath, line: UInt = #line) throws {
        let displayed = try displayedStreak()
        let listed = try XCTUnwrap(model.circles.first { $0.id == model.circle?.id }?.streaks?[displayed.memberID],
            file: file, line: line)
        XCTAssertEqual(listed, displayed, file: file, line: line)
        XCTAssertFalse(model.isPageLoading, file: file, line: line)
    }

    func removeFiles() {
        model.diagnosticCollection.deactivate()
        model.currentUser = nil
        model.circle = nil
        try? FileManager.default.removeItem(at: root)
    }
}
