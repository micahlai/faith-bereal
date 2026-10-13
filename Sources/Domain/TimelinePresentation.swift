import Foundation

enum TimelinePresentation {
    static func lanes(_ source: [TimelineLane], calendar: Calendar) -> [TimelineLane] {
        source.map { lane in
            TimelineLane(member: lane.member, events: lane.events.map { event in
                guard event.promptKind == .daily, case let .blessing(blessing) = event.status,
                      calendar.startOfDay(for: event.date) < calendar.startOfDay(for: lane.member.joinedAt),
                      blessing.submittedAt >= lane.member.joinedAt,
                      calendar.isDate(blessing.submittedAt, inSameDayAs: lane.member.joinedAt) else { return event }
                return TimelineEvent(memberID: lane.member.id, date: calendar.startOfDay(for: blessing.submittedAt),
                    status: event.status, promptKind: event.promptKind, isWelcome: true,
                    id: event.id + "-welcome")
            })
        }
    }
}
