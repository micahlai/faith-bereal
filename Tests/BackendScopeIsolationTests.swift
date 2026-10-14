import XCTest
@testable import BlessingCircle

/// Delayed responses deliberately ignore cancellation, as a completed network request may.
/// Each test changes scope while the response is suspended and then restores the original IDs.
final class BackendScopeIsolationTests: XCTestCase {
    @MainActor
    func testTimelineRefreshRejectsAccountABA() async throws {
        try await assertStaleRefreshRejected(change: .account, context: false)
    }

    @MainActor
    func testTimelineRefreshRejectsCircleABA() async throws {
        try await assertStaleRefreshRejected(change: .circle, context: false)
    }

    @MainActor
    func testTimelineRefreshRejectsTimeZoneABA() async throws {
        try await assertStaleRefreshRejected(change: .timeZone, context: false)
    }

    @MainActor
    func testCurrentCircleRefreshRejectsAccountABA() async throws {
        try await assertStaleRefreshRejected(change: .account, context: true)
    }

    @MainActor
    func testCurrentCircleRefreshRejectsCircleABA() async throws {
        try await assertStaleRefreshRejected(change: .circle, context: true)
    }

    @MainActor
    func testCurrentCircleRefreshRejectsTimeZoneABA() async throws {
        try await assertStaleRefreshRejected(change: .timeZone, context: true)
    }

    @MainActor
    func testCurrentCircleRefreshRejectsErrorFromPreviousAccountScope() async throws {
        let fixture = try await ScopeFixture()
        defer { fixture.removeFiles() }
        await fixture.repository.failNextContext()
        await fixture.repository.gate.arm(.context)
        let work = Task { await fixture.model.refreshCurrentCircle(now: fixture.now) }
        await fixture.repository.gate.waitUntilSuspended()
        try ScopeChange.account.leaveAndReturn(fixture.model)
        fixture.model.message = "Current account message"
        await fixture.repository.gate.release()
        await work.value
        XCTAssertEqual(fixture.model.message, "Current account message")
    }

    @MainActor
    func testLoadMoreRejectsAccountCircleAndTimeZoneABA() async throws {
        for change in [ScopeChange.account, .circle, .timeZone] {
            let fixture = try await ScopeFixture()
            defer { fixture.removeFiles() }
            let user = try XCTUnwrap(fixture.model.currentUser)
            let cursor = fixture.now.addingTimeInterval(-14 * 86_400)
            let originalLanes = [TimelineLane(member: user, events: [])]
            await fixture.repository.stubNextPage(TimelinePage(lanes: originalLanes, nextBeforeDate: cursor))
            try await fixture.model.refreshTimeline(now: fixture.now)
            var staleMember = user
            staleMember.displayName = "Stale older page"
            await fixture.repository.stubNextPage(TimelinePage(
                lanes: [TimelineLane(member: staleMember, events: [])], nextBeforeDate: nil))
            await fixture.repository.gate.arm(.page)
            let work = Task { await fixture.model.loadMoreTimeline() }
            await fixture.repository.gate.waitUntilSuspended()
            XCTAssertTrue(fixture.model.isLoadingMoreTimeline)
            try change.leaveAndReturn(fixture.model)
            await fixture.repository.gate.release()
            await work.value
            XCTAssertEqual(fixture.model.lanes, originalLanes)
            XCTAssertEqual(fixture.model.timelineNextBeforeDate, cursor)
            XCTAssertFalse(fixture.model.isLoadingMoreTimeline)
            XCTAssertNil(fixture.model.timelineLoadError)
        }
    }

