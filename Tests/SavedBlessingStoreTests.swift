import XCTest
@testable import BlessingCircle

final class SavedBlessingStoreTests: XCTestCase {
    func testRetentionBoundaryAndTwoDayWarning() {
        let sent = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(MediaRetentionPolicy.warning(for: sent, at: sent.addingTimeInterval(12 * 86_400 - 1)))
        XCTAssertEqual(MediaRetentionPolicy.warning(for: sent, at: sent.addingTimeInterval(12 * 86_400)), "Media expires in 2 days")
        XCTAssertEqual(MediaRetentionPolicy.warning(for: sent, at: sent.addingTimeInterval(14 * 86_400 - 1)), "Media expires in 1h")
        XCTAssertFalse(MediaRetentionPolicy.isExpired(submittedAt: sent, at: sent.addingTimeInterval(14 * 86_400 - 1)))
        XCTAssertTrue(MediaRetentionPolicy.isExpired(submittedAt: sent, at: sent.addingTimeInterval(14 * 86_400)))
        XCTAssertNil(MediaRetentionPolicy.warning(for: sent, at: sent.addingTimeInterval(14 * 86_400)))
    }

    func testArchiveReloadKeepsTextReferencePhotoAndResponseAudioAfterExpiry() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID()
        let blessing = fixture()
        let response = responseFixture(blessing: blessing)
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        let saved = try await store.save(blessing: blessing, responses: [response], userID: user)
        XCTAssertTrue(saved.blessing.audioURL?.isFileURL == true)
        XCTAssertTrue(saved.blessing.photoURL?.isFileURL == true)
        XCTAssertTrue(saved.responses[0].audioURL?.isFileURL == true)
        let reloaded = try await SavedBlessingStore(root: root).load(userID: user)
        let copy = try XCTUnwrap(reloaded[blessing.id])
        XCTAssertEqual(copy.blessing.body, blessing.body)
        XCTAssertEqual(copy.blessing.scriptureReference, blessing.scriptureReference)
        XCTAssertEqual(copy.responses[0].body, response.body)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copy.blessing.audioURL)), Data("fixture media".utf8))
        XCTAssertTrue(copy.expiredMedia(at: blessing.submittedAt.addingTimeInterval(MediaRetentionPolicy.lifetime)))
        XCTAssertFalse(copy.expiredMedia(at: blessing.submittedAt.addingTimeInterval(MediaRetentionPolicy.lifetime - 1)))
        let manifest = root.appendingPathComponent(user.uuidString).appendingPathComponent(blessing.id.uuidString)
            .appendingPathComponent("blessing.json")
        XCTAssertFalse(String(decoding: try Data(contentsOf: manifest), as: UTF8.self).contains(root.path))
    }

    func testArchiveIsIsolatedPerAccountAndUnsaveOnlyRemovesSelectedCopy() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        let firstUser = UUID(), secondUser = UUID()
        let blessing = fixture()
        _ = try await store.save(blessing: blessing, responses: [], userID: firstUser)
        let hidden = try await store.load(userID: secondUser)
        XCTAssertTrue(hidden.isEmpty)
        _ = try await store.save(blessing: blessing, responses: [], userID: secondUser)
        try await store.unsave(blessingID: blessing.id, userID: firstUser)
        let first = try await store.load(userID: firstUser)
        let second = try await store.load(userID: secondUser)
        XCTAssertTrue(first.isEmpty)
        XCTAssertNotNil(second[blessing.id])
    }

    func testPartialDownloadFailureDoesNotPublishArchive() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID()
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier(failingFile: "photo.jpg"))
        do {
            _ = try await store.save(blessing: fixture(), responses: [], userID: user)
            XCTFail("A partial archive must not succeed")
        } catch { XCTAssertTrue(error is BlessingMediaSaveError) }
        let saved = try await store.load(userID: user)
        XCTAssertTrue(saved.isEmpty)
        let children = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(user.uuidString), includingPropertiesForKeys: nil
        )
        XCTAssertTrue(children.isEmpty)
    }

    func testVideoArchiveSurvivesReload() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID()
        let blessing = fixture(mode: .video)
        _ = try await SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
            .save(blessing: blessing, responses: [], userID: user)
        let records = try await SavedBlessingStore(root: root).load(userID: user)
        XCTAssertTrue(records[blessing.id]?.blessing.videoURL?.isFileURL == true)
        XCTAssertNil(records[blessing.id]?.blessing.photoURL)
    }

    func testResponseExpiryUsesResponseTimestampNotBlessingDate() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sent = Date(timeIntervalSince1970: 1_000)
        let blessing = fixture(mode: .typed, sent: sent)
            .replacingMedia(audio: nil, video: nil, photo: nil)
        let response = responseFixture(blessing: blessing, sent: sent.addingTimeInterval(86_400))
        let record = try await SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
            .save(blessing: blessing, responses: [response], userID: UUID())
        XCTAssertFalse(record.expiredMedia(at: sent.addingTimeInterval(14 * 86_400)))
        XCTAssertTrue(record.expiredMedia(at: sent.addingTimeInterval(15 * 86_400)))
    }

    @MainActor
    func testSavedMediaResolvesForCurrentAccountWithoutUnlockingPeerPosts() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        let model = AppModel(repository: LocalBlessingRepository(), savedBlessingStore: store)
        await model.bootstrap()
        XCTAssertTrue(model.currentPromptBlessings().isEmpty)
        let fabricated = fixture()
        let fabricatedSaved = await model.saveBlessing(fabricated)
        XCTAssertFalse(fabricatedSaved)
        let old = try XCTUnwrap(model.lanes.flatMap(\.events).compactMap { event -> Blessing? in
            if case let .blessing(blessing) = event.status { return blessing }
            return nil
        }.first)
        let saved = await model.saveBlessing(old)
        XCTAssertTrue(saved)
        XCTAssertNotNil(model.savedBlessings[old.id])
        XCTAssertTrue(model.currentPromptBlessings().isEmpty, "Saving history must not unlock current peer content")
        await model.unsaveBlessing(old)
        XCTAssertNil(model.savedBlessings[old.id])
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archive-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func fixture(mode: CaptureMode = .voice, sent: Date = .now) -> Blessing {
        Blessing(
            id: UUID(), circleID: UUID(), promptID: UUID(), authorID: UUID(), captureMode: mode,
            body: "A blessing worth keeping", audioURL: mode == .voice ? URL(string: "https://example.com/audio.m4a") : nil,
            videoURL: mode == .video ? URL(string: "https://example.com/video.mp4") : nil, submittedAt: sent,
            isLate: false, scriptureReference: .init(bookSlug: "john", bookName: "John", chapter: 3, verseStart: 16, verseEnd: 16),
            photoURL: mode == .video ? nil : URL(string: "https://example.com/photo.jpg")
        )
    }

    private func responseFixture(blessing: Blessing, sent: Date? = nil) -> BlessingResponse {
        BlessingResponse(id: UUID(), blessingID: blessing.id, circleID: blessing.circleID,
            authorID: UUID(), mode: .voice, body: "Amen", audioURL: URL(string: "https://example.com/response.m4a"),
            submittedAt: sent ?? blessing.submittedAt)
    }
}

private struct FixtureArchiveCopier: SavedBlessingMediaCopying {
    var failingFile: String? = nil

    func copy(from source: URL, to destination: URL) async throws {
        if source.lastPathComponent == failingFile { throw BlessingMediaSaveError.unavailable }
        try Data("fixture media".utf8).write(to: destination)
    }
}
