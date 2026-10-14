import Foundation

struct CircleStreak: Codable, Hashable, Sendable {
    let memberID: UUID
    let days: Int
    let onTimeDays: Int
    let onTimeToday: Bool
    var onTimeStreakDays: Int = 0

    var hasOnlyTimelyEntries: Bool { days > 0 && onTimeDays == days }

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id", days, onTimeDays = "on_time_days", onTimeToday = "on_time_today"
        case onTimeStreakDays = "on_time_streak_days"
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
    }
}

struct StreakDay: Sendable {
    let circleID: UUID
    let memberID: UUID
    let day: Date
    let onTime: Bool
}

enum CircleStreakPolicy {
    static func summaries(circle: CircleGroup, posts: [StreakDay], now: Date) -> [UUID: CircleStreak] {
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        return Dictionary(uniqueKeysWithValues: circle.members.map { member in
            var days: [Date: Bool] = [:]
            for post in posts where post.circleID == circle.id && post.memberID == member.id {
                let day = calendar.startOfDay(for: post.day)
                guard day <= today, day >= calendar.startOfDay(for: member.joinedAt) else { continue }
                days[day] = (days[day] ?? false) || post.onTime
            }
            let anchor = days[today] == nil ? yesterday : today
            var cursor = anchor
            var count = 0, onTime = 0
            while let timely = days[cursor] {
                count += 1
                if timely { onTime += 1 }
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
            }
            cursor = anchor
            var timelyRun = 0
            while days[cursor] == true {
                timelyRun += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
            }
            return (member.id, CircleStreak(memberID: member.id, days: count, onTimeDays: onTime,
                onTimeToday: days[today] == true, onTimeStreakDays: timelyRun))
        })
    }
}
