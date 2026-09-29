import Foundation

protocol BlessingRepository: Sendable {
    func bootstrap() async throws -> AppBootstrap
    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane]
    func submit(
        promptID: UUID,
        authorID: UUID,
        mode: CaptureMode,
        body: String?,
        audioURL: URL?,
        videoURL: URL?,
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
        allowsLateBlessings: Bool
    ) async throws -> CircleGroup
    func updateBibleVersion(memberID: UUID, versionID: String) async throws -> Member
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
