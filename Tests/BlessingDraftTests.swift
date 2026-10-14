import XCTest
@testable import BlessingCircle

final class BlessingDraftTests: XCTestCase {
    func testSharingGuideUsesTheSameShareButtonForDraftRecovery() {
        let guide = HelpTopic.sharing.steps.map(\.body).joined()
        XCTAssertTrue(guide.contains("Share a blessing changes to Continue"))
        XCTAssertTrue(guide.contains("end-of-day share button does the same for its own draft"))
        XCTAssertTrue(guide.contains("there is no separate draft button"))
        XCTAssertTrue(guide.contains("draft never extends the entry deadline"))
    }

    @MainActor
    func testShareActionRestoresOnlyMatchingDailyOrEveningDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShareDraftTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3_600)
        let repo = LocalBlessingRepository(now: now, endOfDayStartsAt: now.addingTimeInterval(-30))
        let data = try await repo.bootstrap()
        let circle = try XCTUnwrap(data.circle)
        let daily = try XCTUnwrap(data.prompt)
        let evening = try XCTUnwrap(data.endOfDayPrompt)
        let store = BlessingDraftStore(root: root.appendingPathComponent("Drafts"))
        let dailyDraft = makeDraft(user: data.currentUser, circle: circle, prompt: daily, now: now, text: "Daily changes")
        let eveningDraft = makeDraft(user: data.currentUser, circle: circle, prompt: evening, now: now, text: "Evening changes")
        _ = try await store.save(dailyDraft, now: now)
        _ = try await store.save(eveningDraft, now: now)
        let model = AppModel(repository: repo, savedBlessingStore: SavedBlessingStore(root: root.appendingPathComponent("Saved")), draftStore: store)
        model.currentUser = data.currentUser
        model.circle = circle
        model.prompt = daily
        model.endOfDayPrompt = evening
        await model.reloadDrafts(now: now)
        XCTAssertEqual(model.resumableDraft(for: daily, at: now)?.text, "Daily changes")
        XCTAssertEqual(model.resumableDraft(for: evening, at: now)?.text, "Evening changes")
        let openedDaily = await model.openCapture(now: now)
        XCTAssertTrue(openedDaily)
        XCTAssertEqual(model.captureDraftToRestore?.text, "Daily changes")
        model.isCapturePresented = false
        let openedEvening = await model.openCapture(for: evening, now: now)
        XCTAssertTrue(openedEvening)
        XCTAssertEqual(model.captureDraftToRestore?.text, "Evening changes")
        model.isCapturePresented = false
        let otherAccount = Member(id: UUID(), displayName: "Another account", initials: "AA", tintSeed: 2)
        model.currentUser = otherAccount
        XCTAssertNil(model.resumableDraft(for: daily, at: now))
        XCTAssertNil(model.resumableDraft(for: evening, at: now))
        model.currentUser = data.currentUser
        let otherCircle = try XCTUnwrap(data.circles.first { $0.id != circle.id })
        model.circle = otherCircle
        XCTAssertNil(model.resumableDraft(for: daily, at: now))
        let wrongCircleOpened = await model.openCapture(for: daily, now: now)
        XCTAssertFalse(wrongCircleOpened)
        XCTAssertNil(model.captureDraftToRestore)
    }

    @MainActor
    func testShareActionRechecksClosedWindowEvenWithOldGrantAndSavedDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClosedDraftTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3_600)
        let repo = LocalBlessingRepository(now: now)
        let data = try await repo.bootstrap()
        var circle = try XCTUnwrap(data.circle)
        let daily = try XCTUnwrap(data.prompt)
        circle = try await repo.updateCircleSettings(circleID: circle.id, ownerID: circle.ownerID, name: circle.name,
            timeZoneIdentifier: circle.timeZoneIdentifier, randomWindowStartMinutes: circle.randomWindowStartMinutes,
            randomWindowEndMinutes: circle.randomWindowEndMinutes, responseWindowMinutes: circle.responseWindowMinutes,
            allowsLateBlessings: false, repeatWindowMinutes: circle.repeatWindowMinutes, endOfDayMinutes: circle.endOfDayMinutes)
        let store = BlessingDraftStore(root: root.appendingPathComponent("Drafts"))
        _ = try await store.save(makeDraft(user: data.currentUser, circle: circle, prompt: daily, now: now, text: "Kept draft"), now: now)
        let model = AppModel(repository: repo, savedBlessingStore: SavedBlessingStore(root: root.appendingPathComponent("Saved")), draftStore: store)
        model.currentUser = data.currentUser
        model.circle = circle
        model.prompt = daily
        await model.reloadDrafts(now: now)
        let opened = await model.openCapture(now: now)
        XCTAssertTrue(opened)
        model.isCapturePresented = false
        XCTAssertNil(model.resumableDraft(for: daily, at: daily.endsAt))
        let reopened = await model.openCapture(now: daily.endsAt)
        XCTAssertFalse(reopened)
        XCTAssertFalse(model.isCapturePresented)
        XCTAssertNil(model.captureDraftToRestore)
        XCTAssertEqual(model.savedDrafts.first?.text, "Kept draft")
    }

    private func makeDraft(user: Member, circle: CircleGroup, prompt: DailyPrompt, now: Date, text: String) -> BlessingDraft {
        BlessingDraft(authorID: user.id, circleID: circle.id, promptID: prompt.id, createdAt: now,
            expiresAt: BlessingDraftPolicy.expiry(createdAt: now, timeZoneIdentifier: circle.timeZoneIdentifier),
            updatedAt: now, mode: .typed, text: text, audioSegments: [], videoURL: nil, photoURL: nil,
            scriptureReference: nil, repeatSourceID: nil)
    }

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
        let editingCopy = try await recreated.copyForEditing(XCTUnwrap(intact.first))
        let editingURLs = editingCopy.audioSegments + [editingCopy.photoURL, editingCopy.videoURL].compactMap { $0 }
        defer { for url in editingURLs { try? FileManager.default.removeItem(at: url) } }
        try await recreated.markSent(authorID: draft.authorID, circleID: draft.circleID, promptID: draft.promptID)
        let delayedCheckpoint = try await recreated.save(draft, now: now)
        XCTAssertNil(delayedCheckpoint)
        await recreated.beginEditing(authorID: draft.authorID, circleID: draft.circleID, promptID: draft.promptID)
        _ = try await recreated.save(draft, now: now)
        let expired = try await recreated.load(authorID: draft.authorID, now: draft.expiresAt)
        XCTAssertTrue(expired.isEmpty)
        // Midnight removes recovery copies, never the media in an already-open, valid composer.
        for url in editingURLs {
            XCTAssertEqual(try Data(contentsOf: url), Data(repeating: 7, count: 1_000))
        }
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
