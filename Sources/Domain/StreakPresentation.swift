import Foundation

struct StreakIndicator: Equatable, Sendable {
    enum Kind: String, Hashable, Sendable { case overall, onTime }
    let kind: Kind
    let count: Int
}

extension CircleStreak {
    /// The photo always shows the overall count. Blue recognizes an equal timely run.
    var profileIndicator: StreakIndicator? {
        guard days > 0 else { return nil }
        return StreakIndicator(kind: days == onTimeStreakDays ? .onTime : .overall, count: days)
    }

    var circleIndicators: [StreakIndicator] {
        var result: [StreakIndicator] = []
        if days > 0 { result.append(StreakIndicator(kind: .overall, count: days)) }
        if onTimeStreakDays > 0 { result.append(StreakIndicator(kind: .onTime, count: onTimeStreakDays)) }
        return result
    }
}
