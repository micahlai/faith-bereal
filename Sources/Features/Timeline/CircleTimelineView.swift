import SwiftUI

struct CircleTimelineView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            if model.lanes.isEmpty {
                ContentUnavailableView(
                    "No days yet",
                    systemImage: "clock",
                    description: Text("Your circle’s blessings will gather here.")
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        ForEach(model.lanes) { lane in
                            TimelineLaneView(lane: lane, isCurrentUser: lane.member.id == model.currentUser?.id)
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 18)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.visible)
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { try? await model.refreshTimeline() }
    }
}

private struct TimelineLaneView: View {
    let lane: TimelineLane
    let isCurrentUser: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                AvatarBadge(member: lane.member, size: 52)
                Text(isCurrentUser ? "You" : lane.member.displayName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
            }
            .padding(.bottom, 20)

            ForEach(Array(lane.events.enumerated()), id: \.element.id) { index, event in
                TimelineEventView(event: event, isLast: index == lane.events.count - 1)
            }
        }
        .frame(width: 238)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(isCurrentUser ? "Your" : lane.member.displayName + "’s") timeline")
    }
}

private struct TimelineEventView: View {
    let event: TimelineEvent
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                marker
                    .frame(width: 24, height: 24)
                if !isLast {
                    Rectangle()
                        .fill(AppTheme.divider)
                        .frame(width: 2, height: 132)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, isLast ? 0 : 22)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var marker: some View {
        switch event.status {
        case .blessing:
            Circle()
                .fill(AppTheme.iris)
                .overlay { Circle().stroke(AppTheme.surface, lineWidth: 5) }
        case .missed:
            Circle()
                .stroke(AppTheme.missed, style: StrokeStyle(lineWidth: 3, dash: [3, 3]))
                .padding(3)
        case .locked:
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.candle)
                .background(Circle().fill(AppTheme.surface).frame(width: 24, height: 24))
        case .waiting:
            Circle()
                .stroke(AppTheme.dawn, lineWidth: 2)
                .padding(4)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch event.status {
        case let .blessing(blessing):
            VStack(alignment: .leading, spacing: 8) {
                if blessing.captureMode == .video {
                    Label("Video blessing", systemImage: "play.rectangle.fill")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(blessing.body ?? "")
                        .font(.system(.subheadline, design: .serif))
                        .lineLimit(5)
                }
                Text(blessing.submittedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryInk)
                if blessing.isLate {
                    Label("Late", systemImage: "clock.badge.exclamationmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.candle)
                }
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .missed:
            Label("Missed this day", systemImage: "minus.circle")
                .font(.subheadline)
                .foregroundStyle(AppTheme.missed)
                .padding(.vertical, 10)
        case .locked:
            VStack(alignment: .leading, spacing: 5) {
                Label("Today is hidden", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Share yours to open it.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(14)
            .background(AppTheme.candle.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .waiting:
            Label("Still time to share", systemImage: "hourglass")
                .font(.subheadline)
                .foregroundStyle(AppTheme.dawn)
                .padding(.vertical, 10)
        }
    }
}

struct AvatarBadge: View {
    let member: Member
    let size: CGFloat

    var body: some View {
        Text(member.initials)
            .font(.system(size: size * 0.31, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(avatarColor, in: Circle())
            .accessibilityLabel(member.displayName)
    }

    private var avatarColor: Color {
        [AppTheme.iris, AppTheme.dawn, AppTheme.candle][abs(member.tintSeed) % 3]
    }
}
