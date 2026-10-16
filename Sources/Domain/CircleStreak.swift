import Foundation

struct CircleStreak: Codable, Hashable, Sendable {
    let memberID: UUID
    let days: Int
    let onTimeDays: Int
    let onTimeToday: Bool
    var onTimeStreakDays: Int = 0
    var nextUpdateAt: Date? = nil

    var hasOnlyTimelyEntries: Bool { days > 0 && onTimeStreakDays == days }

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id", days, onTimeDays = "on_time_days", onTimeToday = "on_time_today"
        case onTimeStreakDays = "on_time_streak_days"
        case nextUpdateAt = "next_update_at"
    }
}

extension CircleStreak {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        memberID = try values.decode(UUID.self, forKey: .memberID)
        days = try values.decode(Int.self, forKey: .days)
        onTimeDays = try values.decode(Int.self, forKey: .onTimeDays)
        onTimeToday = try values.decode(Bool.self, forKey: .onTimeToday)
        // A mixed older response gives no evidence of where its late day occurred.
        // Only a wholly timely run permits inferring a consecutive timely count.
        onTimeStreakDays = try values.decodeIfPresent(Int.self, forKey: .onTimeStreakDays)
            ?? (days == onTimeDays ? days : 0)
        nextUpdateAt = try values.decodeIfPresent(Date.self, forKey: .nextUpdateAt)
    }
}

struct StreakDay: Sendable {
    let circleID: UUID
    let memberID: UUID
    let day: Date
    let onTime: Bool
    var kind: PromptKind = .daily
}

enum CircleStreakPolicy {
    /// A completed post resolves its own day immediately. An absent post resolves
    /// only when that day's authored opportunity closes, including overnight evening entry.
    static func summaries(
        circle: CircleGroup, posts: [StreakDay], prompts: [DailyPrompt] = [], now: Date
    ) -> [UUID: CircleStreak] {
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let circlePrompts = prompts.filter { $0.circleID == circle.id }
        let promptsByDay = Dictionary(grouping: circlePrompts) { calendar.startOfDay(for: $0.localDate) }
        func previous(_ day: Date) -> Date { calendar.date(byAdding: .day, value: -1, to: day)! }
        func cutoffs(_ day: Date) -> (general: Date, timely: Date) {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            let authored = promptsByDay[day] ?? []
            let dailyEnd = authored.filter {
                $0.kind == .daily && $0.notificationHasStarted != false
            }.map(\.endsAt).max()
            let eveningEnd = authored.filter {
                $0.kind == .endOfDay && $0.notificationHasStarted != false
            }.map { evening in
                let nextDaily = circlePrompts.filter {
                    $0.kind == .daily && $0.notificationHasStarted != false && $0.startsAt > evening.startsAt
                }.map(\.startsAt).min()
                return min(evening.endsAt, nextDaily ?? evening.endsAt)
            }.max()
            // An actual evening window defines the final opportunity for that
            // day. Until one is authored, keep the general day pending at least
            // through midnight rather than resetting at the random deadline.
            return (max(dailyEnd ?? .distantPast, eveningEnd ?? nextDay), dailyEnd ?? nextDay)
        }
        return Dictionary(uniqueKeysWithValues: circle.members.map { member in
            let joinedDay = calendar.startOfDay(for: member.joinedAt)
            var completed: Set<Date> = []
            var dailyResults: [Date: Bool] = [:]
            for post in posts where post.circleID == circle.id && post.memberID == member.id {
                let day = calendar.startOfDay(for: post.day)
                guard day <= today, day >= joinedDay else { continue }
                let authored = (promptsByDay[day] ?? []).filter { $0.kind == post.kind }
                if !authored.isEmpty && !authored.contains(where: {
                    $0.notificationHasStarted != false && $0.startsAt <= now
                }) { continue }
                completed.insert(day)
                if post.kind == .daily {
                    dailyResults[day] = (dailyResults[day] ?? false) || post.onTime
                }
            }
            // Usually only today and yesterday can be unresolved. Start from the
            // earliest actual opportunity so long custom/overnight windows also work.
            let earliestPromptDay = promptsByDay.keys.min() ?? today
            let earliestRelevant = max(joinedDay, min(earliestPromptDay, previous(today)))
            func anchor(timely: Bool) -> Date? {
                var day = today
                while day >= earliestRelevant {
                    if timely ? dailyResults[day] != nil : completed.contains(day) { return day }
                    let deadline = timely ? cutoffs(day).timely : cutoffs(day).general
                    if now >= deadline { return day }
                    day = previous(day)
                }
                return nil
            }
            var count = 0, timelyInGeneral = 0
            if var cursor = anchor(timely: false) {
                while cursor >= joinedDay, completed.contains(cursor) {
                    count += 1
                    if dailyResults[cursor] == true { timelyInGeneral += 1 }
                    cursor = previous(cursor)
                }
            }
            var timelyRun = 0
            if var cursor = anchor(timely: true) {
                while cursor >= joinedDay, dailyResults[cursor] == true {
                    timelyRun += 1
                    cursor = previous(cursor)
                }
            }
            var upcoming: [Date] = []
            // Deadline metadata is only needed for unresolved recent authored days.
            // Past dates with no prompt resolve at midnight; today's does likewise.
            var cursor = today
            while cursor >= earliestRelevant {
                let deadlines = cutoffs(cursor)
                if !completed.contains(cursor), deadlines.general > now { upcoming.append(deadlines.general) }
                if dailyResults[cursor] == nil, deadlines.timely > now { upcoming.append(deadlines.timely) }
                cursor = previous(cursor)
            }
            return (member.id, CircleStreak(memberID: member.id, days: count, onTimeDays: timelyInGeneral,
                onTimeToday: dailyResults[today] == true, onTimeStreakDays: timelyRun,
                nextUpdateAt: upcoming.min()))
        })
    }
}
