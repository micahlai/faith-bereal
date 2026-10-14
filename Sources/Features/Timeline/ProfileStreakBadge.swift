import SwiftUI

struct ProfileStreakBadge: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var compactFontSize: CGFloat = 9
    @State private var showingDetails = false
    let memberID: UUID
    var compact = false

    var body: some View {
        if let streak = model.circle?.streaks?[memberID], streak.days > 0 {
            let flameColor = streak.hasOnlyTimelyEntries ? AppTheme.streakBlue : AppTheme.streakRed
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                    showingDetails.toggle()
                }
            } label: {
                HStack(spacing: compact ? 2 : 3) {
                    Image(systemName: "flame.fill").foregroundStyle(flameColor)
                    Text("\(streak.days)").monospacedDigit()
                }
                .font(compact ? .system(size: compactFontSize, weight: .semibold) : .caption2.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, compact ? 4 : 5)
                .padding(.vertical, compact ? 2 : 3)
                .background(AppTheme.surface, in: Capsule())
                .overlay { Capsule().stroke(flameColor.opacity(0.55), lineWidth: 1) }
                .fixedSize()
                .frame(minWidth: 44, minHeight: 44, alignment: compact ? .topTrailing : .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityLabel("\(streak.days) day streak in \(model.circle?.name ?? "this circle"). \(streak.onTimeStreakDays) on time days in a row.")
            .accessibilityHint("Show both streak counts")
            .accessibilityIdentifier("streak.details.\(memberID.uuidString)")
            .popover(isPresented: $showingDetails, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("\(streak.days) days in a row")
                    } icon: {
                        Image(systemName: "flame.fill").foregroundStyle(AppTheme.streakRed)
                    }
                    Label {
                        Text("\(streak.onTimeStreakDays) on time days in a row")
                    } icon: {
                        Image(systemName: "flame.fill").foregroundStyle(AppTheme.streakBlue)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink)
                .padding(16)
                .frame(maxWidth: 300, alignment: .leading)
                .background(AppTheme.surface)
                .presentationCompactAdaptation(.popover)
            }
            .onChange(of: model.circle?.id) { _, _ in showingDetails = false }
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
                ProfileStreakBadge(memberID: member.id, compact: true)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .offset(x: 6)
            }
    }
}
