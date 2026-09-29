import Foundation

protocol BlessingRepository: Sendable {
    func bootstrap() async throws -> (Member, CircleGroup, DailyPrompt)
    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane]
    func submit(
        promptID: UUID,
        authorID: UUID,
        mode: CaptureMode,
        body: String?,
        videoURL: URL?,
        scriptureReference: ScriptureReference?,
        now: Date
    ) async throws -> Blessing
    func joinCircle(code: String, memberID: UUID) async throws -> CircleGroup
    func createCircle(name: String, member: Member) async throws -> CircleGroup
    func updateCircleSettings(
        circleID: UUID,
        ownerID: UUID,
        responseWindowMinutes: Int,
        allowsLateBlessings: Bool
    ) async throws -> CircleGroup
    func updateBibleVersion(memberID: UUID, versionID: String) async throws -> Member
}
