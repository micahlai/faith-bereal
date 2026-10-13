import Foundation

struct BlessingDraft: Codable, Sendable, Equatable, Identifiable {
    let authorID: UUID
    let circleID: UUID
    let promptID: UUID
    let createdAt: Date
    let expiresAt: Date
    var updatedAt: Date
    var mode: CaptureMode
    var text: String
    var audioSegments: [URL]
    var videoURL: URL?
    var photoURL: URL?
    var scriptureReference: ScriptureReference?
    var repeatSourceID: UUID?
    var id: UUID { promptID }
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !audioSegments.isEmpty
            || videoURL != nil || photoURL != nil || scriptureReference != nil || repeatSourceID != nil
    }
}

enum BlessingDraftPolicy {
    static func expiry(createdAt: Date, timeZoneIdentifier: String) -> Date {
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: timeZoneIdentifier)
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: createdAt))!
    }

    static func canResume(_ draft: BlessingDraft, authorID: UUID, prompt: DailyPrompt, circle: CircleGroup,
                          now: Date, nextDailyPrompt: DailyPrompt? = nil) -> Bool {
        guard draft.authorID == authorID, draft.circleID == circle.id, draft.promptID == prompt.id,
              now >= draft.createdAt, now < draft.expiresAt,
              let member = circle.members.first(where: { $0.id == authorID }) else { return false }
        if prompt.kind == .endOfDay {
            let nextHasStarted = nextDailyPrompt.map {
                $0.notificationHasStarted != false && $0.startsAt > prompt.startsAt && $0.startsAt <= now
            } ?? false
            return prompt.phase(at: now) == .open && !nextHasStarted
        }
        if FirstDaySubmissionPolicy.isEligible(memberJoinedAt: member.joinedAt, prompt: prompt, circle: circle, now: now) { return true }
        if prompt.phase(at: now) == .open { return true }
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier)
        return prompt.phase(at: now) == .closed && circle.allowsLateBlessings
            && calendar.isDate(prompt.localDate, inSameDayAs: now)
    }
}
