import XCTest
@testable import BlessingCircle

final class CircleMetadataStoreTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_790_000_000)

    func testPersistsDisplayMetadataAcrossStoreInstancesWithoutInvitationsOrSharedPermissions() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let user = member()
        var circle = circle(user: user)
        circle.inviteCode = "PRIVATE-INVITATION"
        circle.allowMemberCircleChanges = true
        circle.photoURL = URL(string: "https://example.invalid/circle-photo")
        circle.streaks = [user.id: CircleStreak(memberID: user.id, days: 8, onTimeDays: 6, onTimeToday: true, onTimeStreakDays: 2)]
        let date = instant
        await CircleMetadataStore(directory: directory, now: { date })
            .save(accountID: user.id, currentUser: user, circles: [circle], selectedCircleID: circle.id)
        let loaded = await CircleMetadataStore(directory: directory, now: { date.addingTimeInterval(60) }).load(accountID: user.id)
        let snapshot = try XCTUnwrap(loaded)
        XCTAssertEqual(snapshot.currentUser, user)
        XCTAssertEqual(snapshot.updatedAt, date)
        XCTAssertEqual(snapshot.selectedCircleID, circle.id)
        let restored = try XCTUnwrap(snapshot.circles.first)
        XCTAssertEqual(restored.name, circle.name)
        XCTAssertEqual(restored.members, circle.members)
        XCTAssertEqual(restored.ownerID, circle.ownerID, "Ownership is a display hint only")
        XCTAssertEqual(restored.streaks, circle.streaks)
        XCTAssertEqual(restored.photoURL, circle.photoURL)
        XCTAssertEqual(restored.inviteCode, "")
        XCTAssertFalse(restored.allowMemberCircleChanges)
        let encoded = try String(contentsOf: fileURL(directory, accountID: user.id), encoding: .utf8)
        XCTAssertFalse(encoded.contains("PRIVATE-INVITATION"))
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        let body = try XCTUnwrap(top["snapshot"] as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(["currentUser", "circles", "selectedCircleID", "updatedAt"]))
        let backup = try fileURL(directory, accountID: user.id).resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(backup.isExcludedFromBackup, true)
    }

    func testDifferentAccountsCannotLoadOrRemoveEachOthersMetadata() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = instant
        let store = CircleMetadataStore(directory: directory, now: { date })
        let first = member(), second = member()
        let firstCircle = circle(user: first), secondCircle = circle(user: second)
        await store.save(accountID: first.id, currentUser: first, circles: [firstCircle], selectedCircleID: firstCircle.id)
        let absent = await store.load(accountID: second.id)
        XCTAssertNil(absent)
        await store.save(accountID: second.id, currentUser: second, circles: [secondCircle], selectedCircleID: secondCircle.id)
        await store.remove(accountID: first.id)
        let removed = await store.load(accountID: first.id)
        let retained = await store.load(accountID: second.id)
        XCTAssertNil(removed)
        XCTAssertEqual(retained?.currentUser.id, second.id)
        XCTAssertEqual(retained?.circles.map(\.id), [secondCircle.id])
    }

    func testSaveRejectsMismatchedIdentityAndClearsOnlyThatAccount() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = instant
        let store = CircleMetadataStore(directory: directory, now: { date })
        let first = member(), second = member()
        await store.save(accountID: first.id, currentUser: first, circles: [], selectedCircleID: nil)
        await store.save(accountID: second.id, currentUser: second, circles: [], selectedCircleID: nil)
        await store.save(accountID: first.id, currentUser: second, circles: [], selectedCircleID: nil)
        let rejected = await store.load(accountID: first.id)
        let retained = await store.load(accountID: second.id)
        XCTAssertNil(rejected)
        XCTAssertEqual(retained?.currentUser.id, second.id)
    }

    func testMembershipFilteringClearsInvalidSelectionAndUnrelatedStreaks() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = instant
        let store = CircleMetadataStore(directory: directory, now: { date })
        let user = member(), outsider = member()
        var valid = circle(user: user)
        valid.streaks = [outsider.id: CircleStreak(memberID: outsider.id, days: 99, onTimeDays: 99, onTimeToday: true)]
        let unrelated = circle(user: outsider)
        var duplicatedMembers = circle(user: user)
        duplicatedMembers.members.append(user)
        await store.save(accountID: user.id, currentUser: user,
                         circles: [valid, valid, unrelated, duplicatedMembers], selectedCircleID: unrelated.id)
        let loaded = await store.load(accountID: user.id)
        let snapshot = try XCTUnwrap(loaded)
        XCTAssertEqual(snapshot.circles.map(\.id), [valid.id])
        XCTAssertNil(snapshot.selectedCircleID)
        XCTAssertEqual(snapshot.circles.first?.streaks?.count, 0)
    }

    func testDisplayMetadataPersistsAcrossLongOfflineAbsenceAndClockChanges() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = instant
        let user = member(), group = circle(user: member())
        let writer = CircleMetadataStore(directory: directory, now: { date })
        await writer.save(accountID: user.id, currentUser: user, circles: [circle(user: user)], selectedCircleID: group.id)
        for offset in [90.0 * 86_400, -86_400] {
            let restored = await CircleMetadataStore(directory: directory, now: { date.addingTimeInterval(offset) }).load(accountID: user.id)
            XCTAssertEqual(restored?.currentUser, user)
            XCTAssertEqual(restored?.circles.count, 1)
            XCTAssertEqual(restored?.circles.first?.inviteCode, "")
        }
    }

    func testCorruptAndRelabeledFilesNeverBecomeAnotherAccountsSnapshot() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = instant
        let store = CircleMetadataStore(directory: directory, now: { date })
        let first = member(), second = member()
        await store.save(accountID: first.id, currentUser: first, circles: [], selectedCircleID: nil)
        try FileManager.default.copyItem(at: fileURL(directory, accountID: first.id), to: fileURL(directory, accountID: second.id))
        let relabeled = await store.load(accountID: second.id)
        XCTAssertNil(relabeled)
        try Data("corrupt metadata".utf8).write(to: fileURL(directory, accountID: first.id))
        let corrupt = await store.load(accountID: first.id)
        XCTAssertNil(corrupt)
    }

    func testReadSanitizesInvitationAndPermissionsFromOlderOrModifiedCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = instant
        let store = CircleMetadataStore(directory: directory, now: { date })
        let user = member(), circle = circle(user: user)
        await store.save(accountID: user.id, currentUser: user, circles: [circle], selectedCircleID: circle.id)
        let url = fileURL(directory, accountID: user.id)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var snapshot = try XCTUnwrap(envelope["snapshot"] as? [String: Any])
        var circles = try XCTUnwrap(snapshot["circles"] as? [[String: Any]])
        circles[0]["inviteCode"] = "OLD-SECRET"
        circles[0]["allowMemberCircleChanges"] = true
        snapshot["circles"] = circles
        envelope["snapshot"] = snapshot
        try JSONSerialization.data(withJSONObject: envelope).write(to: url)
        let loaded = await store.load(accountID: user.id)
        XCTAssertEqual(loaded?.circles.first?.inviteCode, "")
        XCTAssertEqual(loaded?.circles.first?.allowMemberCircleChanges, false)
    }

    private func member() -> Member {
        Member(id: UUID(), displayName: "Synthetic member", initials: "SM", tintSeed: 1,
               avatarURL: URL(string: "https://example.invalid/profile-photo"))
    }

    private func circle(user: Member) -> CircleGroup {
        CircleGroup(id: UUID(), name: "Synthetic circle", inviteCode: "SECRET", ownerID: user.id,
                    members: [user], timeZoneIdentifier: "America/New_York", randomWindowStartMinutes: 720,
                    randomWindowEndMinutes: 1_200, responseWindowMinutes: 10, allowsLateBlessings: true,
                    repeatWindowMinutes: 120)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MannaMetadataTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func fileURL(_ directory: URL, accountID: UUID) -> URL {
        directory.appendingPathComponent(accountID.uuidString.lowercased()).appendingPathExtension("json")
    }
}
