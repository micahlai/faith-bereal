import XCTest
@testable import BlessingCircle

@MainActor
final class BiblePreferenceRaceTests: XCTestCase {
    func testDelayedUpdateCannotRestoreSignedOutIdentity() async throws {
        let fixture = try await BiblePreferenceFixture()
        defer { fixture.removeFiles() }
        let work = Task { await fixture.model.updateBibleVersion("bsb") }
        await fixture.repository.waitForUpdate("bsb")
        await fixture.model.signOut()
        XCTAssertNil(fixture.model.currentUser)
        await fixture.repository.release("bsb")
        await work.value
        XCTAssertNil(fixture.model.currentUser)
        XCTAssertEqual(fixture.model.loadState, .signedOut)
        XCTAssertNil(fixture.model.message)
    }

    func testDelayedUpdateCannotOverwriteAnotherAccountOrReturnedAccount() async throws {
        let fixture = try await BiblePreferenceFixture()
        defer { fixture.removeFiles() }
        let original = try XCTUnwrap(fixture.model.currentUser)
        let work = Task { await fixture.model.updateBibleVersion("bsb") }
        await fixture.repository.waitForUpdate("bsb")
        let other = Member(id: UUID(), displayName: "Other account", initials: "OT", tintSeed: 2, bibleVersionID: "asv")
        fixture.model.currentUser = other
        fixture.model.currentUser = original
        await fixture.repository.release("bsb")
        await work.value
        XCTAssertEqual(fixture.model.currentUser, original, "Returning to the same ID must not revive a prior scope's response")
        XCTAssertNil(fixture.model.message)
    }

    func testAcceptedDeletionDiscardsAlreadyInFlightPreference() async throws {
        let fixture = try await BiblePreferenceFixture()
        defer { fixture.removeFiles() }
        let before = try XCTUnwrap(fixture.model.currentUser)
        let work = Task { await fixture.model.updateBibleVersion("bsb") }
        await fixture.repository.waitForUpdate("bsb")
        await fixture.model.requestAccountDeletion(appleCode: "synthetic-only")
        XCTAssertTrue(fixture.model.accountDeletionPending)
        await fixture.repository.release("bsb")
        await work.value
        XCTAssertEqual(fixture.model.currentUser, before)
        XCTAssertTrue(fixture.model.circles.isEmpty)
        XCTAssertNil(fixture.model.message)
    }

    func testNewerChoiceWinsWhenOlderResponseArrivesLast() async throws {
        let fixture = try await BiblePreferenceFixture()
        defer { fixture.removeFiles() }
        let older = Task { await fixture.model.updateBibleVersion("bsb") }
        await fixture.repository.waitForUpdate("bsb")
        let newer = Task { await fixture.model.updateBibleVersion("asv") }
        await fixture.repository.waitForUpdate("asv")
        await fixture.repository.release("asv")
        await newer.value
        XCTAssertEqual(fixture.model.selectedBibleTranslation.id, "asv")
        await fixture.repository.release("bsb")
        await older.value
        XCTAssertEqual(fixture.model.selectedBibleTranslation.id, "asv")
        XCTAssertNil(fixture.model.message)
    }

    func testStaleFailureCannotReplaceNewerSuccessfulChoiceWithAnAlert() async throws {
        let fixture = try await BiblePreferenceFixture(failing: ["bsb"])
        defer { fixture.removeFiles() }
        let older = Task { await fixture.model.updateBibleVersion("bsb") }
        await fixture.repository.waitForUpdate("bsb")
        let newer = Task { await fixture.model.updateBibleVersion("asv") }
        await fixture.repository.waitForUpdate("asv")
        await fixture.repository.release("asv")
        await newer.value
        await fixture.repository.release("bsb")
        await older.value
        XCTAssertEqual(fixture.model.selectedBibleTranslation.id, "asv")
        XCTAssertNil(fixture.model.message)
    }

    func testCurrentFailureStillExplainsFailureAndPreservesSelection() async throws {
        let fixture = try await BiblePreferenceFixture(failing: ["bsb"])
        defer { fixture.removeFiles() }
        let work = Task { await fixture.model.updateBibleVersion("bsb") }
        await fixture.repository.waitForUpdate("bsb")
        await fixture.repository.release("bsb")
        await work.value
        XCTAssertEqual(fixture.model.selectedBibleTranslation.id, "web")
        XCTAssertNotNil(fixture.model.message)
    }
}

