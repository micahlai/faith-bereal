import XCTest
@testable import BlessingCircle

final class CachedCircleLoadingTests: XCTestCase {
    @MainActor
    func testCachedStartupShowsIdentityBeforeBootstrapAndCannotAuthorizeCaptureOrSettings() async throws {
        let fixture = try await CachedLoadingFixture()
        defer { fixture.removeFiles() }
        await fixture.repository.gate.arm(.bootstrap)
        let work = Task { await fixture.model.bootstrap() }
        await fixture.repository.gate.waitUntilSuspended()

        XCTAssertEqual(fixture.model.loadState, .ready)
        XCTAssertTrue(fixture.model.isPageLoading)
        XCTAssertTrue(fixture.model.isShowingCachedMetadata)
        XCTAssertFalse(fixture.model.canUseFreshCircle)
        XCTAssertEqual(fixture.model.circle?.name, "Cached identity")
        XCTAssertEqual(fixture.model.currentUser?.displayName, "Cached person")
        XCTAssertNil(fixture.model.prompt)
        XCTAssertNil(fixture.model.endOfDayPrompt)
        XCTAssertTrue(fixture.model.lanes.isEmpty)
        XCTAssertFalse(fixture.model.canEnterCurrentPrompt(at: fixture.now))
        XCTAssertFalse(fixture.model.canEnterEndOfDayPrompt(at: fixture.now))
        // An explicit prompt argument must not bypass the cached-only state.
        let opened = await fixture.model.openCapture(for: fixture.seed.prompt, now: fixture.now)
        let rotated = await fixture.model.regenerateCurrentCircleInviteCode()
        let shared = await fixture.model.setCircleMemberChanges(true)
        let saved = await fixture.model.updateCircleSettings(name: "Forbidden cached edit", timeZoneIdentifier: "UTC",
            randomWindowStartMinutes: 720, randomWindowEndMinutes: 1_200, responseWindowMinutes: 10,
            allowsLateBlessings: true, repeatWindowMinutes: 120, endOfDayMinutes: 1_320)
        XCTAssertFalse(opened)
        XCTAssertFalse(rotated)
        XCTAssertFalse(shared)
        XCTAssertFalse(saved)
        XCTAssertFalse(fixture.model.isCapturePresented)
        let calls = await fixture.repository.counts()
        XCTAssertEqual(calls.mutations, 0, "Cached owner/member metadata never authorizes a repository mutation")

        await fixture.repository.gate.release()
        await work.value
    }

    @MainActor
    func testPendingStartupContentCannotAuthorizeSubmitAfterFreshMetadataArrives() async throws {
        let fixture = try await CachedLoadingFixture()
        defer { fixture.removeFiles() }
        await fixture.repository.gate.arm(.page)
        let work = Task { await fixture.model.bootstrap() }
        await fixture.repository.gate.waitUntilSuspended()
        XCTAssertTrue(fixture.model.isPageLoading)
        XCTAssertTrue(fixture.model.isShowingCachedMetadata)
        XCTAssertFalse(fixture.model.canUseFreshCircle)
        XCTAssertTrue(fixture.model.lanes.isEmpty)
        XCTAssertFalse(fixture.model.canEnterCurrentPrompt(at: fixture.now))
        let opened = await fixture.model.openCapture(for: fixture.seed.prompt, now: fixture.now)
        let submitted = await fixture.model.submit(mode: .typed, body: "Must not send while loading",
            audioURL: nil, videoURL: nil, scriptureReference: nil)
        let source = Blessing(id: UUID(), circleID: UUID(), promptID: UUID(),
            authorID: fixture.seed.currentUser.id, captureMode: .typed, body: "Synthetic reuse",
            audioURL: nil, videoURL: nil, submittedAt: fixture.now, isLate: false, scriptureReference: nil)
        let repeated = await fixture.model.repeatBlessing(source, now: fixture.now)
        XCTAssertFalse(opened)
        XCTAssertFalse(submitted)
        XCTAssertFalse(repeated)
        let calls = await fixture.repository.counts()
        XCTAssertEqual(calls.mutations, 0)
        await fixture.repository.gate.release()
        await work.value
    }

