import Foundation

struct NudgeKey: Hashable, Sendable {
    let promptID: UUID
    let recipientID: UUID
}

struct NudgeCandidate: Identifiable, Sendable {
    let prompt: DailyPrompt
    let member: Member
    var id: NudgeKey { NudgeKey(promptID: prompt.id, recipientID: member.id) }
}

enum NudgePolicy {
    static func isEligible(
        prompt: DailyPrompt, circle: CircleGroup, senderID: UUID, recipientID: UUID,
        senderHasShared: Bool, recipientHasShared: Bool, now: Date,
        nextDailyStart: Date? = nil
    ) -> Bool {
        guard senderID != recipientID, senderHasShared, !recipientHasShared,
              circle.members.contains(where: { $0.id == senderID }),
              circle.members.contains(where: { $0.id == recipientID }),
              now >= prompt.startsAt else { return false }
        if prompt.kind == .endOfDay {
            return now < prompt.endsAt && (nextDailyStart.map { now < $0 } ?? true)
        }
        return now < prompt.endsAt
            || (circle.allowsLateBlessings && (nextDailyStart.map { now < $0 } ?? true))
    }
}
