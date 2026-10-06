import XCTest
import UIKit
@testable import BlessingCircle

final class DomainRulesTests: XCTestCase {
    func testMediaTimeFormatterUsesStableMinuteAndSecondLabels() {
        XCTAssertEqual(MediaTimeFormatter.string(for: 0), "0:00")
        XCTAssertEqual(MediaTimeFormatter.string(for: 9.9), "0:09")
        XCTAssertEqual(MediaTimeFormatter.string(for: 65), "1:05")
        XCTAssertEqual(MediaTimeFormatter.string(for: .infinity), "0:00")
    }

    func testHostedMediaPathUsesPostgresUUIDCasing() {
        let path = SupabaseBlessingRepository.mediaPath(
            circleID: UUID(uuidString: "D315040F-5F3D-4EEA-8C42-46145CCE2371")!,
            promptID: UUID(uuidString: "1D30024F-D3D1-4539-81D1-B0A160F5012D")!,
            userID: UUID(uuidString: "013F3D7F-1DA3-48AD-B70A-B496E6F3EE5E")!
        )

        XCTAssertEqual(
            path,
            "d315040f-5f3d-4eea-8c42-46145cce2371/1d30024f-d3d1-4539-81d1-b0a160f5012d/013f3d7f-1da3-48ad-b70a-b496e6f3ee5e"
        )
    }

    func testRefreshedCirclePreservesNewlyCreatedInviteCode() {
        let id = UUID()
        let ownerID = UUID()
        let created = CircleGroup(
            id: id,
            name: "Morning Light",
            inviteCode: "MANNA7",
            ownerID: ownerID,
            members: [],
            timeZoneIdentifier: "UTC",
            randomWindowStartMinutes: 480,
            randomWindowEndMinutes: 1_200,
            responseWindowMinutes: 10,
            allowsLateBlessings: false,
            repeatWindowMinutes: 120
        )
        var refreshed = created
        refreshed.inviteCode = ""

        XCTAssertEqual(
            refreshed.preservingInviteCode(created.inviteCode).inviteCode,
            "MANNA7"
        )
    }

    func testRefreshDoesNotReplaceAProvidedInviteCode() {
        let circle = CircleGroup(
            id: UUID(),
            name: "Morning Light",
            inviteCode: "FRESH8",
            ownerID: UUID(),
            members: [],
            timeZoneIdentifier: "UTC",
            randomWindowStartMinutes: 480,
            randomWindowEndMinutes: 1_200,
            responseWindowMinutes: 10,
            allowsLateBlessings: false,
            repeatWindowMinutes: 120
        )

        XCTAssertEqual(circle.preservingInviteCode("OLDER7").inviteCode, "FRESH8")
    }

    func testAppIconPreferenceMapsAlternateIconNames() {
        XCTAssertEqual(AppIconPreference(alternateIconName: nil), .automatic)
        XCTAssertEqual(AppIconPreference(alternateIconName: "MannaLight"), .cream)
        XCTAssertEqual(AppIconPreference(alternateIconName: "MannaDark"), .midnight)
        XCTAssertEqual(AppIconPreference.automatic.alternateIconName, nil)
        XCTAssertEqual(AppIconPreference.cream.alternateIconName, "MannaLight")
        XCTAssertEqual(AppIconPreference.midnight.alternateIconName, "MannaDark")
    }

    func testPublicDomainBibleVersionsAreGroupedInPopularityOrder() {
        let groups = BibleTranslation.groups

        XCTAssertEqual(groups.prefix(4).map(\.id), ["en", "zh", "es", "ar"])
        XCTAssertTrue(groups.first(where: { $0.id == "es" })?.translations.contains(where: { $0.id == "rvr1909" }) == true)
        XCTAssertTrue(groups.first(where: { $0.id == "ja" })?.translations.contains(where: { $0.id == "kgy" }) == true)
        XCTAssertEqual(Set(BibleTranslation.publicDomain.map(\.languageCode)).count, 12)
    }

