import XCTest
@testable import BlessingCircle

final class SharedCircleSettingsTests: XCTestCase {
    func testLegacySnapshotRemainsOwnerOnlyAndExplicitFlagRoundTrips() async throws {
        let bootstrap = try await LocalBlessingRepository().bootstrap()
        var circle = try XCTUnwrap(bootstrap.circle)
        let peer = try XCTUnwrap(circle.members.first { $0.id != circle.ownerID })
        XCTAssertTrue(circle.canManageSettings(memberID: circle.ownerID))
        XCTAssertFalse(circle.canManageSettings(memberID: peer.id))
        let encoded = try JSONEncoder().encode(circle)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "allowMemberCircleChanges")
        let legacy = try JSONDecoder().decode(CircleGroup.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(legacy.allowMemberCircleChanges)
        XCTAssertFalse(legacy.canManageSettings(memberID: peer.id))
        circle.allowMemberCircleChanges = true
        let restored = try JSONDecoder().decode(CircleGroup.self, from: JSONEncoder().encode(circle))
        XCTAssertTrue(restored.allowMemberCircleChanges)
        XCTAssertTrue(restored.canManageSettings(memberID: peer.id))
        XCTAssertFalse(restored.canManageSettings(memberID: UUID()))
    }

    func testLeaderEnablesAndRevokesMemberSettingsWithoutChangingOwnership() async throws {
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let peer = try XCTUnwrap(circle.members.first { $0.id != circle.ownerID })
        await assertDenied { try await Self.saveSettings(repository, circle: circle, actor: peer.id, name: "Denied") }
        let enabled = try await repository.setCircleMemberChanges(circleID: circle.id, ownerID: circle.ownerID, allowed: true)
        XCTAssertTrue(enabled.allowMemberCircleChanges)
        let edited = try await Self.saveSettings(repository, circle: circle, actor: peer.id, name: "Shared circle")
        XCTAssertEqual(edited.name, "Shared circle")
        XCTAssertEqual(edited.ownerID, circle.ownerID)
        XCTAssertTrue(edited.allowMemberCircleChanges)
        _ = try await repository.setCircleMemberChanges(circleID: circle.id, ownerID: circle.ownerID, allowed: false)
        await assertDenied { try await Self.saveSettings(repository, circle: circle, actor: peer.id, name: "Revoked") }
        let final = try await repository.circleContext(circleID: circle.id)
        XCTAssertEqual(final.circle.name, "Shared circle")
        XCTAssertFalse(final.circle.allowMemberCircleChanges)
    }

    func testEnabledMembersCanRotatePhotoForceAndRemoveAnotherOrdinaryMember() async throws {
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let peers = circle.members.filter { $0.id != circle.ownerID }
        let actor = try XCTUnwrap(peers.first)
        let target = try XCTUnwrap(peers.last)
        XCTAssertNotEqual(actor.id, target.id)
        _ = try await repository.setCircleMemberChanges(circleID: circle.id, ownerID: circle.ownerID, allowed: true)
        let rotated = try await repository.regenerateInviteCode(circleID: circle.id, ownerID: actor.id)
        XCTAssertNotEqual(rotated.inviteCode, circle.inviteCode)
        let photoURL = URL(fileURLWithPath: "/tmp/synthetic-circle-photo.jpg")
        let photo = try await repository.updateCirclePhoto(circleID: circle.id, ownerID: actor.id, photoURL: photoURL)
        XCTAssertEqual(photo.photoURL, photoURL)
        let forced = try await repository.forceCirclePrompt(circleID: circle.id, ownerID: actor.id, now: .now)
        XCTAssertEqual(forced.prompt.circleID, circle.id)
        let removed = try await repository.removeCircleMember(circleID: circle.id, ownerID: actor.id, memberID: target.id)
        XCTAssertFalse(removed.members.contains { $0.id == target.id })
        XCTAssertTrue(removed.members.contains { $0.id == circle.ownerID })
    }

    func testOffBlocksEveryGeneralMemberMutation() async throws {
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let peer = try XCTUnwrap(circle.members.first { $0.id != circle.ownerID })
        let other = try XCTUnwrap(circle.members.last { $0.id != circle.ownerID && $0.id != peer.id })
        await assertDenied { try await repository.regenerateInviteCode(circleID: circle.id, ownerID: peer.id) }
        await assertDenied { try await repository.updateCirclePhoto(circleID: circle.id, ownerID: peer.id, photoURL: nil) }
        await assertDenied { try await repository.forceCirclePrompt(circleID: circle.id, ownerID: peer.id, now: .now) }
        await assertDenied { try await repository.removeCircleMember(circleID: circle.id, ownerID: peer.id, memberID: other.id) }
    }

