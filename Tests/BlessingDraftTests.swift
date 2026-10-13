import XCTest
@testable import BlessingCircle

final class BlessingDraftTests: XCTestCase {
    func testDraftMediaSurvivesStoreRecreationAndFailedCheckpointIsAtomic() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DraftTest-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("audio.caf")
        try Data(repeating: 7, count: 1_000).write(to: source)
        let now = Date()
        let draft = BlessingDraft(authorID: UUID(), circleID: UUID(), promptID: UUID(), createdAt: now,
            expiresAt: now.addingTimeInterval(3600), updatedAt: now, mode: .voice, text: "Kept",
            audioSegments: [source], videoURL: source, photoURL: source, scriptureReference: nil, repeatSourceID: nil)
        let storeRoot = root.appendingPathComponent("Store")
        let store = BlessingDraftStore(root: storeRoot)
        let saved = try await store.save(draft, now: now)
        XCTAssertNotEqual(saved?.audioSegments.first, source)
        let recreated = BlessingDraftStore(root: storeRoot)
        let loaded = try await recreated.load(authorID: draft.authorID, now: now)
        XCTAssertEqual(loaded.first?.text, "Kept")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(loaded.first?.photoURL)), Data(repeating: 7, count: 1_000))
        let other = try await recreated.load(authorID: UUID(), now: now)
        XCTAssertTrue(other.isEmpty)
        var broken = draft
        broken.text = "Should not replace a good checkpoint"
        broken.audioSegments = [root.appendingPathComponent("missing.caf")]
        do { _ = try await recreated.save(broken, now: now); XCTFail("Missing media must reject checkpoint") } catch {}
        let intact = try await recreated.load(authorID: draft.authorID, now: now)
        XCTAssertEqual(intact.first?.text, "Kept")
        try await recreated.markSent(authorID: draft.authorID, circleID: draft.circleID, promptID: draft.promptID)
        let delayedCheckpoint = try await recreated.save(draft, now: now)
        XCTAssertNil(delayedCheckpoint)
        await recreated.beginEditing(authorID: draft.authorID, circleID: draft.circleID, promptID: draft.promptID)
        _ = try await recreated.save(draft, now: now)
        let expired = try await recreated.load(authorID: draft.authorID, now: draft.expiresAt)
        XCTAssertTrue(expired.isEmpty)
        XCTAssertTrue(HelpTopic.sharing.steps.map(\.body).joined().contains("draft never extends the entry deadline"))
    }

    func testResumeRejectsClosedWindowWrongAccountAndNextDayDespiteOldEntry() async throws {
        let now = Date()
        let repo = LocalBlessingRepository(now: now)
        let data = try await repo.bootstrap()
        var circle = try XCTUnwrap(data.circle)
        circle.allowsLateBlessings = false
        let prompt = try XCTUnwrap(data.prompt)
        let user = data.currentUser
        let draft = BlessingDraft(authorID: user.id, circleID: circle.id, promptID: prompt.id,
            createdAt: prompt.startsAt, expiresAt: BlessingDraftPolicy.expiry(createdAt: prompt.startsAt,
                timeZoneIdentifier: circle.timeZoneIdentifier), updatedAt: now, mode: .typed,
            text: "Draft", audioSegments: [], videoURL: nil, photoURL: nil, scriptureReference: nil, repeatSourceID: nil)
        XCTAssertTrue(BlessingDraftPolicy.canResume(draft, authorID: user.id, prompt: prompt, circle: circle, now: prompt.startsAt))
        XCTAssertFalse(BlessingDraftPolicy.canResume(draft, authorID: user.id, prompt: prompt, circle: circle, now: prompt.endsAt))
        XCTAssertFalse(BlessingDraftPolicy.canResume(draft, authorID: UUID(), prompt: prompt, circle: circle, now: now))
        circle.allowsLateBlessings = true
        XCTAssertTrue(BlessingDraftPolicy.canResume(draft, authorID: user.id, prompt: prompt, circle: circle, now: prompt.endsAt))
        XCTAssertFalse(BlessingDraftPolicy.canResume(draft, authorID: user.id, prompt: prompt, circle: circle, now: draft.expiresAt))
        _ = try await repo.updateCircleSettings(circleID: circle.id, ownerID: circle.ownerID, name: circle.name,
            timeZoneIdentifier: circle.timeZoneIdentifier, randomWindowStartMinutes: circle.randomWindowStartMinutes,
            randomWindowEndMinutes: circle.randomWindowEndMinutes, responseWindowMinutes: circle.responseWindowMinutes,
            allowsLateBlessings: false, repeatWindowMinutes: circle.repeatWindowMinutes, endOfDayMinutes: circle.endOfDayMinutes)
        try await repo.beginBlessingEntry(promptID: prompt.id, memberID: user.id, now: prompt.startsAt)
        do { try await repo.beginBlessingEntry(promptID: prompt.id, memberID: user.id, now: prompt.endsAt); XCTFail("Old grant cannot reopen a closed no-late entry") } catch {}
    }
}