    func testResponsesCanOnlyBeComposedForTheCurrentDayPrompt() {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let prompt = DailyPrompt(
            id: UUID(),
            circleID: UUID(),
            localDate: now,
            startsAt: now.addingTimeInterval(-60),
            endsAt: now.addingTimeInterval(540)
        )
        let currentBlessing = Blessing.fixture(promptID: prompt.id, submittedAt: now)
        let historicalBlessing = Blessing.fixture(promptID: UUID(), submittedAt: now.addingTimeInterval(-86_400))

        XCTAssertTrue(
            ResponseCompositionPolicy.canRespond(
                to: currentBlessing,
                currentPrompt: prompt,
                isCurrentPromptToday: true
            )
        )
        XCTAssertFalse(
            ResponseCompositionPolicy.canRespond(
                to: historicalBlessing,
                currentPrompt: prompt,
                isCurrentPromptToday: true
            )
        )
        XCTAssertFalse(
            ResponseCompositionPolicy.canRespond(
                to: currentBlessing,
                currentPrompt: prompt,
                isCurrentPromptToday: false
            )
        )
    }

    func testWidgetPrioritizesAnUnsubmittedActivePrompt() throws {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let prompt = BlessingWidgetPrompt(
            promptID: UUID(),
            circleID: UUID(),
            circleName: "Morning Prayer",
            startsAt: now.addingTimeInterval(-60),
            endsAt: now.addingTimeInterval(540),
            viewerHasSubmitted: false,
            isOnCurrentCircleDay: true
        )
        let snapshot = BlessingWidgetSnapshot(
            generatedAt: now,
            refreshIntervalMinutes: 30,
            prompts: [prompt],
            blessings: [.fixture(submittedAt: now.addingTimeInterval(-120), isToday: true)]
        )

        guard case let .share(selected) = snapshot.content(at: now) else {
            return XCTFail("Expected the active prompt to take precedence")
        }
        XCTAssertEqual(selected.circleName, "Morning Prayer")
    }

    func testWidgetPrefersUnseenCurrentDayBlessingsAfterPromptStarts() throws {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let shown = BlessingWidgetBlessing.fixture(submittedAt: now.addingTimeInterval(-60), isToday: true)
        let unseen = BlessingWidgetBlessing.fixture(submittedAt: now.addingTimeInterval(-120), isToday: true)
        let prior = BlessingWidgetBlessing.fixture(submittedAt: now.addingTimeInterval(-86_400), isToday: false)
        let prompt = BlessingWidgetPrompt(
            promptID: UUID(),
            circleID: UUID(),
            circleName: "Sunday Table",
            startsAt: now.addingTimeInterval(-600),
            endsAt: now.addingTimeInterval(-1),
            viewerHasSubmitted: true,
            isOnCurrentCircleDay: true
        )
        let snapshot = BlessingWidgetSnapshot(
            generatedAt: now,
            refreshIntervalMinutes: 30,
            prompts: [prompt],
            blessings: [shown, unseen, prior]
        )

        guard case let .blessing(selected) = snapshot.content(at: now, recentlyShownIDs: [shown.id]) else {
            return XCTFail("Expected a blessing")
        }
        XCTAssertEqual(selected.id, unseen.id)
    }

    func testWidgetFallsBackToPriorDayBeforeAnyPromptStarts() throws {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let futurePrompt = BlessingWidgetPrompt(
            promptID: UUID(),
            circleID: UUID(),
            circleName: "Sunday Table",
            startsAt: now.addingTimeInterval(600),
            endsAt: now.addingTimeInterval(1_200),
            viewerHasSubmitted: false,
            isOnCurrentCircleDay: true
        )
        let today = BlessingWidgetBlessing.fixture(submittedAt: now, isToday: true)
        let prior = BlessingWidgetBlessing.fixture(submittedAt: now.addingTimeInterval(-86_400), isToday: false)
        let snapshot = BlessingWidgetSnapshot(
            generatedAt: now,
            refreshIntervalMinutes: 30,
            prompts: [futurePrompt],
            blessings: [today, prior]
        )

        guard case let .blessing(selected) = snapshot.content(at: now) else {
            return XCTFail("Expected the prior-day fallback")
        }
        XCTAssertEqual(selected.id, prior.id)
    }

