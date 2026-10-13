import Foundation

enum TimelinePresentation {
    static func notificationTimes(_ events: [TimelineEvent]) -> [TimelineNotificationStamp] {
        Array(Set(events.compactMap { event -> TimelineNotificationStamp? in
            guard !event.isWelcome, let date = event.notificationStartedAt, let kind = event.promptKind else { return nil }
            return TimelineNotificationStamp(kind: kind, date: date)
        })).sorted { $0.date < $1.date }
    }
    static func listEntries(_ lanes: [TimelineLane]) -> [TimelineListEntry] {
        lanes.flatMap { lane in
            lane.events.compactMap { event -> TimelineListEntry? in
                switch event.status {
                case .blessing, .joinedCircle: TimelineListEntry(member: lane.member, event: event)
                default: nil
                }
            }
        }.sorted { $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate > $1.sortDate }
    }
    static func lanes(_ source: [TimelineLane], calendar: Calendar) -> [TimelineLane] {
        source.map { lane in
            TimelineLane(member: lane.member, events: lane.events.filter { $0.status != .scheduled }.map { event in
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

struct TimelineNotificationStamp: Identifiable, Hashable {
    let kind: PromptKind
    let date: Date
    var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }
}

struct TimelineListEntry: Identifiable {
    let member: Member
    let event: TimelineEvent
    var id: String { event.id }
    var sortDate: Date {
        if case let .blessing(blessing) = event.status { return blessing.submittedAt }
        return event.date
    }
}
