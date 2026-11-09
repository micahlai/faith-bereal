import XCTest
@testable import BlessingCircle

final class SavedBlessingStoreTests: XCTestCase {
    func testIndexedPageKeepsLargeArchiveBodiesOffTheInitialLoad() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), circle = UUID(), author = UUID()
        let account = root.appendingPathComponent(user.uuidString)
        let now = Date(), count = 300
        var ids: [UUID] = []
        for offset in 0..<count {
            let blessing = fixture(mode: .typed, sent: now.addingTimeInterval(Double(-offset) * 86400),
                circleID: circle, authorID: author).replacingMedia(audio: nil, video: nil, photo: nil)
            let responses = (0..<30).map { _ in BlessingResponse(id: UUID(), blessingID: blessing.id,
                circleID: circle, authorID: author, mode: .typed, body: String(repeating: "Saved response ", count: 20),
                audioURL: nil, submittedAt: blessing.submittedAt) }
            let record = SavedBlessingRecord(blessing: blessing, responses: responses, savedAt: now, files: [:])
            let directory = account.appendingPathComponent(blessing.id.uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("blessing.json"))
            ids.append(blessing.id)
        }
        let store = SavedBlessingStore(root: root)
        _ = try await store.index(userID: user) // One-time legacy migration, excluded from warm timing.
        let fullStart = Date()
        let full = try await store.load(userID: user)
        let fullMS = Date().timeIntervalSince(fullStart) * 1000
        let pageStart = Date()
        let index = try await store.index(userID: user)
        let page = await store.load(blessingIDs: Set(ids.prefix(1)), userID: user)
        let pageMS = Date().timeIntervalSince(pageStart) * 1000
        XCTAssertEqual(index.count, count)
        XCTAssertEqual(full.count, count)
        XCTAssertEqual(Set(page.keys), Set(ids.prefix(1)))
        XCTAssertEqual(page.values.flatMap(\.responses).count, 30)
        print("LOCAL_ARCHIVE_BENCHMARK full_records=\(full.count) full_ms=\(fullMS) page_records=\(page.count) page_ms=\(pageMS)")
    }

    func testCompactIndexSurvivesRelaunchWithoutReadingOldManifestsAndTracksMutations() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), blessing = fixture()
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        _ = try await store.save(blessing: blessing, responses: [], userID: user, automatically: true)
        let account = root.appendingPathComponent(user.uuidString)
        let indexJSON = String(decoding: try Data(contentsOf: account.appendingPathComponent("index.json")), as: UTF8.self)
        XCTAssertFalse(indexJSON.contains("body"))
        XCTAssertFalse(indexJSON.contains("responses"))
        XCTAssertFalse(indexJSON.contains(root.path))
        // A missing old manifest must not trigger a full-archive scan on relaunch.
        let manifest = account.appendingPathComponent(blessing.id.uuidString).appendingPathComponent("blessing.json")
        let original = try Data(contentsOf: manifest)
        try FileManager.default.removeItem(at: manifest)
        let reopened = SavedBlessingStore(root: root)
        let index = try await reopened.index(userID: user)
        XCTAssertEqual(index.map(\.id), [blessing.id])
        let otherAccount = try await reopened.index(userID: UUID())
        XCTAssertTrue(otherAccount.isEmpty)
        try original.write(to: manifest)
        _ = try await reopened.keepManually(blessingID: blessing.id, userID: user)
        let manual = try await reopened.index(userID: user)
        XCTAssertEqual(manual.first?.isAutomatic, false)
        try await reopened.unsave(blessingID: blessing.id, userID: user)
        let removed = try await reopened.index(userID: user)
        XCTAssertTrue(removed.isEmpty)
    }

    func testLegacyArchiveBuildsAndRepairsItsIndexWithoutChangingSavedCopies() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), blessing = fixture()
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        _ = try await store.save(blessing: blessing, responses: [], userID: user)
        let file = root.appendingPathComponent(user.uuidString).appendingPathComponent("index.json")
        for damagedIndex in [false, true] {
            if damagedIndex { try Data("interrupted index".utf8).write(to: file) }
            else { try FileManager.default.removeItem(at: file) }
            let reopened = SavedBlessingStore(root: root)
            let index = try await reopened.index(userID: user)
            XCTAssertEqual(index.map(\.id), [blessing.id])
            let records = await reopened.load(blessingIDs: [blessing.id], userID: user)
            XCTAssertEqual(records[blessing.id]?.blessing.body, blessing.body)
            XCTAssertTrue(records[blessing.id]?.hasAllSavedFiles == true)
        }
    }

    func testAccountRemovalFencesAnAlreadyDownloadingSave() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), blessing = fixture()
        let copier = PausedArchiveCopier()
        let store = SavedBlessingStore(root: root, copier: copier)
        let save = Task { try await store.save(blessing: blessing, responses: [], userID: user) }
        await copier.waitUntilPaused()
        try await store.removeAccount(userID: user)
        await copier.resume()
        do { _ = try await save.value; XCTFail("In-flight save republished deleted data") } catch { }
        let records = try await store.load(userID: user)
        XCTAssertTrue(records.isEmpty)
    }

    func testBlockingPurgesOnlyBlockedAuthorsAndTheirResponses() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), blockedPost = fixture(), keptPost = fixture()
        let blocked = blockedPost.authorID
        let reply = BlessingResponse(id: UUID(), blessingID: keptPost.id, circleID: keptPost.circleID,
            authorID: blocked, mode: .voice, body: "Blocked reply", audioURL: URL(string: "https://example.com/blocked.m4a"), submittedAt: .now)
        let keptReply = responseFixture(blessing: keptPost)
        let store = SavedBlessingStore(root: root, copier: CountingArchiveCopier())
        _ = try await store.save(blessing: blockedPost, responses: [], userID: user)
        let before = try await store.save(blessing: keptPost, responses: [reply, keptReply], userID: user)
        let blockedAudio = try XCTUnwrap(before.responses.first { $0.id == reply.id }?.audioURL)
        try await store.removeContent(authorID: blocked, userID: user)
        let records = try await store.load(userID: user)
        XCTAssertNil(records[blockedPost.id])
        XCTAssertEqual(records[keptPost.id]?.responses.map(\.id), [keptReply.id])
        XCTAssertTrue(records[keptPost.id]?.hasAllSavedFiles == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedAudio.path))
    }

    func testRefreshingRemoteURLsDownloadsEachSavedFileOnlyOnceAcrossRelaunch() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), blessing = fixture()
        let response = responseFixture(blessing: blessing)
        let copier = CountingArchiveCopier()
        let store = SavedBlessingStore(root: root, copier: copier)
        let first = try await store.save(blessing: blessing, responses: [response], userID: user, automatically: true)
        let initialCount = await copier.count
        XCTAssertEqual(initialCount, 3)
        let fresh = blessing.replacingMedia(audio: URL(string: "https://example.com/audio.m4a?fresh"),
            video: nil, photo: URL(string: "https://example.com/photo.jpg?fresh"))
        let freshResponse = response.replacingAudio(URL(string: "https://example.com/response.m4a?fresh"))
        let reopened = SavedBlessingStore(root: root, copier: copier)
        let refreshed = try await reopened.save(blessing: fresh, responses: [freshResponse], userID: user,
            automatically: true, refreshing: true)
        let afterRefresh = await copier.count
        XCTAssertEqual(afterRefresh, initialCount)
        XCTAssertEqual(refreshed.blessing.audioURL, first.blessing.audioURL)
        XCTAssertEqual(refreshed.blessing.photoURL, first.blessing.photoURL)
        XCTAssertEqual(refreshed.responses[0].audioURL, first.responses[0].audioURL)
        let newResponse = responseFixture(blessing: blessing)
        let added = try await reopened.save(blessing: fresh, responses: [freshResponse, newResponse], userID: user,
            automatically: true, refreshing: true)
        let afterNewResponse = await copier.count
        XCTAssertEqual(afterNewResponse, initialCount + 1)
        XCTAssertEqual(added.responses[0].audioURL, first.responses[0].audioURL)
        _ = try await reopened.save(blessing: fresh.replacingMedia(audio: nil, video: nil, photo: nil),
            responses: added.responses, userID: user, automatically: true, refreshing: true)
        let reloaded = try await reopened.load(userID: user)
        XCTAssertEqual(reloaded[blessing.id]?.blessing.audioURL, first.blessing.audioURL)
    }

    @MainActor
    func testSavedMediaWinsOverFreshRemoteLinksBeforeAndAfterExpiry() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedBlessingStore(root: root, copier: CountingArchiveCopier())
        let repository = LocalBlessingRepository()
        let firstModel = AppModel(repository: repository, savedBlessingStore: store)
        await firstModel.bootstrap()
        let user = try XCTUnwrap(firstModel.currentUser?.id)
        let circleID = try XCTUnwrap(firstModel.circle?.id)
        let voice = fixture(circleID: circleID, authorID: user)
        let video = fixture(mode: .video, circleID: circleID, authorID: user)
        let response = responseFixture(blessing: voice)
        let voiceCopy = try await store.save(blessing: voice, responses: [response], userID: user)
        let videoCopy = try await store.save(blessing: video, responses: [], userID: user)
        let reopened = AppModel(repository: repository, savedBlessingStore: store)
        await reopened.bootstrap()
        for now in [voice.submittedAt, voice.submittedAt.addingTimeInterval(MediaRetentionPolicy.lifetime + 1)] {
            let resolved = reopened.resolvedBlessing(voice, at: now)
            XCTAssertEqual(resolved.audioURL, voiceCopy.blessing.audioURL)
            XCTAssertEqual(resolved.photoURL, voiceCopy.blessing.photoURL)
            XCTAssertEqual(reopened.resolvedBlessing(video, at: now).videoURL, videoCopy.blessing.videoURL)
            XCTAssertEqual(reopened.resolvedResponse(response, at: now).audioURL, voiceCopy.responses[0].audioURL)
        }
    }

    func testCAFArchivePreservesPlayableExtensionForBlessingAndResponse() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID()
        let blessing = fixture().replacingMedia(audio: URL(string: "https://example.com/voice.caf"), video: nil, photo: nil)
        let response = responseFixture(blessing: blessing).replacingAudio(URL(string: "https://example.com/reply.caf"))
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        _ = try await store.save(blessing: blessing, responses: [response], userID: user)
        let records = try await store.load(userID: user)
        XCTAssertEqual(records[blessing.id]?.blessing.audioURL?.pathExtension, "caf")
        XCTAssertEqual(records[blessing.id]?.responses.first?.audioURL?.pathExtension, "caf")
    }

    func testRetentionBoundaryAndThreeDayWarning() {
        let sent = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(MediaRetentionPolicy.warning(for: sent, at: sent.addingTimeInterval(27 * 86_400 - 1)))
        XCTAssertEqual(MediaRetentionPolicy.warning(for: sent, at: sent.addingTimeInterval(27 * 86_400)), "Media expires in 3 days")
        XCTAssertEqual(MediaRetentionPolicy.warning(for: sent, at: sent.addingTimeInterval(28 * 86_400)), "Media expires in 2 days")
        XCTAssertEqual(MediaRetentionPolicy.warning(for: sent, at: sent.addingTimeInterval(30 * 86_400 - 1)), "Media expires in 1h")
        XCTAssertFalse(MediaRetentionPolicy.isExpired(submittedAt: sent, at: sent.addingTimeInterval(30 * 86_400 - 1)))
        XCTAssertTrue(MediaRetentionPolicy.isExpired(submittedAt: sent, at: sent.addingTimeInterval(30 * 86_400)))
        XCTAssertNil(MediaRetentionPolicy.warning(for: sent, at: sent.addingTimeInterval(30 * 86_400)))
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
        XCTAssertFalse(record.expiredMedia(at: sent.addingTimeInterval(30 * 86_400)))
        XCTAssertTrue(record.expiredMedia(at: sent.addingTimeInterval(31 * 86_400)))
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

    func testAutomaticPreferencePersistsOnlyForItsAccount() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), excluded = UUID()
        let preferences = LocalSavingPreferences(isEnabled: true, hasChosen: true, excludedBlessingIDs: [excluded])
        try await SavedBlessingStore(root: root).savePreferences(preferences, userID: user)
        let same = try await SavedBlessingStore(root: root).loadPreferences(userID: user)
        let other = try await SavedBlessingStore(root: root).loadPreferences(userID: UUID())
        XCTAssertTrue(same.isEnabled)
        XCTAssertTrue(same.hasChosen)
        XCTAssertEqual(same.excludedBlessingIDs, [excluded])
        XCTAssertTrue(other.isEnabled)
        XCTAssertFalse(other.hasChosen)
    }

    func testExistingManifestWithoutAutomaticFlagRemainsManual() throws {
        let record = SavedBlessingRecord(blessing: fixture(), responses: [], savedAt: .now, files: [:])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "automaticallySaved")
        let old = try JSONDecoder().decode(SavedBlessingRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(old.isAutomatic)
    }

    @MainActor
    func testDamagedSavingPreferenceCannotBlockStartupOrEraseCopies() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalBlessingRepository()
        let userID = try await repository.bootstrap().currentUser.id
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        try await store.savePreferences(LocalSavingPreferences(isEnabled: true, hasChosen: true), userID: userID)
        let blessing = fixture()
        _ = try await store.save(blessing: blessing, responses: [], userID: userID)
        try Data("damaged preference".utf8).write(to: root.appendingPathComponent(userID.uuidString).appendingPathComponent("preferences.json"))
        let model = AppModel(repository: repository, savedBlessingStore: store)
        await model.bootstrap()
        XCTAssertEqual(model.loadState, .ready)
        XCTAssertFalse(model.automaticallySavesLocally)
        XCTAssertNotNil(model.automaticSavingError)
        let preserved = await store.loadRecord(blessingID: blessing.id, userID: userID)
        XCTAssertNotNil(preserved, "An unrequested circle's copy stays on disk despite damaged preferences")
        XCTAssertNil(model.savedBlessings[blessing.id])
    }

    func testAllFourKeepChoicesFilterOnlyAutomaticCopies() async throws {
        let mine = fixture(), other = fixture()
        let records = [mine, other].map {
            SavedBlessingRecord(blessing: $0, responses: [], savedAt: .now, files: [:], automaticallySaved: true)
        }
        XCTAssertEqual(AutomaticSaveKeepChoice.all.keptIDs(records: records, userID: mine.authorID, selectedIDs: []), [mine.id, other.id])
        XCTAssertEqual(AutomaticSaveKeepChoice.mine.keptIDs(records: records, userID: mine.authorID, selectedIDs: []), [mine.id])
        XCTAssertTrue(AutomaticSaveKeepChoice.none.keptIDs(records: records, userID: mine.authorID, selectedIDs: []).isEmpty)
        XCTAssertEqual(AutomaticSaveKeepChoice.selected.keptIDs(records: records, userID: mine.authorID, selectedIDs: [other.id, UUID()]), [other.id])
    }

    func testKeepingAutomaticCopyConvertsToManualWithoutRemovingMedia() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), blessing = fixture()
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        let automatic = try await store.save(blessing: blessing, responses: [], userID: user, automatically: true)
        XCTAssertTrue(automatic.isAutomatic)
        let kept = try await store.keepManually(blessingID: blessing.id, userID: user)
        XCTAssertFalse(try XCTUnwrap(kept).isAutomatic)
        XCTAssertEqual(kept?.blessing.audioURL, automatic.blessing.audioURL)
        let reloaded = try await store.load(userID: user)
        XCTAssertFalse(try XCTUnwrap(reloaded[blessing.id]).isAutomatic)
    }

    func testAutomaticRefreshAddsNewResponseAndFailurePreservesPreviousArchive() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), blessing = fixture()
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        let first = try await store.save(blessing: blessing, responses: [], userID: user, automatically: true)
        let response = responseFixture(blessing: blessing)
        let updated = try await store.save(blessing: first.blessing, responses: [response], userID: user,
            automatically: true, refreshing: true)
        XCTAssertEqual(updated.blessing.audioURL, first.blessing.audioURL, "Keep the already downloaded file")
        XCTAssertTrue(updated.responses[0].audioURL?.isFileURL == true)
        let failing = SavedBlessingStore(root: root, copier: FixtureArchiveCopier(failingFile: "video.mp4"))
        do {
            let newResponse = responseFixture(blessing: blessing).replacingAudio(URL(string: "https://example.com/video.mp4"))
            _ = try await failing.save(blessing: updated.blessing, responses: updated.responses + [newResponse], userID: user,
                automatically: true, refreshing: true)
            XCTFail("Download must fail")
        } catch {}
        let reloaded = try await store.load(userID: user)
        XCTAssertEqual(reloaded[blessing.id]?.responses.map(\.id), [response.id])
        XCTAssertEqual(reloaded[blessing.id]?.blessing.audioURL, first.blessing.audioURL)
    }

    @MainActor
    func testAutomaticSavingCoversCirclesWithoutUnlockingAndRespectsIndividualUnsave() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier())
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let secondary = try await repository.circleContext(circleID: bootstrap.circles[1].id)
        _ = try await repository.submit(promptID: XCTUnwrap(secondary.prompt?.id), authorID: bootstrap.currentUser.id,
            mode: .typed, body: "A blessing in my other circle", audioURL: nil, videoURL: nil, photoURL: nil,
            scriptureReference: nil, now: .now)
        let model = AppModel(repository: repository, savedBlessingStore: store)
        await model.bootstrap()
        await model.setAutomaticSavingEnabled(true)
        await model.saveVisibleBlessingsAutomatically()
        XCTAssertTrue(model.currentPromptBlessings().isEmpty)
        let allSaved = try await store.load(userID: bootstrap.currentUser.id)
        XCTAssertGreaterThan(Set(allSaved.values.map(\.blessing.circleID)).count, 1)
        XCTAssertTrue(allSaved.values.allSatisfy(\.isAutomatic))
        XCTAssertTrue(model.savedBlessings.values.allSatisfy { $0.blessing.circleID == model.circle?.id })
        let saved = try XCTUnwrap(allSaved.values.first)
        await model.unsaveBlessing(saved.blessing)
        await model.saveVisibleBlessingsAutomatically()
        XCTAssertNil(model.savedBlessings[saved.blessing.id])
        await model.pauseAutomaticSavingForSelection()
        let visibleIDs = Set(model.savedBlessings.keys)
        let keep = Set(model.automaticSavedBlessings.map(\.blessing.id))
        let disabled = await model.disableAutomaticSaving(keepingIDs: keep)
        XCTAssertTrue(disabled)
        XCTAssertFalse(model.automaticallySavesLocally)
        XCTAssertEqual(Set(model.savedBlessings.keys), visibleIDs)
        let kept = try await store.load(userID: bootstrap.currentUser.id)
        XCTAssertEqual(Set(kept.keys), keep)
        XCTAssertTrue(kept.values.allSatisfy { !$0.isAutomatic })
        let prefs = try await store.loadPreferences(userID: XCTUnwrap(model.currentUser?.id))
        XCTAssertFalse(prefs.isEnabled)
        XCTAssertTrue(prefs.hasChosen)
    }

    @MainActor
    func testKeepNoneNeverDeletesExistingManualSave() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(repository: LocalBlessingRepository(),
            savedBlessingStore: SavedBlessingStore(root: root, copier: FixtureArchiveCopier()))
        await model.bootstrap()
        let blessing = try XCTUnwrap(model.lanes.flatMap(\.events).compactMap { event -> Blessing? in
            if case let .blessing(value) = event.status, value.captureMode == .typed { return value }
            return nil
        }.first)
        let saved = await model.saveBlessing(blessing)
        XCTAssertTrue(saved)
        await model.setAutomaticSavingEnabled(true)
        await model.saveVisibleBlessingsAutomatically()
        XCTAssertGreaterThan(model.automaticSavedBlessings.count, 0)
        let disabled = await model.disableAutomaticSaving(keepingIDs: [])
        XCTAssertTrue(disabled)
        XCTAssertEqual(Array(model.savedBlessings.keys), [blessing.id])
        await model.saveVisibleBlessingsAutomatically()
        XCTAssertEqual(model.savedBlessings.count, 1)
    }

    func testNewDefaultAndExistingOptOutAndReminderStayAccountScoped() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedBlessingStore(root: root), user = UUID()
        let first = try await store.loadPreferences(userID: user)
        XCTAssertTrue(first.isEnabled)
        XCTAssertNil(first.showsExpiryReminder)
        try await store.savePreferences(LocalSavingPreferences(isEnabled: false, hasChosen: true, showsExpiryReminder: false), userID: user)
        let reopened = try await SavedBlessingStore(root: root).loadPreferences(userID: user)
        XCTAssertFalse(reopened.isEnabled)
        XCTAssertEqual(reopened.showsExpiryReminder, false)
        let other = try await store.loadPreferences(userID: UUID())
        XCTAssertTrue(other.isEnabled)
        XCTAssertNil(other.showsExpiryReminder)
    }

    func testMissingAndEmptyDownloadsCannotPublishOrClaimCompleteArchive() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), blessing = fixture()
        let missing = blessing.replacingMedia(audio: nil, video: nil, photo: nil)
        let store = SavedBlessingStore(root: root, copier: EmptyArchiveCopier())
        for post in [missing, blessing] {
            do { _ = try await store.save(blessing: post, responses: [], userID: user); XCTFail("Incomplete save succeeded") }
            catch { XCTAssertTrue(error is BlessingMediaSaveError) }
        }
        let records = try await store.load(userID: user)
        XCTAssertTrue(records.isEmpty)
    }

    func testUsageCountsOnlyCurrentAccountArchivesAndFallsAfterRemoval() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedBlessingStore(root: root, copier: FixtureArchiveCopier()), user = UUID(), post = fixture()
        _ = try await store.save(blessing: post, responses: [responseFixture(blessing: post)], userID: user)
        _ = try await store.save(blessing: fixture(), responses: [], userID: UUID())
        try await store.savePreferences(.init(), userID: user)
        let directory = root.appendingPathComponent(user.uuidString).appendingPathComponent(post.id.uuidString)
        let manifestBytes = try Data(contentsOf: directory.appendingPathComponent("blessing.json")).count
        let usage = try await store.usage(userID: user)
        XCTAssertEqual(usage.blessingCount, 1)
        XCTAssertEqual(usage.bytes, Int64(manifestBytes + 3 * Data("fixture media".utf8).count))
        try await store.unsave(blessingID: post.id, userID: user)
        let empty = try await store.usage(userID: user)
        XCTAssertEqual(empty.bytes, 0)
        XCTAssertEqual(empty.blessingCount, 0)
    }