    func testWidgetReturnsEmptyWhenNoPromptOrBlessingIsAvailable() {
        let now = Date(timeIntervalSince1970: 2_100_000_000)

        XCTAssertEqual(BlessingWidgetSnapshot.empty.content(at: now), .empty)
        XCTAssertEqual(
            BlessingWidgetSnapshot.empty.nextRefreshDate(after: now),
            now.addingTimeInterval(30 * 60)
        )
    }

    func testWidgetRefreshesAtTheNextPromptBoundaryBeforeTheRotationInterval() {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let startsAt = now.addingTimeInterval(90)
        let prompt = BlessingWidgetPrompt(
            promptID: UUID(),
            circleID: UUID(),
            circleName: "Evening Prayer",
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(600),
            viewerHasSubmitted: false,
            isOnCurrentCircleDay: true
        )
        let snapshot = BlessingWidgetSnapshot(
            generatedAt: now,
            refreshIntervalMinutes: 30,
            prompts: [prompt],
            blessings: []
        )

        XCTAssertEqual(snapshot.nextRefreshDate(after: now), startsAt)
        XCTAssertEqual(snapshot.content(at: startsAt), .share(prompt))
    }

    @MainActor
    func testTodayFeedUnlocksAllVisibleCurrentPromptBlessingsAfterSubmission() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let model = AppModel(repository: repository)
        await model.bootstrap()
        let primaryCircleID = try XCTUnwrap(model.circles.first?.id)
        await model.switchCircle(to: primaryCircleID)

        XCTAssertTrue(model.currentPromptBlessings().isEmpty)
        let didSubmit = await model.submit(
            mode: .typed,
            body: "A local test blessing",
            audioURL: nil,
            videoURL: nil,
            scriptureReference: nil
        )

        XCTAssertTrue(didSubmit)
        let visibleNames = Set(model.currentPromptBlessings().map(\.member.displayName))
        XCTAssertTrue(visibleNames.contains("Micah"), "The viewer's blessing should be in the Today feed")
        XCTAssertTrue(visibleNames.contains("Ava"), "A visible peer blessing should be in the Today feed")
    }

    func testForcedCirclePromptRequiresOwnerAndRestartsWindow() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        let ownerCircle = try XCTUnwrap(bootstrap.circles.first)
        let forcedAt = now.addingTimeInterval(30)

        let dispatch = try await repository.forceCirclePrompt(
            circleID: ownerCircle.id,
            ownerID: bootstrap.currentUser.id,
            now: forcedAt
        )

        XCTAssertEqual(dispatch.prompt.startsAt, forcedAt)
        XCTAssertEqual(
            dispatch.prompt.endsAt,
            forcedAt.addingTimeInterval(ownerCircle.responseWindowDuration)
        )
        XCTAssertEqual(dispatch.memberCount, ownerCircle.members.count)
        XCTAssertEqual(dispatch.registeredDevices, 0)
    }

    func testForcedCirclePromptRejectsNonOwner() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let bootstrap = try await repository.bootstrap()
        let memberOnlyCircle = try XCTUnwrap(
            bootstrap.circles.first(where: { $0.ownerID != bootstrap.currentUser.id })
        )

        do {
            _ = try await repository.forceCirclePrompt(
                circleID: memberOnlyCircle.id,
                ownerID: bootstrap.currentUser.id,
                now: .now
            )
            XCTFail("Expected a non-owner force attempt to fail")
        } catch let error as BlessingError {
            XCTAssertEqual(error, .notCircleOwner)
        }
    }

