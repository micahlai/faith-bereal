import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        todayContent(at: context.date)
                    }
                    .frame(maxWidth: 680)
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 18)
                    .padding(.bottom, 100)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await model.refreshCurrentCircle() }
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func todayContent(at date: Date) -> some View {
        if model.currentUserBlessing(at: date) != nil {
            TodayBlessingsFeed(items: model.currentPromptBlessings(at: date))
        } else if let prompt = model.prompt,
                  model.isCurrentPromptToday(at: date),
                  model.isFirstCircleDay(at: date) || prompt.phase(at: date) == .open ||
                    (prompt.phase(at: date) == .closed && model.circle?.allowsLateBlessings == true) {
            PromptWindowView(
                prompt: prompt,
                date: date,
                allowsLateBlessings: model.circle?.allowsLateBlessings == true,
                isFirstCircleDay: model.isFirstCircleDay(at: date),
                allowsSharing: allowsSharing,
                shareAction: { model.isCapturePresented = true }
            )
        } else {
            WaitingForPromptView(circleName: model.circle?.name)
        }
    }

    private var allowsSharing: Bool {
#if DEBUG
        !model.isDebugPromptPreview
#else
        true
#endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.circle?.name ?? "Your circle")
                .font(.headline)
                .foregroundStyle(AppTheme.primary)
            Text("What feels like a blessing today?")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

private struct WaitingForPromptView: View {
    let circleName: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bell.badge")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 88, height: 88)
                .background(AppTheme.primary.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
            Text("Wait for today’s blessing notification")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
            Text("Everyone in \(circleName ?? "your circle") will be invited to share at the same moment.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .blessingCard()
        .accessibilityElement(children: .combine)
    }
}

private struct TodayBlessingsFeed: View {
    let items: [BlessingFeedItem]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today’s circle")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(items.count == 1 ? "1 blessing shared" : "\(items.count) blessings shared")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer()
                Image(systemName: "person.3.fill")
                    .foregroundStyle(AppTheme.primary)
                    .accessibilityHidden(true)
            }

            ForEach(items) { item in
                TodayBlessingCard(item: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TodayBlessingCard: View {
    let item: BlessingFeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                AvatarBadge(member: item.member, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.member.displayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(item.blessing.submittedAt.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer(minLength: 8)
                if item.blessing.isLate {
                    Label("Late", systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.candle)
                }
            }
            .accessibilityElement(children: .combine)

            BlessingContentView(blessing: item.blessing)
                .id(item.blessing.id)

            if let reference = item.blessing.scriptureReference {
                ScripturePassageView(reference: reference)
            }

            BlessingResponsesView(blessing: item.blessing, allowsResponding: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PromptWindowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prompt: DailyPrompt
    let date: Date
    let allowsLateBlessings: Bool
    let isFirstCircleDay: Bool
    let allowsSharing: Bool
    let shareAction: () -> Void

    var body: some View {
        promptContent(at: date)
    }

    private func promptContent(at date: Date) -> some View {
        let phase = prompt.phase(at: date)
        let remaining = max(0, prompt.endsAt.timeIntervalSince(date))
        let duration = max(1, prompt.endsAt.timeIntervalSince(prompt.startsAt))
        let progress = min(1, max(0, remaining / duration))

        return VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(AppTheme.divider, lineWidth: 13)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [AppTheme.candle, AppTheme.iris, AppTheme.dawn, AppTheme.candle],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: progress)

                VStack(spacing: 4) {
                    if isFirstCircleDay && phase != .open {
                        Image(systemName: "sun.horizon.fill")
                            .font(.title)
                            .foregroundStyle(AppTheme.candle)
                        Text("Your first day")
                            .font(.headline)
                        Text("Share anytime today")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    } else if phase == .open {
                        Text(durationString(remaining))
                            .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                        Text("to respond")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                    } else if allowsLateBlessings {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.title)
                            .foregroundStyle(AppTheme.candle)
                            .accessibilityHidden(true)
                        Text("Late sharing is open")
                            .font(.headline)
                    } else {
                        Image(systemName: "moon.stars")
                            .font(.title)
                            .foregroundStyle(AppTheme.secondaryInk)
                            .accessibilityHidden(true)
                        Text("Window closed")
                            .font(.headline)
                    }
                }
                .foregroundStyle(AppTheme.ink)
            }
            .frame(width: 210, height: 210)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(phase: phase, remaining: remaining))

            Button(action: shareAction) {
                Label(allowsSharing ? "Share a blessing" : "Hosted preview only", systemImage: allowsSharing ? "plus" : "eye")
                    .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!allowsSharing || (!isFirstCircleDay && phase != .open && !(phase == .closed && allowsLateBlessings)))
        }
        .blessingCard()
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func accessibilityLabel(phase: PromptPhase, remaining: TimeInterval) -> String {
        if isFirstCircleDay && phase != .open { return "On your first day in a circle, you can share anytime today" }
        return switch phase {
        case .scheduled: "Today’s prompt starts at \(prompt.startsAt.formatted(date: .omitted, time: .shortened))"
        case .open: "\(durationString(remaining)) remaining to share your blessing"
        case .closed: allowsLateBlessings ? "The response window ended, but late sharing is open" : "Today’s response window is closed"
        }
    }
}
