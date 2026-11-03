import Foundation

protocol ReadyCircleCountProviding: Sendable {
    func readyCircleCount(userID: UUID, now: Date) async throws -> Int
}

protocol DeviceNotificationRevoking: Sendable {
    func revokeDeviceNotifications(installationID: UUID) async throws
}

enum ReadyCircleBadgePolicy {
    static func count(circles: [CircleGroup], prompts: [DailyPrompt], submitted: Set<UUID>, userID: UUID, now: Date)
        -> Int
    {
        Set(
            prompts.filter { prompt in
                guard !submitted.contains(prompt.id), prompt.notificationHasStarted != false,
                    let circle = circles.first(where: { $0.id == prompt.circleID }),
                    let member = circle.members.first(where: { $0.id == userID })
                else { return false }
                let newerDaily = prompts.contains {
                    $0.circleID == prompt.circleID && $0.kind == .daily && $0.startsAt > prompt.startsAt
                        && $0.startsAt <= now
                }
                if prompt.kind == .endOfDay { return prompt.phase(at: now) == .open && !newerDaily }
                return prompt.phase(at: now) == .open
                    || (now >= prompt.startsAt && circle.allowsLateBlessings && !newerDaily
                        && prompt.occursOnCircleDay(at: now, timeZoneIdentifier: circle.timeZoneIdentifier))
                    || FirstDaySubmissionPolicy.isEligible(
                        memberJoinedAt: member.joinedAt, prompt: prompt, circle: circle, now: now)
            }.map(\.circleID)
        ).count
    }
}
