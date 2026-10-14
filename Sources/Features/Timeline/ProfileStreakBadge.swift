import SwiftUI

struct ProfileStreakBadge: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .caption2) private var compactFontSize: CGFloat = 9
    let memberID: UUID
    var compact = false

    var body: some View {
        if let streak = model.circle?.streaks?[memberID], streak.days > 0 {
            let flameColor = streak.hasOnlyTimelyEntries ? AppTheme.streakBlue : AppTheme.streakRed
            HStack(spacing: compact ? 2 : 3) {
                Image(systemName: "flame.fill").foregroundStyle(flameColor)
                Text("\(streak.days)").monospacedDigit()
            }
            .font(compact ? .system(size: compactFontSize, weight: .semibold) : .caption2.weight(.semibold))
            // Keep the secondary pill compact enough to leave the photo visible.
            // VoiceOver announces the full streak and timely-entry information below.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, compact ? 4 : 5)
            .padding(.vertical, compact ? 2 : 3)
            .background(AppTheme.surface, in: Capsule())
            .overlay { Capsule().stroke(flameColor.opacity(0.55), lineWidth: 1) }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(streak.days) day streak in \(model.circle?.name ?? "this circle"). \(streak.hasOnlyTimelyEntries ? "Every day entered in time." : "Includes late entry.") \(streak.onTimeDays) timely-entry days.\(streak.onTimeToday ? " Entered in time today." : "")")
        }
    }
}

/// The pill overlays the photo, so it adds no width/height to the adjacent name.
struct ProfileStreakAvatar: View {
    let member: Member
    let size: CGFloat
    var enlargesPhoto = false
    var body: some View {
        AvatarBadge(member: member, size: size)
            .photoEnlargement(url: enlargesPhoto ? member.avatarURL : nil,
                title: "\(member.displayName) profile photo", hitSlop: max(0, (44 - size) / 2))
            .overlay(alignment: .topTrailing) {
                ProfileStreakBadge(memberID: member.id, compact: true)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .offset(x: 6)
            }
    }
}
