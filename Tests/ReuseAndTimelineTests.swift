import XCTest
@testable import BlessingCircle

final class ReuseAndTimelineTests: XCTestCase {
    func testReusePreservesEveryCaptureFormatAndMediaWithoutResponses() async throws {
        for mode in CaptureMode.allCases {
            let now = Date()
            let repo = LocalBlessingRepository(now: now)
            let bootstrap = try await repo.bootstrap()
            let user = bootstrap.currentUser
            let originalPrompt = try XCTUnwrap(bootstrap.prompt)
            let targetCircle = try XCTUnwrap(bootstrap.circles.last)
            let context = try await repo.circleContext(circleID: targetCircle.id)
            let target = try XCTUnwrap(context.prompt)
            let source = try await repo.submit(
                promptID: originalPrompt.id, authorID: user.id, mode: mode, body: "Thankful today",
                audioURL: mode == .voice ? URL(fileURLWithPath: "/tmp/voice.caf") : nil,
                videoURL: mode == .video ? URL(fileURLWithPath: "/tmp/video.mov") : nil,
                photoURL: mode != .video ? URL(fileURLWithPath: "/tmp/photo.jpg") : nil,
                scriptureReference: nil, now: now)
            _ = try await repo.submitResponse(blessingID: source.id, circleID: source.circleID,
                authorID: user.id, mode: .typed, body: "Response stays here", audioURL: nil, now: now)
            let copy = try await repo.repeatBlessing(sourceBlessingID: source.id,
                targetPromptID: target.id, authorID: user.id, now: now.addingTimeInterval(60))
            XCTAssertNotEqual(copy.id, source.id)
            XCTAssertEqual(copy.captureMode, source.captureMode)
            XCTAssertEqual(copy.audioURL, source.audioURL)
            XCTAssertEqual(copy.videoURL, source.videoURL)
            XCTAssertEqual(copy.photoURL, source.photoURL)
            XCTAssertEqual(copy.body, source.body)
            XCTAssertEqual(copy.submittedAt, now.addingTimeInterval(60))
            XCTAssertEqual(copy.promptID, target.id)
            let responses = try await repo.responses(blessingID: copy.id, viewerID: user.id)
            XCTAssertTrue(responses.isEmpty)
            do {
                _ = try await repo.repeatBlessing(sourceBlessingID: source.id,
                    targetPromptID: target.id, authorID: user.id, now: now.addingTimeInterval(61))
                XCTFail("A repeat must not bypass one blessing per prompt")
            } catch { XCTAssertEqual(error as? BlessingError, .alreadySubmitted) }
        }
    }

    func testScheduledTimelineIsNotShareableEvenWithLateSharingEnabled() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = LocalBlessingRepository(now: start)
        let bootstrap = try await repo.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let prompt = try XCTUnwrap(bootstrap.prompt)
        let lanes = try await repo.timeline(circleID: circle.id, viewerID: bootstrap.currentUser.id,
            now: prompt.startsAt.addingTimeInterval(-1))
        for lane in lanes {
            let event = try XCTUnwrap(lane.events.first { $0.promptKind == .daily && $0.date == prompt.localDate })
            // Seeded early peer content stays locked; empty lanes wait for notification.
            XCTAssertTrue(event.status == .scheduled || event.status == .locked)
            XCTAssertNotEqual(event.status, .waiting)
            XCTAssertNotEqual(event.status, .missed)
        }
    }

    func testTimelinePolicyPreservesFirstDayAndStartDeadlineTransitions() async throws {
        let now = Date()
        let repo = LocalBlessingRepository(now: now)
        let bootstrap = try await repo.bootstrap()
        var circle = try XCTUnwrap(bootstrap.circle)
        let prompt = try XCTUnwrap(bootstrap.prompt)
        var member = bootstrap.currentUser
        func status(at date: Date, canEnter: Bool) -> TimelineStatus {
            TimelineStatusPolicy.status(prompt: prompt, circle: circle, member: member,
                viewerID: member.id, viewerHasSubmitted: false, blessing: nil,
                now: date, entryIsOpen: canEnter, requiresSubmissionGate: true)
        }
        XCTAssertEqual(status(at: prompt.startsAt.addingTimeInterval(-1), canEnter: true), .scheduled)
        XCTAssertEqual(status(at: prompt.startsAt, canEnter: true), .waiting)
        circle.allowsLateBlessings = false
        XCTAssertEqual(status(at: prompt.endsAt, canEnter: false), .missed)
        circle.allowsLateBlessings = true
        XCTAssertEqual(status(at: prompt.endsAt, canEnter: true), .waiting)
        member.joinedAt = prompt.startsAt.addingTimeInterval(-30)
        XCTAssertEqual(status(at: prompt.startsAt.addingTimeInterval(-1), canEnter: true), .waiting)
    }
}