#if DEBUG
    @MainActor
    func testDebugPromptRestartsLocalWindowAndAllowsFreshSubmission() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let model = AppModel(repository: repository)
        await model.bootstrap()

        let firstSubmissionSucceeded = await model.submit(
            mode: .typed,
            body: "First local test",
            audioURL: nil,
            videoURL: nil,
            scriptureReference: nil
        )
        XCTAssertTrue(firstSubmissionSucceeded)
        XCTAssertTrue(model.hasSubmittedToday)

        let restartedAt = Date().addingTimeInterval(-1)
        await model.startDebugDailyBlessing(now: restartedAt)

        XCTAssertEqual(model.prompt?.startsAt, restartedAt)
        XCTAssertEqual(
            model.prompt?.endsAt,
            restartedAt.addingTimeInterval(TimeInterval(model.circle?.responseWindowMinutes ?? 0) * 60)
        )
        XCTAssertFalse(model.hasSubmittedToday)
        XCTAssertFalse(model.isDebugPromptPreview)
        XCTAssertTrue(model.canSubmitCurrentPrompt)
    }
#endif

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

    func testSelectedPhotoIsConvertedToStableJPEGStorage() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let sourceData = try XCTUnwrap(image.pngData())

        let persistedURL = try CaptureMediaStore.persistPhoto(data: sourceData)
        defer { try? FileManager.default.removeItem(at: persistedURL) }

        XCTAssertEqual(persistedURL.pathExtension, "jpg")
        XCTAssertNotNil(UIImage(contentsOfFile: persistedURL.path))
        XCTAssertTrue(persistedURL.path.contains("BlessingCaptures"))
    }

    func testProfilePhotoIsDownsampledBeforeUpload() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2_400, height: 1_600)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 1_600))
        }
        let sourceData = try XCTUnwrap(image.pngData())
        let persistedURL = try CaptureMediaStore.persistProfilePhoto(data: sourceData)
        defer { try? FileManager.default.removeItem(at: persistedURL) }

        let persistedImage = try XCTUnwrap(UIImage(contentsOfFile: persistedURL.path))
        XCTAssertLessThanOrEqual(max(persistedImage.size.width, persistedImage.size.height), 1_024)
        XCTAssertLessThan(try Data(contentsOf: persistedURL).count, sourceData.count)
    }

    func testTypedBlessingCanIncludeOptionalPhoto() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        let prompt = try XCTUnwrap(bootstrap.prompt)
        let photoURL = URL(fileURLWithPath: "/tmp/blessing-photo.jpg")

        let blessing = try await repository.submit(
            promptID: prompt.id,
            authorID: bootstrap.currentUser.id,
            mode: .typed,
            body: "A photographed blessing",
            audioURL: nil,
            videoURL: nil,
            photoURL: photoURL,
            scriptureReference: nil,
            now: now
        )

        XCTAssertEqual(blessing.photoURL, photoURL)
    }

    func testVoiceBlessingCanIncludeOptionalPhoto() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        let prompt = try XCTUnwrap(bootstrap.prompt)
        let audioURL = URL(fileURLWithPath: "/tmp/blessing-audio.caf")
        let photoURL = URL(fileURLWithPath: "/tmp/blessing-photo.jpg")

        let blessing = try await repository.submit(
            promptID: prompt.id,
            authorID: bootstrap.currentUser.id,
            mode: .voice,
            body: "A spoken blessing with a photo",
            audioURL: audioURL,
            videoURL: nil,
            photoURL: photoURL,
            scriptureReference: nil,
            now: now
        )

        XCTAssertEqual(blessing.audioURL, audioURL)
        XCTAssertEqual(blessing.photoURL, photoURL)
    }

    func testVideoBlessingRejectsPhotoAttachment() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        let prompt = try XCTUnwrap(bootstrap.prompt)

        do {
            _ = try await repository.submit(
                promptID: prompt.id,
                authorID: bootstrap.currentUser.id,
                mode: .video,
                body: "Video transcript",
                audioURL: nil,
                videoURL: URL(fileURLWithPath: "/tmp/blessing.mov"),
                photoURL: URL(fileURLWithPath: "/tmp/blessing-photo.jpg"),
                scriptureReference: nil,
                now: now
            )
            XCTFail("Expected video-plus-photo submission to fail")
        } catch let error as BlessingError {
            XCTAssertEqual(error, .emptyBlessing)
        }
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
            allowsLateBlessings: true,
            repeatWindowMinutes: 180
        )

        XCTAssertEqual(updated.responseWindowMinutes, 40)
        XCTAssertTrue(updated.allowsLateBlessings)
        XCTAssertEqual(updated.name, "Morning Light")
        XCTAssertEqual(updated.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(updated.repeatWindowMinutes, 180)
    }

    func testRepeatEligibilityUsesTargetCircleWindowAndOriginalSubmissionTime() throws {
        let authorID = UUID()
        let sourceCircleID = UUID()
        let targetCircle = CircleGroup(
            id: UUID(),
            name: "Second circle",
            inviteCode: "SECOND",
            ownerID: authorID,
            members: [],
            timeZoneIdentifier: "UTC",
            randomWindowStartMinutes: 480,
            randomWindowEndMinutes: 1_200,
            responseWindowMinutes: 10,
            allowsLateBlessings: false,
            repeatWindowMinutes: 60
        )
        let sentAt = Date(timeIntervalSince1970: 2_000_000_000)
        let source = Blessing(
            id: UUID(),
            circleID: sourceCircleID,
            promptID: UUID(),
            authorID: authorID,
            captureMode: .voice,
            body: "A timely blessing",
            audioURL: URL(fileURLWithPath: "/tmp/source.caf"),
            videoURL: nil,
            submittedAt: sentAt,
            isLate: false,
            scriptureReference: nil
        )

        XCTAssertTrue(
            RepeatBlessingPolicy.isEligible(
                source: source,
                targetCircle: targetCircle,
                authorID: authorID,
                now: sentAt.addingTimeInterval(3_600)
            )
        )
        XCTAssertFalse(
            RepeatBlessingPolicy.isEligible(
                source: source,
                targetCircle: targetCircle,
                authorID: authorID,
                now: sentAt.addingTimeInterval(3_601)
            )
        )
    }

    func testRepeatingBlessingCopiesMessageAndScriptureIntoTargetCircle() async throws {
        let now = Date()
        let repository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        let user = bootstrap.currentUser
        let sourcePrompt = try XCTUnwrap(bootstrap.prompt)
        let targetCircle = try XCTUnwrap(bootstrap.circles.last)
        let targetContext = try await repository.circleContext(circleID: targetCircle.id)
        let targetPrompt = try XCTUnwrap(targetContext.prompt)
        let reference = ScriptureReference(
            bookSlug: "psalms",
            bookName: "Psalms",
            chapter: 23,
            verseStart: 1,
            verseEnd: 2
        )
        let source = try await repository.submit(
            promptID: sourcePrompt.id,
            authorID: user.id,
            mode: .voice,
            body: "Provision in a difficult week.",
            audioURL: URL(fileURLWithPath: "/tmp/source.caf"),
            videoURL: nil,
            scriptureReference: reference,
            now: now
        )

        let repeated = try await repository.repeatBlessing(
            sourceBlessingID: source.id,
            targetPromptID: targetPrompt.id,
            authorID: user.id,
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(repeated.circleID, targetCircle.id)
        XCTAssertEqual(repeated.captureMode, .typed)
        XCTAssertEqual(repeated.body, source.body)
        XCTAssertEqual(repeated.scriptureReference, reference)
        XCTAssertEqual(repeated.repeatedFromBlessingID, source.id)
        XCTAssertNil(repeated.audioURL)
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

    func testOwnerCanRemoveAnotherCurrentCircleMember() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let bootstrap = try await repository.bootstrap()
        let owner = bootstrap.currentUser
        let circle = try XCTUnwrap(bootstrap.circle)
        let member = try XCTUnwrap(circle.members.first(where: { $0.id != owner.id }))

        let updated = try await repository.removeCircleMember(
            circleID: circle.id,
            ownerID: owner.id,
            memberID: member.id
        )

        XCTAssertFalse(updated.members.contains(where: { $0.id == member.id }))
        XCTAssertEqual(updated.ownerID, owner.id)
    }

    func testOwnerCannotRemoveThemself() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let bootstrap = try await repository.bootstrap()
        let owner = bootstrap.currentUser
        let circle = try XCTUnwrap(bootstrap.circle)

        do {
            _ = try await repository.removeCircleMember(
                circleID: circle.id,
                ownerID: owner.id,
                memberID: owner.id
            )
            XCTFail("Expected self-removal to require the leave flow")
        } catch let error as BlessingError {
            XCTAssertEqual(error, .invalidMemberRemoval)
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

    func testProfileUpdatePropagatesAcrossLocalCircles() async throws {
        let repository = LocalBlessingRepository(now: .now)
        let before = try await repository.bootstrap()
        let updated = try await repository.updateProfile(
            memberID: before.currentUser.id,
            displayName: "Manna Friend",
            avatarURL: URL(string: "file:///tmp/avatar.jpg")
        )
        let after = try await repository.bootstrap()

        XCTAssertEqual(updated.displayName, "Manna Friend")
        XCTAssertEqual(updated.initials, "MF")
        XCTAssertTrue(after.circles.allSatisfy { circle in
            circle.members.first(where: { $0.id == updated.id })?.displayName == "Manna Friend"
        })
    }

    func testFirstDayMemberCanSubmitOutsidePromptWindowOnlyOnJoinDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let member = Member(id: UUID(), displayName: "New Friend", initials: "NF", tintSeed: 1, joinedAt: day.addingTimeInterval(8 * 3_600))
        let circle = CircleGroup(
            id: UUID(), name: "Test", inviteCode: "TEST12", ownerID: member.id, members: [member],
            timeZoneIdentifier: calendar.timeZone.identifier, randomWindowStartMinutes: 480,
            randomWindowEndMinutes: 1_200, responseWindowMinutes: 10,
            allowsLateBlessings: false, repeatWindowMinutes: 60
        )
        let prompt = DailyPrompt(
            id: UUID(), circleID: circle.id, localDate: day,
            startsAt: day.addingTimeInterval(18 * 3_600), endsAt: day.addingTimeInterval(18 * 3_600 + 600)
        )

        XCTAssertTrue(FirstDaySubmissionPolicy.isEligible(
            memberJoinedAt: member.joinedAt, prompt: prompt, circle: circle,
            now: day.addingTimeInterval(10 * 3_600)
        ))
        XCTAssertFalse(FirstDaySubmissionPolicy.isEligible(
            memberJoinedAt: member.joinedAt, prompt: prompt, circle: circle,
            now: day.addingTimeInterval(26 * 3_600)
        ))
    }
}

private extension BlessingWidgetBlessing {
    static func fixture(submittedAt: Date, isToday: Bool) -> BlessingWidgetBlessing {
        BlessingWidgetBlessing(
            id: UUID(),
            circleID: UUID(),
            circleName: "Sunday Table",
            authorName: "Ava",
            captureMode: .typed,
            transcript: "A test blessing",
            submittedAt: submittedAt,
            isFromCurrentCircleDay: isToday,
            scriptureReference: nil,
            scriptureText: nil,
            bibleVersionName: nil
        )
    }
}

private extension Blessing {
    static func fixture(promptID: UUID, submittedAt: Date) -> Blessing {
        Blessing(
            id: UUID(),
            circleID: UUID(),
            promptID: promptID,
            authorID: UUID(),
            captureMode: .typed,
            body: "A test blessing",
            audioURL: nil,
            videoURL: nil,
            submittedAt: submittedAt,
            isLate: false,
            scriptureReference: nil
        )
    }
}
