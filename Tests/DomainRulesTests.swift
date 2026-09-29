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
            audioURL: nil,
            videoURL: nil,
            scriptureReference: nil,
            now: now
        )

        do {
            _ = try await repository.submit(
                promptID: prompt.id,
                authorID: user.id,
                mode: .typed,
                body: "Another",
                audioURL: nil,
                videoURL: nil,
                scriptureReference: nil,
                now: now
            )
            XCTFail("Expected duplicate submission to fail")
        } catch let error as BlessingError {
            XCTAssertEqual(error, .alreadySubmitted)
        }
    }

    func testOwnerCanChangeFutureResponseWindowAndAllowLateBlessings() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let (user, circle, _) = try await repository.bootstrap()

        let updated = try await repository.updateCircleSettings(
            circleID: circle.id,
            ownerID: user.id,
            name: "Morning Light",
            timeZoneIdentifier: "America/New_York",
            randomWindowStartMinutes: 7 * 60,
            randomWindowEndMinutes: 18 * 60,
            responseWindowMinutes: 40,
            allowsLateBlessings: true
        )

        XCTAssertEqual(updated.responseWindowMinutes, 40)
        XCTAssertTrue(updated.allowsLateBlessings)
        XCTAssertEqual(updated.name, "Morning Light")
        XCTAssertEqual(updated.timeZoneIdentifier, "America/New_York")
    }

    func testLateSubmissionIsMarkedLateWhenCircleAllowsIt() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let (user, _, prompt) = try await repository.bootstrap()
        let lateTime = prompt.endsAt.addingTimeInterval(30)

        let blessing = try await repository.submit(
            promptID: prompt.id,
            authorID: user.id,
            mode: .typed,
            body: "Still grateful",
            audioURL: nil,
            videoURL: nil,
            scriptureReference: nil,
            now: lateTime
        )

        XCTAssertTrue(blessing.isLate)
    }

    func testSubmissionStoresReferenceWithoutVerseText() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let (user, _, prompt) = try await repository.bootstrap()
        let reference = ScriptureReference(
            bookSlug: "john",
            bookName: "John",
            chapter: 3,
            verseStart: 16,
            verseEnd: 18
        )

        let blessing = try await repository.submit(
            promptID: prompt.id,
            authorID: user.id,
            mode: .typed,
            body: "Grace today",
            audioURL: nil,
            videoURL: nil,
            scriptureReference: reference,
            now: now
        )

        XCTAssertEqual(blessing.scriptureReference, reference)
        XCTAssertEqual(blessing.body, "Grace today")
    }

    func testBibleVersionPreferenceIsUserSpecific() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let (user, circle, _) = try await repository.bootstrap()

        let updated = try await repository.updateBibleVersion(memberID: user.id, versionID: "kjv")

        XCTAssertEqual(updated.bibleVersionID, "kjv")
        XCTAssertNotEqual(circle.members[1].bibleVersionID, "kjv")
    }
}
