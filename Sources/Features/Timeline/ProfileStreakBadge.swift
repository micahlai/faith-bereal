import SwiftUI

struct ProfileStreakBadge: View {
    @Environment(AppModel.self) private var model
    let memberID: UUID

    var body: some View {
        if let streak = model.circle?.streaks?[memberID], streak.days > 0 {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill").foregroundStyle(AppTheme.streakBlue)
                Text("\(streak.days)").monospacedDigit()
                if streak.onTimeToday { Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.streakBlue) }
            }
            .font(.caption2.weight(.semibold))
            // Keep the secondary pill compact enough to leave the photo visible.
            // VoiceOver announces the full streak and timely-entry information below.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(AppTheme.surface, in: Capsule())
            .overlay { Capsule().stroke(AppTheme.streakBlue.opacity(0.55), lineWidth: 1) }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(streak.days) day streak in \(model.circle?.name ?? "this circle"). \(streak.onTimeDays) timely-entry days.\(streak.onTimeToday ? " Entered in time today." : "")")
        }
    }
}

/// The pill overlays the photo, so it adds no width/height to the adjacent name.
struct ProfileStreakAvatar: View {
    let member: Member
    let size: CGFloat
    var body: some View {
        AvatarBadge(member: member, size: size)
            .overlay(alignment: .topTrailing) {
                ProfileStreakBadge(memberID: member.id).offset(x: 8)
            }
    }
}
