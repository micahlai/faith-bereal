import XCTest
@testable import BlessingCircle

final class DomainRulesTests: XCTestCase {
    func testCurrentDayPeerContentRequiresViewerSubmission() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertFalse(
            VisibilityPolicy.canReadPeerBlessing(
                promptDate: now,
                now: now,
                viewerHasSubmitted: false,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            VisibilityPolicy.canReadPeerBlessing(
                promptDate: now,
                now: now,
                viewerHasSubmitted: true,
                calendar: calendar
            )
        )
    }

    func testHistoricalContentIsAlwaysVisibleToMembers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        XCTAssertTrue(
            VisibilityPolicy.canReadPeerBlessing(
                promptDate: yesterday,
                now: now,
                viewerHasSubmitted: false,
                calendar: calendar
            )
        )
    }

    func testPromptDeadlineIsExclusive() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let prompt = DailyPrompt(
            id: UUID(),
            circleID: UUID(),
            localDate: start,
            startsAt: start,
            endsAt: start.addingTimeInterval(600)
        )

        XCTAssertEqual(prompt.phase(at: start), .open)
        XCTAssertEqual(prompt.phase(at: start.addingTimeInterval(599.99)), .open)
        XCTAssertEqual(prompt.phase(at: start.addingTimeInterval(600)), .closed)
    }

    func testDuplicateSubmissionIsRejected() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let (user, _, prompt) = try await repository.bootstrap()

        _ = try await repository.submit(
            promptID: prompt.id,
            authorID: user.id,
            mode: .typed,
            body: "A test blessing",
            videoURL: nil,
            now: now
        )

        do {
            _ = try await repository.submit(
                promptID: prompt.id,
                authorID: user.id,
                mode: .typed,
                body: "Another",
                videoURL: nil,
                now: now
            )
            XCTFail("Expected duplicate submission to fail")
        } catch let error as BlessingError {
            XCTAssertEqual(error, .alreadySubmitted)
        }
    }
}