    @MainActor
    func testCancelledCircleSwitchRestartsOriginalRealtimeSubscription() async throws {
        let fixture = try await ScopeFixture()
        defer { fixture.removeFiles() }
        let originalID = try XCTUnwrap(fixture.model.circle?.id)
        let target = try XCTUnwrap(fixture.model.circles.first { $0.id != originalID })
        await fixture.repository.gate.arm(.page)
        let work = Task { await fixture.model.switchCircle(to: target.id) }
        await fixture.repository.gate.waitUntilSuspended()
        work.cancel()
        await fixture.repository.gate.release()
        await work.value
        // The stream reports its subscription and immediately finishes; no test task leaks.
        let subscribed = await fixture.repository.waitForRealtimeSubscription()
        XCTAssertEqual(subscribed, originalID)
        XCTAssertEqual(fixture.model.circle?.id, originalID)
        XCTAssertFalse(fixture.model.isSwitchingCircle)
        XCTAssertNil(fixture.model.message)
    }

    @MainActor
    private func assertStaleRefreshRejected(change: ScopeChange, context: Bool) async throws {
        let fixture = try await ScopeFixture()
        defer { fixture.removeFiles() }
        await fixture.repository.gate.arm(context ? .context : .page)
        let work = Task {
            if context { await fixture.model.refreshCurrentCircle(now: fixture.now) }
            else { try await fixture.model.refreshTimeline(now: fixture.now) }
        }
        await fixture.repository.gate.waitUntilSuspended()
        try change.leaveAndReturn(fixture.model)
        fixture.model.circle?.name = "Current scope metadata"
        fixture.model.lanes = []
        await fixture.repository.gate.release()
        try await work.value
        XCTAssertTrue(fixture.model.lanes.isEmpty, "An old response must not replace the current scope's content")
        XCTAssertEqual(fixture.model.circle?.name, "Current scope metadata")
        XCTAssertNil(fixture.model.timelineNextBeforeDate)
    }
}

private enum ScopeChange {
    case account, circle, timeZone

    @MainActor
    func leaveAndReturn(_ model: AppModel) throws {
        switch self {
        case .account:
            let original = try XCTUnwrap(model.currentUser)
            model.currentUser = Member(id: UUID(), displayName: "Other account", initials: "OA", tintSeed: 0)
            model.currentUser = original
        case .circle:
            let original = try XCTUnwrap(model.circle)
            model.circle = try XCTUnwrap(model.circles.first { $0.id != original.id })
            model.circle = original
        case .timeZone:
            let original = try XCTUnwrap(model.circle)
            model.circle?.timeZoneIdentifier = original.timeZoneIdentifier == "UTC" ? "Asia/Tokyo" : "UTC"
            model.circle = original
        }
    }
}

@MainActor
private struct ScopeFixture {
    let now = Date()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackendScope-\(UUID())")
    let repository: ScopeRepository
    let model: AppModel

    init() async throws {
        repository = ScopeRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        model = AppModel(repository: repository,
            savedBlessingStore: SavedBlessingStore(root: root.appendingPathComponent("saved")),
            draftStore: BlessingDraftStore(root: root.appendingPathComponent("drafts")))
        model.currentUser = bootstrap.currentUser
        model.circles = bootstrap.circles
        model.circle = try XCTUnwrap(bootstrap.circles.first)
        let page = try await repository.timelinePage(circleID: model.circle!.id,
            viewerID: bootstrap.currentUser.id, now: now, before: nil)
        XCTAssertFalse(page.lanes.isEmpty, "The delayed response must contain content to detect a stale installation")
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

private actor ScopeGate {
    enum Operation { case page, context }
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
private actor ScopeRepository: BlessingRepository {
    let gate = ScopeGate()
    private let base: LocalBlessingRepository
    private var nextPage: TimelinePage?
    private var shouldFailContext = false
    private var subscribedCircleID: UUID?
    private var subscriptionObservers: [CheckedContinuation<UUID, Never>] = []

    init(now: Date) { base = LocalBlessingRepository(now: now) }

    func failNextContext() { shouldFailContext = true }

    func circleContext(circleID: UUID) async throws -> CircleContext {
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
        return try await base.bootstrap()
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
        return try await base.repeatBlessing(sourceBlessingID: sourceBlessingID, targetPromptID: targetPromptID, authorID: authorID, now: now)
    }

    func leaveCircle(circleID: UUID, memberID: UUID) async throws {
        try await base.leaveCircle(circleID: circleID, memberID: memberID)
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
