import Foundation

protocol BlessingRepository: Sendable {
    func bootstrap() async throws -> AppBootstrap
    func circleContext(circleID: UUID) async throws -> CircleContext
    func circleContext(promptID: UUID) async throws -> CircleContext
    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane]
    func timeline(circle: CircleGroup, viewerID: UUID, now: Date) async throws -> [TimelineLane]
    func timelinePage(circleID: UUID, viewerID: UUID, now: Date, before: Date?) async throws -> TimelinePage
    func timelinePage(circle: CircleGroup, viewerID: UUID, now: Date, before: Date?) async throws -> TimelinePage
    func blessing(id: UUID, viewerID: UUID) async throws -> Blessing?
    func beginBlessingEntry(promptID: UUID, memberID: UUID, now: Date) async throws
    func submit(
        promptID: UUID,
        authorID: UUID,
        mode: CaptureMode,
        body: String?,
        audioURL: URL?,
        videoURL: URL?,
        photoURL: URL?,
        scriptureReference: ScriptureReference?,
        now: Date
    ) async throws -> Blessing
    func updateBlessing(
        blessingID: UUID,
        authorID: UUID,
        body: String,
        scriptureReference: ScriptureReference?,
        now: Date
    ) async throws -> Blessing
    func joinCircle(code: String, memberID: UUID) async throws -> CircleGroup
    func createCircle(configuration: CircleConfiguration, member: Member) async throws -> CircleGroup
    func regenerateInviteCode(circleID: UUID, ownerID: UUID) async throws -> CircleGroup
    func updateCircleSettings(
        circleID: UUID,
        ownerID: UUID,
        name: String,
        timeZoneIdentifier: String,
        randomWindowStartMinutes: Int,
        randomWindowEndMinutes: Int,
        responseWindowMinutes: Int,
        allowsLateBlessings: Bool,
        repeatWindowMinutes: Int,
        endOfDayMinutes: Int
    ) async throws -> CircleGroup
    func updateCirclePhoto(circleID: UUID, ownerID: UUID, photoURL: URL?) async throws -> CircleGroup
    func updateCircleActivityNotifications(circleID: UUID, memberID: UUID, enabled: Bool) async throws
    func updateEndOfDayNotifications(circleID: UUID, memberID: UUID, enabled: Bool) async throws
    func forceCirclePrompt(circleID: UUID, ownerID: UUID, now: Date) async throws -> CirclePromptDispatch
    func updateBibleVersion(memberID: UUID, versionID: String) async throws -> Member
    func updateProfile(memberID: UUID, displayName: String, avatarURL: URL?) async throws -> Member
    func transferCircleOwnership(circleID: UUID, ownerID: UUID, newOwnerID: UUID) async throws -> CircleGroup
    func removeCircleMember(circleID: UUID, ownerID: UUID, memberID: UUID) async throws -> CircleGroup
    func recentBlessings(authorID: UUID, submittedAfter: Date) async throws -> [Blessing]
    func repeatBlessing(
        sourceBlessingID: UUID,
        targetPromptID: UUID,
        authorID: UUID,
        now: Date
    ) async throws -> Blessing
    func leaveCircle(circleID: UUID, memberID: UUID) async throws
    func nudgeMember(promptID: UUID, recipientID: UUID, senderID: UUID, now: Date) async throws -> Bool
    func responses(blessingID: UUID, viewerID: UUID) async throws -> [BlessingResponse]
    func submitResponse(
        blessingID: UUID,
        circleID: UUID,
        authorID: UUID,
        mode: ResponseMode,
        body: String,
        audioURL: URL?,
        now: Date
    ) async throws -> BlessingResponse
    func timelineUpdates(circleID: UUID) async throws -> AsyncStream<Void>
    func registerDevice(
        installationID: UUID,
        apnsToken: String?,
        pushToStartToken: String?,
        environment: String
    ) async throws
    func registerActivity(
        promptID: UUID,
        activityID: String,
        pushToken: String,
        environment: String
    ) async throws
}

extension BlessingRepository {
    // Only pass metadata fetched as part of the same load. Content is still read
    // afresh under server authorization; this is not a cross-refresh cache.
    func timeline(circle: CircleGroup, viewerID: UUID, now: Date) async throws -> [TimelineLane] {
        try await timeline(circleID: circle.id, viewerID: viewerID, now: now)
    }
    func timelinePage(circle: CircleGroup, viewerID: UUID, now: Date, before: Date?) async throws -> TimelinePage {
        try await timelinePage(circleID: circle.id, viewerID: viewerID, now: now, before: before)
    }
    func blessing(id: UUID, viewerID: UUID) async throws -> Blessing? { nil }
    func timelinePage(circleID: UUID, viewerID: UUID, now: Date, before: Date?) async throws -> TimelinePage {
        let circle = try await circleContext(circleID: circleID).circle
        return TimelinePaging.page(try await timeline(circleID: circleID, viewerID: viewerID, now: now),
            before: before, calendar: CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier))
    }
}

protocol AuthenticationProviding: Sendable {
    /// Local identity only, without refreshing or authorizing a server request.
    func cachedUserID() async -> UUID?
    func hasSession() async -> Bool
    func currentUserID() async -> UUID?
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws
    func signOut() async throws
}

extension AuthenticationProviding {
    func cachedUserID() async -> UUID? { nil }
    func currentUserID() async -> UUID? { nil }
}