    @MainActor
    func testFreshStartupReplacesCachedIdentityAndPersistsNewMetadata() async throws {
        let fixture = try await CachedLoadingFixture()
        defer { fixture.removeFiles() }
        await fixture.repository.gate.arm(.bootstrap)
        let work = Task { await fixture.model.bootstrap() }
        await fixture.repository.gate.waitUntilSuspended()
        XCTAssertEqual(fixture.model.circle?.name, "Cached identity")
        await fixture.repository.gate.release()
        await work.value

        XCTAssertEqual(fixture.model.loadState, .ready)
        XCTAssertFalse(fixture.model.isPageLoading)
        XCTAssertFalse(fixture.model.isShowingCachedMetadata)
        XCTAssertTrue(fixture.model.canUseFreshCircle)
        XCTAssertEqual(fixture.model.circle?.name, fixture.seed.circle?.name)
        XCTAssertEqual(fixture.model.currentUser, fixture.seed.currentUser)
        XCTAssertNotNil(fixture.model.prompt)
        XCTAssertFalse(fixture.model.lanes.isEmpty)
        let loaded = await fixture.metadata.load(accountID: fixture.seed.currentUser.id)
        let cached = try XCTUnwrap(loaded)
        XCTAssertEqual(cached.currentUser, fixture.seed.currentUser)
        XCTAssertEqual(cached.selectedCircleID, fixture.model.circle?.id)
        XCTAssertEqual(cached.circles.first?.name, fixture.seed.circles.first?.name)
        XCTAssertTrue(cached.circles.allSatisfy { $0.inviteCode.isEmpty && !$0.allowMemberCircleChanges })
    }

    @MainActor
    func testCircleSwitchShowsDestinationImmediatelyAndKeepsContentEmptyUntilFreshPage() async throws {
        let fixture = try await CachedLoadingFixture()
        defer { fixture.removeFiles() }
        try await fixture.installFreshPresentation()
        let target = try XCTUnwrap(fixture.seed.circles.first { $0.id != fixture.model.circle?.id })
        await fixture.repository.gate.arm(.context)
        let work = Task { await fixture.model.switchCircle(to: target.id) }
        await fixture.repository.gate.waitUntilSuspended()
        assertSwitchLoading(fixture.model, target: target)
        await fixture.repository.gate.arm(.page)
        await fixture.repository.gate.release()
        await fixture.repository.gate.waitUntilSuspended()
        assertSwitchLoading(fixture.model, target: target)
        await fixture.repository.gate.release()
        await work.value
        XCTAssertEqual(fixture.model.circle?.id, target.id)
        XCTAssertFalse(fixture.model.isSwitchingCircle)
        XCTAssertFalse(fixture.model.isShowingCachedMetadata)
        XCTAssertFalse(fixture.model.isPageLoading)
        XCTAssertNil(fixture.model.pageLoadError)
        XCTAssertFalse(fixture.model.lanes.isEmpty)
    }

    @MainActor
    func testFailedSwitchRestoresOriginalAuthorizedContentAndShowsPageError() async throws {
        let fixture = try await CachedLoadingFixture()
        defer { fixture.removeFiles() }
        try await fixture.installFreshPresentation()
        let previous = fixture.model.circle
        let prompt = fixture.model.prompt
        let evening = fixture.model.endOfDayPrompt
        let lanes = fixture.model.lanes
        let target = try XCTUnwrap(fixture.seed.circles.first { $0.id != previous?.id })
        await fixture.repository.failNextContext()
        await fixture.repository.gate.arm(.context)
        let work = Task { await fixture.model.switchCircle(to: target.id) }
        await fixture.repository.gate.waitUntilSuspended()
        assertSwitchLoading(fixture.model, target: target)
        await fixture.repository.gate.release()
        await work.value
        XCTAssertEqual(fixture.model.circle, previous)
        XCTAssertEqual(fixture.model.prompt, prompt)
        XCTAssertEqual(fixture.model.endOfDayPrompt, evening)
        XCTAssertEqual(fixture.model.lanes, lanes)
        XCTAssertFalse(fixture.model.isSwitchingCircle)
        XCTAssertFalse(fixture.model.isPageLoading)
        XCTAssertFalse(fixture.model.isShowingCachedMetadata)
        XCTAssertTrue(fixture.model.canUseFreshCircle)
        XCTAssertTrue(fixture.model.pageLoadError?.contains("Couldn’t switch circles") == true)
    }

