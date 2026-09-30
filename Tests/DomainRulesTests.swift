import XCTest
@testable import BlessingCircle

final class DomainRulesTests: XCTestCase {
    func testCapturedVideoIsCopiedToStableAppStorage() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        let data = Data("video-fixture".utf8)
        try data.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let persistedURL = try CaptureMediaStore.persistVideo(from: sourceURL)
        defer { try? FileManager.default.removeItem(at: persistedURL) }

        XCTAssertNotEqual(persistedURL, sourceURL)
        XCTAssertEqual(try Data(contentsOf: persistedURL), data)
        XCTAssertTrue(persistedURL.path.contains("BlessingCaptures"))
    }

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

    func testPromptStopsBeingTodayAtMidnightInCircleTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 18))
        )
        let beforeMidnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 23, minute: 59))
        )
        let midnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 0))
        )
        let prompt = DailyPrompt(
            id: UUID(),
            circleID: UUID(),
            localDate: calendar.startOfDay(for: start),
            startsAt: start,
            endsAt: start.addingTimeInterval(600)
        )

        XCTAssertTrue(prompt.occursOnCircleDay(at: beforeMidnight, timeZoneIdentifier: "America/New_York"))
        XCTAssertFalse(prompt.occursOnCircleDay(at: midnight, timeZoneIdentifier: "America/New_York"))
    }

    func testDuplicateSubmissionIsRejected() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        let user = bootstrap.currentUser
        let prompt = try XCTUnwrap(bootstrap.prompt)

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
        let bootstrap = try await repository.bootstrap()
        let user = bootstrap.currentUser
        let circle = try XCTUnwrap(bootstrap.circle)

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

    func testOwnerCanTransferCircleOwnershipToCurrentMember() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let bootstrap = try await repository.bootstrap()
        let user = bootstrap.currentUser
        let circle = try XCTUnwrap(bootstrap.circle)
        let successor = try XCTUnwrap(circle.members.first(where: { $0.id != user.id }))

        let updated = try await repository.transferCircleOwnership(
            circleID: circle.id,
            ownerID: user.id,
            newOwnerID: successor.id
        )

        XCTAssertEqual(updated.ownerID, successor.id)
        XCTAssertTrue(updated.members.contains(where: { $0.id == user.id }))
    }

    func testNonOwnerCannotTransferCircleOwnership() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let bootstrap = try await repository.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let nonOwner = try XCTUnwrap(circle.members.first(where: { $0.id != circle.ownerID }))

        do {
            _ = try await repository.transferCircleOwnership(
                circleID: circle.id,
                ownerID: nonOwner.id,
                newOwnerID: circle.ownerID
            )
            XCTFail("Expected a non-owner transfer to fail")
        } catch let error as BlessingError {
            XCTAssertEqual(error, .notCircleOwner)
        }
    }

    func testLateSubmissionIsMarkedLateWhenCircleAllowsIt() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        let user = bootstrap.currentUser
        let prompt = try XCTUnwrap(bootstrap.prompt)
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
        let bootstrap = try await repository.bootstrap()
        let user = bootstrap.currentUser
        let prompt = try XCTUnwrap(bootstrap.prompt)
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
        let bootstrap = try await repository.bootstrap()
        let user = bootstrap.currentUser
        let circle = try XCTUnwrap(bootstrap.circle)

        let updated = try await repository.updateBibleVersion(memberID: user.id, versionID: "kjv")

        XCTAssertEqual(updated.bibleVersionID, "kjv")
        XCTAssertNotEqual(circle.members[1].bibleVersionID, "kjv")
    }

    func testTimelineEndsAtMembershipStartAndExcludesEarlierPrompts() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        let user = bootstrap.currentUser
        let circle = try XCTUnwrap(bootstrap.circle)
        let lanes = try await repository.timeline(circleID: circle.id, viewerID: user.id, now: now)
        let newestMemberLane = try XCTUnwrap(lanes.first(where: { $0.member.displayName == "Ben" }))

        guard case .joinedCircle = newestMemberLane.events.last?.status else {
            return XCTFail("Expected the lane to end with the membership marker")
        }
        XCTAssertEqual(newestMemberLane.events.count, 3)
    }

    func testResponseStaysAttachedToBlessingCircle() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        let user = bootstrap.currentUser
        let circle = try XCTUnwrap(bootstrap.circle)
        let prompt = try XCTUnwrap(bootstrap.prompt)
        let blessing = try await repository.submit(
            promptID: prompt.id,
            authorID: user.id,
            mode: .typed,
            body: "A specific blessing",
            audioURL: nil,
            videoURL: nil,
            scriptureReference: nil,
            now: now
        )

        let response = try await repository.submitResponse(
            blessingID: blessing.id,
            circleID: circle.id,
            authorID: circle.members[1].id,
            mode: .typed,
            body: "Amen",
            audioURL: nil,
            now: now.addingTimeInterval(1)
        )
        let loaded = try await repository.responses(blessingID: blessing.id, viewerID: user.id)

        XCTAssertEqual(response.circleID, circle.id)
        XCTAssertEqual(loaded, [response])
    }

    func testBootstrapLoadsMultipleCircleContexts() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let bootstrap = try await repository.bootstrap()

        XCTAssertEqual(bootstrap.circles.count, 2)
        XCTAssertEqual(bootstrap.circle?.name, "Sunday Table")

        let secondCircle = try XCTUnwrap(bootstrap.circles.last)
        let context = try await repository.circleContext(circleID: secondCircle.id)

        XCTAssertEqual(context.circle.name, "Morning Prayer")
        XCTAssertEqual(context.prompt?.circleID, secondCircle.id)
    }

    func testLeavingOneCirclePreservesOtherMembership() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let before = try await repository.bootstrap()
        let user = before.currentUser
        let circleToLeave = try XCTUnwrap(before.circle)

        try await repository.leaveCircle(circleID: circleToLeave.id, memberID: user.id)
        let after = try await repository.bootstrap()

        XCTAssertEqual(after.circles.map(\.name), ["Morning Prayer"])
        XCTAssertEqual(after.circle?.name, "Morning Prayer")

        do {
            _ = try await repository.circleContext(circleID: circleToLeave.id)
            XCTFail("Expected the departed circle to be inaccessible")
        } catch let error as BlessingError {
            XCTAssertEqual(error, .circleNotFound)
        }
    }
}
