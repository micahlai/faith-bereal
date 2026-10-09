import Foundation

enum TimelineStatusPolicy {
    static func status(
        prompt: DailyPrompt, circle: CircleGroup, member: Member,
        viewerID: UUID, viewerHasSubmitted: Bool, blessing: Blessing?,
        now: Date, entryIsOpen: Bool, requiresSubmissionGate: Bool
    ) -> TimelineStatus {
        if let blessing {
            return requiresSubmissionGate && member.id != viewerID && !viewerHasSubmitted
                ? .locked : .blessing(blessing)
        }
        // Scheduled does not mean shareable. Keep the explicit join-day exception.
        if prompt.phase(at: now) == .scheduled
            && !FirstDaySubmissionPolicy.isEligible(
                memberJoinedAt: member.joinedAt, prompt: prompt, circle: circle, now: now
            ) {
            return .scheduled
        }
        if requiresSubmissionGate && member.id != viewerID && !viewerHasSubmitted { return .locked }
        return requiresSubmissionGate && entryIsOpen ? .waiting : .missed
    }
}