    @MainActor
    func testDelayedPreferredCircleContextCannotRestoreMetadataAfterSignOut() async throws {
        let fixture = try await CachedLoadingFixture()
        defer { fixture.removeFiles() }
        let preferred = try XCTUnwrap(fixture.seed.circles.first { $0.id != fixture.seed.selectedCircleID })
        UserDefaults.standard.set(preferred.id.uuidString, forKey: "blessingCircle.selectedCircleID")
        await fixture.repository.gate.arm(.context)
        let work = Task { await fixture.model.bootstrap() }
        await fixture.repository.gate.waitUntilSuspended()
        XCTAssertEqual(fixture.model.circle?.id, preferred.id)
        await fixture.model.signOut()
        XCTAssertEqual(fixture.model.loadState, .signedOut)
        await fixture.repository.gate.release()
        await work.value
        XCTAssertEqual(fixture.model.loadState, .signedOut)
        XCTAssertNil(fixture.model.currentUser)
        XCTAssertNil(fixture.model.circle)
        XCTAssertNil(fixture.model.prompt)
        XCTAssertNil(fixture.model.endOfDayPrompt)
        XCTAssertTrue(fixture.model.circles.isEmpty)
        XCTAssertTrue(fixture.model.lanes.isEmpty)
        let cached = await fixture.metadata.load(accountID: fixture.seed.currentUser.id)
        XCTAssertNil(cached, "A stale startup must not recreate signed-out account metadata")
    }

    @MainActor
    func testDelayedLeaveCannotClearANewerAccountScopeOrRestoreItsCache() async throws {
        let fixture = try await CachedLoadingFixture()
        defer { fixture.removeFiles() }
        try await fixture.installFreshPresentation()
        await fixture.repository.gate.arm(.leave)
        let work = Task { await fixture.model.leaveCurrentCircle() }
        await fixture.repository.gate.waitUntilSuspended()
        await fixture.model.signOut()
        let signedOutMessage = fixture.model.message
        await fixture.repository.gate.release()
        let completed = await work.value
        XCTAssertFalse(completed, "A delayed leave belongs to the departed account scope")
        XCTAssertEqual(fixture.model.loadState, .signedOut)
        XCTAssertNil(fixture.model.currentUser)
        XCTAssertNil(fixture.model.circle)
        XCTAssertTrue(fixture.model.circles.isEmpty)
        XCTAssertTrue(fixture.model.lanes.isEmpty)
        XCTAssertEqual(fixture.model.message, signedOutMessage)
        let cached = await fixture.metadata.load(accountID: fixture.seed.currentUser.id)
        XCTAssertNil(cached)
    }

    @MainActor
    func testConcurrentRefreshRequestsCoalesceWhileContextIsPending() async throws {
        let fixture = try await CachedLoadingFixture()
        defer { fixture.removeFiles() }
        try await fixture.installFreshPresentation()
        let previous = fixture.model.lanes
        let before = await fixture.repository.counts()
        await fixture.repository.gate.arm(.context)
        let first = Task { await fixture.model.refreshCurrentCircle(now: fixture.now) }
        await fixture.repository.gate.waitUntilSuspended()
        XCTAssertTrue(fixture.model.isPageLoading)
        let second = Task { await fixture.model.refreshCurrentCircle(now: fixture.now) }
        await second.value
        let during = await fixture.repository.counts()
        XCTAssertEqual(during.context - before.context, 1)
        XCTAssertEqual(fixture.model.lanes, previous, "Refresh retains the currently authorized page")
        await fixture.repository.gate.release()
        await first.value
        XCTAssertFalse(fixture.model.isPageLoading)
        XCTAssertNil(fixture.model.pageLoadError)
    }

    @MainActor
    private func assertSwitchLoading(_ model: AppModel, target: CircleGroup, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.circle?.id, target.id, file: file, line: line)
        XCTAssertEqual(model.circle?.members, target.members, file: file, line: line)
        XCTAssertTrue(model.isSwitchingCircle, file: file, line: line)
        XCTAssertTrue(model.isPageLoading, file: file, line: line)
        XCTAssertTrue(model.isShowingCachedMetadata, file: file, line: line)
        XCTAssertFalse(model.canUseFreshCircle, file: file, line: line)
        XCTAssertNil(model.prompt, file: file, line: line)
        XCTAssertNil(model.endOfDayPrompt, file: file, line: line)
        XCTAssertTrue(model.lanes.isEmpty, file: file, line: line)
    }
}

@MainActor
private struct CachedLoadingFixture {
    let now = Date()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CachedLoading-\(UUID())")
    let repository: CachedLoadingRepository
    let metadata: CircleMetadataStore
    let seed: AppBootstrap
    let model: AppModel
    private let previousSelection: String?

