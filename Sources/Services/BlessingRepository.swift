import Foundation

protocol BlessingRepository: Sendable {
    func bootstrap() async throws -> AppBootstrap
    func circleContext(circleID: UUID) async throws -> CircleContext
    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane]
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
    func joinCircle(code: String, memberID: UUID) async throws -> CircleGroup
    func createCircle(name: String, member: Member) async throws -> CircleGroup
    func updateCircleSettings(
        circleID: UUID,
        ownerID: UUID,
        name: String,
        timeZoneIdentifier: String,
        randomWindowStartMinutes: Int,
        randomWindowEndMinutes: Int,
        responseWindowMinutes: Int,
        allowsLateBlessings: Bool,
        repeatWindowMinutes: Int
    ) async throws -> CircleGroup
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

protocol AuthenticationProviding: Sendable {
    func hasSession() async -> Bool
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws
    func signOut() async throws
}
