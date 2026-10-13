import SwiftUI

struct ProfileStreakBadge: View {
    @Environment(AppModel.self) private var model
    let memberID: UUID

    var body: some View {
        if let streak = model.circle?.streaks?[memberID], streak.days > 0 {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill").foregroundStyle(AppTheme.candle)
                Text("\(streak.days)").monospacedDigit()
                if streak.onTimeToday { Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.dawn) }
            }
            .font(.caption.weight(.semibold))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(streak.days) day streak in \(model.circle?.name ?? "this circle"). \(streak.onTimeDays) timely-entry days.\(streak.onTimeToday ? " Entered in time today." : "")")
        }
    }
}