    func testFlagNeverGrantsOutsiderOrOwnershipAuthority() async throws {
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let peer = try XCTUnwrap(circle.members.first { $0.id != circle.ownerID })
        _ = try await repository.setCircleMemberChanges(circleID: circle.id, ownerID: circle.ownerID, allowed: true)
        await assertDenied(.notCircleOwner) { try await repository.setCircleMemberChanges(circleID: circle.id, ownerID: peer.id, allowed: false) }
        await assertDenied(.notCircleOwner) { try await repository.transferCircleOwnership(circleID: circle.id, ownerID: peer.id, newOwnerID: peer.id) }
        let outsider = UUID()
        await assertDenied { try await Self.saveSettings(repository, circle: circle, actor: outsider, name: "Outsider") }
        await assertDenied { try await repository.regenerateInviteCode(circleID: circle.id, ownerID: outsider) }
        do {
            _ = try await repository.removeCircleMember(circleID: circle.id, ownerID: peer.id, memberID: circle.ownerID)
            XCTFail("Shared changes cannot remove the leader")
        } catch { XCTAssertEqual(error as? BlessingError, .invalidMemberRemoval) }
        do {
            _ = try await repository.removeCircleMember(circleID: circle.id, ownerID: peer.id, memberID: peer.id)
            XCTFail("Leaving requires the separate leave flow")
        } catch { XCTAssertEqual(error as? BlessingError, .invalidMemberRemoval) }
    }

    func testTransferMovesPermissionSwitchAuthorityToNewLeader() async throws {
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let circle = try XCTUnwrap(bootstrap.circle)
        let peer = try XCTUnwrap(circle.members.first { $0.id != circle.ownerID })
        _ = try await repository.setCircleMemberChanges(circleID: circle.id, ownerID: circle.ownerID, allowed: true)
        let transferred = try await repository.transferCircleOwnership(circleID: circle.id, ownerID: circle.ownerID, newOwnerID: peer.id)
        XCTAssertTrue(transferred.allowMemberCircleChanges)
        await assertDenied(.notCircleOwner) { try await repository.setCircleMemberChanges(circleID: circle.id, ownerID: circle.ownerID, allowed: false) }
        let disabled = try await repository.setCircleMemberChanges(circleID: circle.id, ownerID: peer.id, allowed: false)
        XCTAssertFalse(disabled.allowMemberCircleChanges)
    }

    @MainActor
    func testAppModelRejectsMemberPolicyAndTransferButAllowsGeneralChanges() async throws {
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let original = try XCTUnwrap(bootstrap.circle)
        let peer = try XCTUnwrap(original.members.first { $0.id != original.ownerID })
        let shared = try await repository.setCircleMemberChanges(circleID: original.id, ownerID: original.ownerID, allowed: true)
        let model = AppModel(repository: repository)
        model.currentUser = peer
        model.circle = shared
        model.circles = [shared]
        let policyResult = await model.setCircleMemberChanges(false)
        XCTAssertFalse(policyResult)
        let transferResult = await model.transferCurrentCircleOwnership(to: peer.id)
        XCTAssertFalse(transferResult)
        let photoResult = await model.updateCirclePhoto(nil)
        XCTAssertTrue(photoResult)
        XCTAssertEqual(model.circle?.ownerID, original.ownerID)
        XCTAssertEqual(model.circle?.allowMemberCircleChanges, true)
        model.isSwitchingCircle = true
        let switchingResult = await model.regenerateCurrentCircleInviteCode()
        XCTAssertFalse(switchingResult)
    }

    @MainActor
    func testAppModelStaleSharedFlagCannotBypassFreshRepositoryRevocation() async throws {
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let original = try XCTUnwrap(bootstrap.circle)
        let peer = try XCTUnwrap(original.members.first { $0.id != original.ownerID })
        let stale = try await repository.setCircleMemberChanges(circleID: original.id, ownerID: original.ownerID, allowed: true)
        _ = try await repository.setCircleMemberChanges(circleID: original.id, ownerID: original.ownerID, allowed: false)
        let model = AppModel(repository: repository)
        model.currentUser = peer
        model.circle = stale
        model.circles = [stale]
        let result = await model.updateCirclePhoto(URL(fileURLWithPath: "/tmp/not-authorized.jpg"))
        XCTAssertFalse(result)
        XCTAssertNil(model.circle?.photoURL)
        let authoritative = try await repository.circleContext(circleID: original.id)
        XCTAssertFalse(authoritative.circle.allowMemberCircleChanges)
        XCTAssertNil(authoritative.circle.photoURL)
    }

    private static func saveSettings(_ repository: LocalBlessingRepository, circle: CircleGroup, actor: UUID, name: String) async throws -> CircleGroup {
        try await repository.updateCircleSettings(circleID: circle.id, ownerID: actor, name: name,
            timeZoneIdentifier: circle.timeZoneIdentifier, randomWindowStartMinutes: circle.randomWindowStartMinutes,
            randomWindowEndMinutes: circle.randomWindowEndMinutes, responseWindowMinutes: circle.responseWindowMinutes,
            allowsLateBlessings: circle.allowsLateBlessings, repeatWindowMinutes: circle.repeatWindowMinutes,
            endOfDayMinutes: circle.endOfDayMinutes)
    }

    private func assertDenied<T: Sendable>(_ expected: BlessingError = .circleChangesNotAllowed, _ operation: @Sendable () async throws -> T) async {
        do { _ = try await operation(); XCTFail("Expected settings authorization failure") }
        catch { XCTAssertEqual(error as? BlessingError, expected) }
    }
}
