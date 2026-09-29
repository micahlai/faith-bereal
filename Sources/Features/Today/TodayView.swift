import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if let prompt = model.prompt {
                        PromptWindowView(
                            prompt: prompt,
                            hasSubmitted: model.hasSubmittedToday,
                            shareAction: { model.isCapturePresented = true },
                            timelineAction: { model.selectedTab = 1 }
                        )
                    }
                    intention
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.vertical, 18)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.circle?.name ?? "Your circle")
                .font(.headline)
                .foregroundStyle(AppTheme.iris)
            Text("What feels like a blessing today?")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var intention: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(AppTheme.dawn)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Share before you scroll")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("Past blessings are always here. Today’s words from your circle open after you add your own.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .blessingCard()
    }
}

private struct PromptWindowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prompt: DailyPrompt
    let hasSubmitted: Bool
    let shareAction: () -> Void
    let timelineAction: () -> Void

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: Date.now, by: 1.0)) { context in
            promptContent(at: context.date)
        }
    }

    private func promptContent(at date: Date) -> some View {
        let phase = prompt.phase(at: date)
        let remaining = max(0, prompt.endsAt.timeIntervalSince(date))
        let progress = min(1, max(0, remaining / 600))

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
                    if hasSubmitted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppTheme.iris)
                            .accessibilityHidden(true)
                        Text("Shared")
                            .font(.headline)
                    } else if phase == .open {
                        Text(durationString(remaining))
                            .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                        Text("to respond")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                    } else if phase == .scheduled {
                        Text(prompt.startsAt, style: .time)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("today’s moment")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
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

            if hasSubmitted {
                Button(action: timelineAction) {
                    Label("See today’s circle", systemImage: "person.3.fill")
                        .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(action: shareAction) {
                    Label("Share a blessing", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(phase != .open)
            }
        }
        .blessingCard()
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func accessibilityLabel(phase: PromptPhase, remaining: TimeInterval) -> String {
        if hasSubmitted { return "Your blessing was shared" }
        return switch phase {
        case .scheduled: "Today’s prompt starts at \(prompt.startsAt.formatted(date: .omitted, time: .shortened))"
        case .open: "\(durationString(remaining)) remaining to share your blessing"
        case .closed: "Today’s response window is closed"
        }
    }
}