#if DEBUG
    @MainActor
    func testWholeRetentionWindowIncludingOldParentResponseSavesBeforeSourceRemoval() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.caf")
        let bytes = Data("permanent synthetic recording bytes".utf8)
        try bytes.write(to: source)
        let now = Date(), repository = LocalBlessingRepository(now: now, retentionFixtureURL: source)
        let store = SavedBlessingStore(root: root.appendingPathComponent("saved"))
        let model = AppModel(repository: repository, savedBlessingStore: store, registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
        await model.bootstrap()
        XCTAssertTrue(model.automaticallySavesLocally)
        await model.reviewExpiringMedia(now: now)
        let due = model.expiringBlessings
        XCTAssertEqual(due.count, 3, "The older parent with recent voice audio must be included")
        let responsePreview = try XCTUnwrap(due.first { !$0.responses.isEmpty })
        XCTAssertEqual(responsePreview.responses.first?.audioURL, source, "Review must reuse the authorized response already fetched for inventory")
        XCTAssertTrue(due.contains { $0.blessing.submittedAt < now.addingTimeInterval(-40 * 86_400) })
        await model.saveVisibleBlessingsAutomatically()
        let user = try XCTUnwrap(model.currentUser?.id)
        for item in due {
            let savedRecord = await store.loadRecord(blessingID: item.id, userID: user)
            let record = try XCTUnwrap(savedRecord)
            let responses = try await repository.responses(blessingID: item.id, viewerID: user)
            XCTAssertTrue(record.covers(blessing: item.blessing, responses: responses))
        }
        await model.reviewExpiringMedia(now: now)
        XCTAssertTrue(model.expiringBlessings.isEmpty)
        XCTAssertNil(model.expiryReviewError)
        // Physically remove the source bytes, reopen the archive, and verify every recording.
        try FileManager.default.removeItem(at: source)
        let reopened = try await SavedBlessingStore(root: root.appendingPathComponent("saved")).load(userID: user)
        for item in due {
            let record = try XCTUnwrap(reopened[item.id])
            let urls = [record.blessing.audioURL, record.blessing.videoURL].compactMap { $0 }
                + record.responses.compactMap(\.audioURL)
            XCTAssertFalse(urls.isEmpty)
            for url in urls { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        }
    }

    @MainActor
    func testManualReviewRescueAndHiddenReminderPersistWithoutTurningSavingOn() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.caf")
        try Data("recording".utf8).write(to: source)
        let repository = LocalBlessingRepository(retentionFixtureURL: source)
        let store = SavedBlessingStore(root: root.appendingPathComponent("saved"))
        let model = AppModel(repository: repository, savedBlessingStore: store, registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
        await model.bootstrap()
        XCTAssertFalse(model.shouldShowTimelineExpiryReminder, "No known unsaved recording means no warning")
        await model.setAutomaticSavingEnabled(false)
        XCTAssertFalse(model.shouldShowTimelineExpiryReminder, "Turning saving off must not invent pending recordings")
        await model.reviewExpiringMedia()
        XCTAssertEqual(model.expiringBlessings.count, 3)
        XCTAssertTrue(model.shouldShowTimelineExpiryReminder)
        await model.setAutomaticSavingEnabled(true)
        XCTAssertFalse(model.shouldShowTimelineExpiryReminder)
        await model.setAutomaticSavingEnabled(false)
        await model.setExpiryReminderVisible(false)
        XCTAssertFalse(model.shouldShowTimelineExpiryReminder)
        let post = try XCTUnwrap(model.expiringBlessings.first?.blessing)
        let saved = await model.saveBlessing(post)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.expiringBlessings.count, 2)
        XCTAssertGreaterThan(model.localArchiveUsage?.bytes ?? 0, 0)
        let reopened = AppModel(repository: repository, savedBlessingStore: store, registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
        await reopened.bootstrap()
        XCTAssertFalse(reopened.automaticallySavesLocally)
        XCTAssertFalse(reopened.showsExpiryReminder)
        await reopened.reviewExpiringMedia()
        XCTAssertEqual(reopened.expiringBlessings.count, 2)
        XCTAssertFalse(reopened.shouldShowTimelineExpiryReminder)
        await reopened.setExpiryReminderVisible(true)
        XCTAssertTrue(reopened.shouldShowTimelineExpiryReminder)
        for item in reopened.expiringBlessings {
            let saved = await reopened.saveBlessing(item.blessing)
            XCTAssertTrue(saved)
        }
        XCTAssertFalse(reopened.shouldShowTimelineExpiryReminder, "Saving the final recording must remove the warning immediately")
        await reopened.reviewExpiringMedia()
        XCTAssertFalse(reopened.shouldShowTimelineExpiryReminder)
    }
#endif

    private func fixture(mode: CaptureMode = .voice, sent: Date = .now, circleID: UUID? = nil, authorID: UUID? = nil) -> Blessing {
        Blessing(
            id: UUID(), circleID: circleID ?? UUID(), promptID: UUID(), authorID: authorID ?? UUID(), captureMode: mode,
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

private actor CountingArchiveCopier: SavedBlessingMediaCopying {
    private(set) var count = 0
    func copy(from source: URL, to destination: URL) async throws {
        count += 1
        try Data("saved media".utf8).write(to: destination)
    }
}

private actor PausedArchiveCopier: SavedBlessingMediaCopying {
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasPaused = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    func waitUntilPaused() async {
        if hasPaused { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    var isWaiting: Bool { continuation != nil }
    func resume() { continuation?.resume(); continuation = nil }
    func copy(from source: URL, to destination: URL) async throws {
        if !hasPaused {
            hasPaused = true
            startWaiters.forEach { $0.resume() }; startWaiters = []
            await withCheckedContinuation { continuation = $0 }
        }
        // Simulate a transport which recreates its target after account cleanup.
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("in-flight private media".utf8).write(to: destination)
    }
}

private struct EmptyArchiveCopier: SavedBlessingMediaCopying {
    func copy(from source: URL, to destination: URL) async throws { try Data().write(to: destination) }
}