    init() async throws {
        previousSelection = UserDefaults.standard.string(forKey: "blessingCircle.selectedCircleID")
        repository = CachedLoadingRepository(now: now)
        seed = try await repository.seedBootstrap()
        UserDefaults.standard.set(seed.selectedCircleID?.uuidString, forKey: "blessingCircle.selectedCircleID")
        metadata = CircleMetadataStore(directory: root.appendingPathComponent("metadata"))
        var cachedUser = seed.currentUser
        cachedUser.displayName = "Cached person"
        var cachedCircles = seed.circles
        for index in cachedCircles.indices { cachedCircles[index].name = "Cached identity" }
        await metadata.save(accountID: cachedUser.id, currentUser: cachedUser,
            circles: cachedCircles, selectedCircleID: seed.selectedCircleID)
        model = AppModel(repository: repository,
            authentication: CachedLoadingAuthentication(accountID: seed.currentUser.id),
            savedBlessingStore: SavedBlessingStore(root: root.appendingPathComponent("saved")),
            draftStore: BlessingDraftStore(root: root.appendingPathComponent("drafts")),
            diagnosticCollection: DiagnosticCollectionController(store: BackendDiagnosticStore(root: root.appendingPathComponent("diagnostics"))),
            metadataStore: metadata, registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
    }

    func installFreshPresentation() async throws {
        model.currentUser = seed.currentUser
        model.circles = seed.circles
        model.circle = try XCTUnwrap(seed.circle)
        model.prompt = seed.prompt
        model.endOfDayPrompt = seed.endOfDayPrompt
        model.loadState = .ready
        try await model.refreshTimeline(now: now, freshCircle: seed.circle)
        XCTAssertFalse(model.lanes.isEmpty)
    }

    func removeFiles() {
        model.diagnosticCollection.deactivate()
        UserDefaults.standard.set(previousSelection, forKey: "blessingCircle.selectedCircleID")
        try? FileManager.default.removeItem(at: root)
    }
}

private actor CachedLoadingAuthentication: AuthenticationProviding {
    let accountID: UUID
    init(accountID: UUID) { self.accountID = accountID }
    func cachedUserID() async -> UUID? { accountID }
    func currentUserID() async -> UUID? { accountID }
    func hasSession() async -> Bool { true }
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws { }
    func signOut() async throws { }
}
private actor CachedLoadingGate {
    enum Operation { case page, context, bootstrap, leave }
    private var armed: Operation?
    private var suspended: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    func arm(_ operation: Operation) { armed = operation }

    func pauseIfArmed(_ operation: Operation) async {
        guard armed == operation else { return }
        armed = nil
        await withCheckedContinuation { continuation in
            suspended = continuation
            observers.forEach { $0.resume() }
            observers = []
        }
    }

    func waitUntilSuspended() async {
        if suspended != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func release() {
        let continuation = suspended
        suspended = nil
        continuation?.resume()
    }
}

/// All domain behavior is forwarded to the local repository; only response delivery is delayed.
private actor CachedLoadingRepository: BlessingRepository {
    let gate = CachedLoadingGate()
    private let base: LocalBlessingRepository
    private var nextPage: TimelinePage?
    private var contextCalls = 0
    private var mutationCalls = 0
    private var shouldFailContext = false
    private var subscribedCircleID: UUID?
    private var subscriptionObservers: [CheckedContinuation<UUID, Never>] = []

    init(now: Date) { base = LocalBlessingRepository(now: now) }

    func counts() -> (context: Int, mutations: Int) { (contextCalls, mutationCalls) }
    func seedBootstrap() async throws -> AppBootstrap { try await base.bootstrap() }

    func failNextContext() { shouldFailContext = true }

    func circleContext(circleID: UUID) async throws -> CircleContext {
        contextCalls += 1
        let shouldFail = shouldFailContext
        shouldFailContext = false
        let result = try await base.circleContext(circleID: circleID)
        await gate.pauseIfArmed(.context)
        if shouldFail { throw URLError(.networkConnectionLost) }
        return result
    }

    func circleContext(promptID: UUID) async throws -> CircleContext {
        try await base.circleContext(promptID: promptID)
    }

    func stubNextPage(_ page: TimelinePage) { nextPage = page }

    func timelinePage(circleID: UUID, viewerID: UUID, now: Date, before: Date?) async throws -> TimelinePage {
        let result: TimelinePage
        if let nextPage {
            self.nextPage = nil
            result = nextPage
        } else {
            result = try await base.timelinePage(circleID: circleID, viewerID: viewerID, now: now, before: before)
        }
        await gate.pauseIfArmed(.page)
        return result
    }

    func timelinePage(circle: CircleGroup, viewerID: UUID, now: Date, before: Date?) async throws -> TimelinePage {
        try await timelinePage(circleID: circle.id, viewerID: viewerID, now: now, before: before)
    }

    func timelineUpdates(circleID: UUID) async throws -> AsyncStream<Void> {
        subscribedCircleID = circleID
        subscriptionObservers.forEach { $0.resume(returning: circleID) }
        subscriptionObservers = []
        return AsyncStream { $0.finish() }
    }

    func waitForRealtimeSubscription() async -> UUID {
        if let subscribedCircleID { return subscribedCircleID }
        return await withCheckedContinuation { subscriptionObservers.append($0) }
    }

    func bootstrap() async throws -> AppBootstrap {
        let result = try await base.bootstrap()
        await gate.pauseIfArmed(.bootstrap)
        return result
    }

    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane] {
        return try await base.timeline(circleID: circleID, viewerID: viewerID, now: now)
    }

    func timeline(circle: CircleGroup, viewerID: UUID, now: Date) async throws -> [TimelineLane] {
        return try await base.timeline(circle: circle, viewerID: viewerID, now: now)
    }

    func blessing(id: UUID, viewerID: UUID) async throws -> Blessing? {
        return try await base.blessing(id: id, viewerID: viewerID)
    }

    func beginBlessingEntry(promptID: UUID, memberID: UUID, now: Date) async throws {
        mutationCalls += 1
        try await base.beginBlessingEntry(promptID: promptID, memberID: memberID, now: now)
    }

    func submit(promptID: UUID, authorID: UUID, mode: CaptureMode, body: String?, audioURL: URL?, videoURL: URL?, photoURL: URL?, scriptureReference: ScriptureReference?, now: Date) async throws -> Blessing {
        mutationCalls += 1
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
        mutationCalls += 1
        return try await base.setCircleMemberChanges(circleID: circleID, ownerID: ownerID, allowed: allowed)
    }

    func regenerateInviteCode(circleID: UUID, ownerID: UUID) async throws -> CircleGroup {
        mutationCalls += 1
        return try await base.regenerateInviteCode(circleID: circleID, ownerID: ownerID)
    }

    func updateCircleSettings(circleID: UUID, ownerID: UUID, name: String, timeZoneIdentifier: String, randomWindowStartMinutes: Int, randomWindowEndMinutes: Int, responseWindowMinutes: Int, allowsLateBlessings: Bool, repeatWindowMinutes: Int, endOfDayMinutes: Int) async throws -> CircleGroup {
        mutationCalls += 1
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

    func updateBibleVersion(memberID: UUID, versionID: String) async throws -> Member {
        return try await base.updateBibleVersion(memberID: memberID, versionID: versionID)
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
        mutationCalls += 1
        return try await base.repeatBlessing(sourceBlessingID: sourceBlessingID, targetPromptID: targetPromptID, authorID: authorID, now: now)
    }

    func leaveCircle(circleID: UUID, memberID: UUID) async throws {
        try await base.leaveCircle(circleID: circleID, memberID: memberID)
        await gate.pauseIfArmed(.leave)
    }

    func nudgeMember(promptID: UUID, recipientID: UUID, senderID: UUID, now: Date) async throws -> Bool {
        return try await base.nudgeMember(promptID: promptID, recipientID: recipientID, senderID: senderID, now: now)
    }

    func responses(blessingID: UUID, viewerID: UUID) async throws -> [BlessingResponse] {
        return try await base.responses(blessingID: blessingID, viewerID: viewerID)
    }

    func submitResponse(blessingID: UUID, circleID: UUID, authorID: UUID, mode: ResponseMode, body: String, audioURL: URL?, now: Date) async throws -> BlessingResponse {
        return try await base.submitResponse(blessingID: blessingID, circleID: circleID, authorID: authorID, mode: mode, body: body, audioURL: audioURL, now: now)
    }

    func registerDevice(installationID: UUID, apnsToken: String?, pushToStartToken: String?, environment: String) async throws {
        try await base.registerDevice(installationID: installationID, apnsToken: apnsToken, pushToStartToken: pushToStartToken, environment: environment)
    }

    func registerActivity(promptID: UUID, activityID: String, pushToken: String, environment: String) async throws {
        try await base.registerActivity(promptID: promptID, activityID: activityID, pushToken: pushToken, environment: environment)
    }
}