@MainActor
private struct BiblePreferenceFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("BiblePreference-\(UUID())")
    let repository: BiblePreferenceRepository
    let model: AppModel

    init(failing: Set<String> = []) async throws {
        repository = BiblePreferenceRepository(failing: failing)
        let seed = try await repository.bootstrap()
        let suite = "BiblePreference-\(UUID())"
        model = AppModel(repository: repository, authentication: BiblePreferenceAuthentication(),
            savedBlessingStore: SavedBlessingStore(root: root.appendingPathComponent("saved")),
            draftStore: BlessingDraftStore(root: root.appendingPathComponent("drafts")),
            accountSafety: LocalAccountSafetyService(), deletionPreferences: UserDefaults(suiteName: suite)!,
            diagnosticCollection: DiagnosticCollectionController(store: BackendDiagnosticStore(root: root.appendingPathComponent("diagnostics"))),
            metadataStore: CircleMetadataStore(directory: root.appendingPathComponent("metadata")),
            identityPhotoCache: IdentityPhotoCache(directory: root.appendingPathComponent("photos"), fetch: { _ in nil }),
            registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
        model.currentUser = seed.currentUser
        model.circles = seed.circles
        model.circle = seed.circle
        model.prompt = seed.prompt
        model.loadState = .ready
    }

    func removeFiles() {
        model.diagnosticCollection.deactivate()
        try? FileManager.default.removeItem(at: root)
    }
}

private actor BiblePreferenceAuthentication: AuthenticationProviding {
    func hasSession() async -> Bool { true }
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws {}
    func signOut() async throws {}
}

