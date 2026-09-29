import Foundation

protocol BlessingRepository: Sendable {
    func bootstrap() async throws -> (Member, Circle, DailyPrompt)
    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane]
    func submit(
        promptID: UUID,
        authorID: UUID,
        mode: CaptureMode,
        body: String?,
        videoURL: URL?,
        now: Date
    ) async throws -> Blessing
    func joinCircle(code: String, memberID: UUID) async throws -> Circle
    func createCircle(name: String, member: Member) async throws -> Circle
}

