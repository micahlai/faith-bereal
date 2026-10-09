import XCTest
@testable import BlessingCircle

final class NudgeTests: XCTestCase {
    func testNudgesRequireSamePromptSubmissionAndOnlyOnePerRecipient() async throws {
        let now = Date()
        let repo = LocalBlessingRepository(now: now, endOfDayStartsAt: now.addingTimeInterval(-30))
        let bootstrap = try await repo.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let daily = try XCTUnwrap(bootstrap.prompt)
        let evening = try XCTUnwrap(bootstrap.endOfDayPrompt)
        let user = bootstrap.currentUser
        let recipient = try XCTUnwrap(circle.members.first { $0.displayName == "Ben" })
        do {
            _ = try await repo.nudgeMember(promptID: daily.id, recipientID: recipient.id, senderID: user.id, now: now)
            XCTFail("Must share first")
        } catch { XCTAssertEqual(error as? BlessingError, .nudgeUnavailable) }
        _ = try await repo.submit(promptID: daily.id, authorID: user.id, mode: .typed,
            body: "Grateful", audioURL: nil, videoURL: nil, scriptureReference: nil, now: now)
        let first = try await repo.nudgeMember(promptID: daily.id, recipientID: recipient.id, senderID: user.id, now: now)
        XCTAssertTrue(first)
        let duplicate = try await repo.nudgeMember(promptID: daily.id, recipientID: recipient.id, senderID: user.id, now: now)
        XCTAssertFalse(duplicate)
        do {
            _ = try await repo.nudgeMember(promptID: evening.id, recipientID: recipient.id, senderID: user.id, now: now)
            XCTFail("Daily sharing must not enable evening nudges")
        } catch { XCTAssertEqual(error as? BlessingError, .nudgeUnavailable) }
        _ = try await repo.submit(promptID: evening.id, authorID: user.id, mode: .typed,
            body: "Evening grateful", audioURL: nil, videoURL: nil, scriptureReference: nil, now: now)
        let eveningNudge = try await repo.nudgeMember(promptID: evening.id, recipientID: recipient.id, senderID: user.id, now: now)
        XCTAssertTrue(eveningNudge)
        _ = try await repo.submit(promptID: daily.id, authorID: recipient.id, mode: .typed,
            body: "I shared", audioURL: nil, videoURL: nil, scriptureReference: nil, now: now)
        do {
            _ = try await repo.nudgeMember(promptID: daily.id, recipientID: recipient.id, senderID: user.id, now: now)
            XCTFail("Completed recipients cannot be nudged")
        } catch { XCTAssertEqual(error as? BlessingError, .nudgeUnavailable) }
    }

    func testNudgeWindowBoundariesAndNoFirstDayOrGrantException() async throws {
        let now = Date()
        let bootstrap = try await LocalBlessingRepository(now: now).bootstrap()
        var circle = try XCTUnwrap(bootstrap.circle)
        let daily = try XCTUnwrap(bootstrap.prompt)
        let sender = bootstrap.currentUser.id
        let recipient = try XCTUnwrap(circle.members.last).id
        func canNudge(_ prompt: DailyPrompt, at time: Date, shared: Bool = true,
                      recipientShared: Bool = false, target: UUID? = nil, next: Date? = nil) -> Bool {
            NudgePolicy.isEligible(prompt: prompt, circle: circle, senderID: sender, recipientID: target ?? recipient,
                senderHasShared: shared, recipientHasShared: recipientShared, now: time, nextDailyStart: next)
        }
        XCTAssertFalse(canNudge(daily, at: daily.startsAt.addingTimeInterval(-1)))
        XCTAssertTrue(canNudge(daily, at: daily.startsAt))
        XCTAssertFalse(canNudge(daily, at: now, shared: false))
        XCTAssertFalse(canNudge(daily, at: now, recipientShared: true))
        XCTAssertFalse(canNudge(daily, at: now, target: sender))
        XCTAssertFalse(canNudge(daily, at: now, target: UUID()))
        circle.allowsLateBlessings = false
        XCTAssertFalse(canNudge(daily, at: daily.endsAt))
        circle.allowsLateBlessings = true
        XCTAssertTrue(canNudge(daily, at: daily.endsAt))
        XCTAssertFalse(canNudge(daily, at: daily.endsAt, next: daily.endsAt))
        let evening = DailyPrompt(id: UUID(), circleID: circle.id, localDate: daily.localDate,
            startsAt: now, endsAt: now.addingTimeInterval(5*3600), kind: .endOfDay)
        XCTAssertTrue(canNudge(evening, at: now))
        XCTAssertFalse(canNudge(evening, at: evening.endsAt))
        XCTAssertFalse(canNudge(evening, at: now.addingTimeInterval(60), next: now.addingTimeInterval(60)))
    }

    @MainActor
    func testTodayNudgeChoicesOnlyAppearAfterSharingAndDisappearWhenCompleted() async throws {
        let model = AppModel(repository: LocalBlessingRepository())
        await model.bootstrap()
        XCTAssertTrue(model.nudgeCandidates().isEmpty)
        let shared = await model.submit(mode: .typed, body: "Grateful", audioURL: nil, videoURL: nil,
            scriptureReference: nil)
        XCTAssertTrue(shared)
        let candidate = try XCTUnwrap(model.nudgeCandidates().first)
        XCTAssertEqual(candidate.member.displayName, "Ben")
        XCTAssertEqual(candidate.prompt.kind, .daily)
        await model.nudge(candidate)
        XCTAssertTrue(model.nudgedMembers.contains(candidate.id))
        XCTAssertTrue(model.message?.contains("Nudge queued") == true)
    }
}