/// Normal local behavior with delayed preference-response delivery. The underlying
/// write finishes first, so releasing continuations out of order models the wire.
private actor BiblePreferenceRepository: BlessingRepository {
    private let base = LocalBlessingRepository()
    private let failing: Set<String>
    private var pending: [String: CheckedContinuation<Void, Never>] = [:]
    private var observers: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var requested: [String] = []
    init(failing: Set<String>) { self.failing = failing }
    func requestedVersions() -> [String] { requested }
    func waitForUpdate(_ version: String) async {
        if pending[version] != nil { return }
        await withCheckedContinuation { observers[version, default: []].append($0) }
    }
    func release(_ version: String) { pending.removeValue(forKey: version)?.resume() }
    func updateBibleVersion(memberID: UUID, versionID: String) async throws -> Member {
        let result = try await base.updateBibleVersion(memberID: memberID, versionID: versionID)
        requested.append(versionID)
        await withCheckedContinuation { continuation in
            pending[versionID] = continuation
            observers.removeValue(forKey: versionID)?.forEach { $0.resume() }
        }
        if failing.contains(versionID) { throw URLError(.notConnectedToInternet) }
        return result
    }
    func bootstrap() async throws -> AppBootstrap {
        return try await base.bootstrap()
    }
    func circleContext(circleID: UUID) async throws -> CircleContext {
        return try await base.circleContext(circleID: circleID)
    }
    func circleContext(promptID: UUID) async throws -> CircleContext {
        return try await base.circleContext(promptID: promptID)
    }
    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane] {
        return try await base.timeline(circleID: circleID, viewerID: viewerID, now: now)
    }
    func timeline(circle: CircleGroup, viewerID: UUID, now: Date) async throws -> [TimelineLane] {
        return try await base.timeline(circle: circle, viewerID: viewerID, now: now)
    }
    func timelinePage(circleID: UUID, viewerID: UUID, now: Date, before: Date?) async throws -> TimelinePage {
        return try await base.timelinePage(circleID: circleID, viewerID: viewerID, now: now, before: before)
    }
    func timelinePage(circle: CircleGroup, viewerID: UUID, now: Date, before: Date?) async throws -> TimelinePage {
        return try await base.timelinePage(circle: circle, viewerID: viewerID, now: now, before: before)
    }
    func retentionPage(circle: CircleGroup, viewerID: UUID, now: Date, afterID: UUID?) async throws -> RetentionPage {
        return try await base.retentionPage(circle: circle, viewerID: viewerID, now: now, afterID: afterID)
    }
    func blessing(id: UUID, viewerID: UUID) async throws -> Blessing? {
        return try await base.blessing(id: id, viewerID: viewerID)
    }
    func beginBlessingEntry(promptID: UUID, memberID: UUID, now: Date) async throws {
        try await base.beginBlessingEntry(promptID: promptID, memberID: memberID, now: now)
    }
    func submit(promptID: UUID, authorID: UUID, mode: CaptureMode, body: String?, audioURL: URL?, videoURL: URL?, photoURL: URL?, scriptureReference: ScriptureReference?, now: Date) async throws -> Blessing {
        return try await base.submit(promptID: promptID, authorID: authorID, mode: mode, body: body, audioURL: audioURL, videoURL: videoURL, photoURL: photoURL, scriptureReference: scriptureReference, now: now)
    }
    func updateBlessing(blessingID: UUID, authorID: UUID, body: String, scriptureReference: ScriptureReference?, now: Date) async throws -> Blessing {
        return try await base.updateBlessing(blessingID: blessingID, authorID: authorID, body: body, scriptureReference: scriptureReference, now: now)
    }
    func joinCircle(code: String, memberID: UUID) async throws -> CircleGroup {
        return try await base.joinCircle(code: code, memberID: memberID)
    }
    func createCircle(configuration: CircleConfiguration, member: Member) async throws -> CircleGroup {
        return try await base.createCircle(configuration: configuration, member: member)
    }
    func setCircleMemberChanges(circleID: UUID, ownerID: UUID, allowed: Bool) async throws -> CircleGroup {
        return try await base.setCircleMemberChanges(circleID: circleID, ownerID: ownerID, allowed: allowed)
    }
    func regenerateInviteCode(circleID: UUID, ownerID: UUID) async throws -> CircleGroup {
        return try await base.regenerateInviteCode(circleID: circleID, ownerID: ownerID)
    }
    func updateCircleSettings(circleID: UUID, ownerID: UUID, name: String, timeZoneIdentifier: String, randomWindowStartMinutes: Int, randomWindowEndMinutes: Int, responseWindowMinutes: Int, allowsLateBlessings: Bool, repeatWindowMinutes: Int, endOfDayMinutes: Int) async throws -> CircleGroup {
        return try await base.updateCircleSettings(circleID: circleID, ownerID: ownerID, name: name, timeZoneIdentifier: timeZoneIdentifier, randomWindowStartMinutes: randomWindowStartMinutes, randomWindowEndMinutes: randomWindowEndMinutes, responseWindowMinutes: responseWindowMinutes, allowsLateBlessings: allowsLateBlessings, repeatWindowMinutes: repeatWindowMinutes, endOfDayMinutes: endOfDayMinutes)
    }
    func updateCirclePhoto(circleID: UUID, ownerID: UUID, photoURL: URL?) async throws -> CircleGroup {
        return try await base.updateCirclePhoto(circleID: circleID, ownerID: ownerID, photoURL: photoURL)
    }
    func updateCircleActivityNotifications(circleID: UUID, memberID: UUID, enabled: Bool) async throws {
        try await base.updateCircleActivityNotifications(circleID: circleID, memberID: memberID, enabled: enabled)
    }
    func updateEndOfDayNotifications(circleID: UUID, memberID: UUID, enabled: Bool) async throws {
        try await base.updateEndOfDayNotifications(circleID: circleID, memberID: memberID, enabled: enabled)
    }
    func forceCirclePrompt(circleID: UUID, ownerID: UUID, now: Date) async throws -> CirclePromptDispatch {
        return try await base.forceCirclePrompt(circleID: circleID, ownerID: ownerID, now: now)
    }
    func updateProfile(memberID: UUID, displayName: String, avatarURL: URL?) async throws -> Member {
        return try await base.updateProfile(memberID: memberID, displayName: displayName, avatarURL: avatarURL)
    }
    func transferCircleOwnership(circleID: UUID, ownerID: UUID, newOwnerID: UUID) async throws -> CircleGroup {
        return try await base.transferCircleOwnership(circleID: circleID, ownerID: ownerID, newOwnerID: newOwnerID)
    }
    func removeCircleMember(circleID: UUID, ownerID: UUID, memberID: UUID) async throws -> CircleGroup {
        return try await base.removeCircleMember(circleID: circleID, ownerID: ownerID, memberID: memberID)
    }
    func recentBlessings(authorID: UUID, submittedAfter: Date) async throws -> [Blessing] {
        return try await base.recentBlessings(authorID: authorID, submittedAfter: submittedAfter)
    }
    func repeatBlessing(sourceBlessingID: UUID, targetPromptID: UUID, authorID: UUID, now: Date) async throws -> Blessing {
        return try await base.repeatBlessing(sourceBlessingID: sourceBlessingID, targetPromptID: targetPromptID, authorID: authorID, now: now)
    }
    func leaveCircle(circleID: UUID, memberID: UUID) async throws {
        try await base.leaveCircle(circleID: circleID, memberID: memberID)
    }
    func nudgeMember(promptID: UUID, recipientID: UUID, senderID: UUID, now: Date) async throws -> Bool {
        return try await base.nudgeMember(promptID: promptID, recipientID: recipientID, senderID: senderID, now: now)
    }
    func timelineResponderSummaries(blessingIDs: [UUID], viewerID: UUID) async throws -> [TimelineResponderSummary] {
        return try await base.timelineResponderSummaries(blessingIDs: blessingIDs, viewerID: viewerID)
    }
    func responses(blessingID: UUID, viewerID: UUID) async throws -> [BlessingResponse] {
        return try await base.responses(blessingID: blessingID, viewerID: viewerID)
    }
    func submitResponse(blessingID: UUID, circleID: UUID, authorID: UUID, mode: ResponseMode, body: String, audioURL: URL?, now: Date) async throws -> BlessingResponse {
        return try await base.submitResponse(blessingID: blessingID, circleID: circleID, authorID: authorID, mode: mode, body: body, audioURL: audioURL, now: now)
    }
    func timelineUpdates(circleID: UUID) async throws -> AsyncStream<Void> {
        return try await base.timelineUpdates(circleID: circleID)
    }
    func registerDevice(installationID: UUID, apnsToken: String?, pushToStartToken: String?, environment: String) async throws {
        try await base.registerDevice(installationID: installationID, apnsToken: apnsToken, pushToStartToken: pushToStartToken, environment: environment)
    }
    func registerActivity(promptID: UUID, activityID: String, pushToken: String, environment: String) async throws {
        try await base.registerActivity(promptID: promptID, activityID: activityID, pushToken: pushToken, environment: environment)
    }
}
