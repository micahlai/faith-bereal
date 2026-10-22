import Foundation

struct TimelinePage: Sendable {
    let lanes: [TimelineLane]
    let nextBeforeDate: Date?
}

enum TimelinePaging {
    static let daysPerPage = 7
    static func scope(circleID: UUID, viewerID: UUID, timeZoneIdentifier: String) -> String {
        "\(circleID)|\(viewerID)|\(timeZoneIdentifier)"
    }

    static func page(_ lanes: [TimelineLane], before: Date?, calendar: Calendar, limit: Int = daysPerPage) -> TimelinePage {
        let limit = max(1, limit)
        let days = Set(lanes.flatMap(\.events).filter { $0.status != .joinedCircle }
            .map { calendar.startOfDay(for: $0.date) })
        return makePage(lanes, before: before, calendar: calendar, limit: limit, days: days)
    }

    private static func makePage(_ lanes: [TimelineLane], before: Date?, calendar: Calendar, limit: Int, days: Set<Date>) -> TimelinePage {
        let ordered = days.filter { day in before.map { day < calendar.startOfDay(for: $0) } ?? true }.sorted(by: >)
        let selected = Set(ordered.prefix(limit))
        let hasMore = ordered.count > limit
        let oldest = selected.min()
        let result = lanes.map { lane in
            TimelineLane(member: lane.member, events: lane.events.filter { event in
                let day = calendar.startOfDay(for: event.date)
                if let before, day >= calendar.startOfDay(for: before) { return false }
                if event.status == .joinedCircle { return !hasMore || oldest.map { day >= $0 } ?? true }
                return selected.contains(day)
            })
        }
        return TimelinePage(lanes: result, nextBeforeDate: hasMore ? oldest : nil)
    }

    static func merge(_ existing: [TimelineLane], with incoming: [TimelineLane]) -> [TimelineLane] {
        incoming.map { lane in
            var events = Dictionary(uniqueKeysWithValues: (existing.first { $0.id == lane.id }?.events ?? []).map { ($0.id, $0) })
            lane.events.forEach { events[$0.id] = $0 }
            return TimelineLane(member: lane.member, events: events.values.sorted { $0.date > $1.date })
        }
    }
}
