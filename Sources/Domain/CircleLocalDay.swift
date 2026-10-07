import Foundation

enum CircleLocalDay {
    static func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    static func date(from storageValue: String, timeZoneIdentifier: String) -> Date? {
        let parts = storageValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        guard let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return date
    }
}
