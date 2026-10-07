import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BlessingCircleWidgetBundle: WidgetBundle {
    var body: some Widget {
        BlessingCircleHomeWidget()
        BlessingCircleLiveActivity()
    }
}

struct BlessingCircleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PromptActivityAttributes.self) { context in
            HStack(spacing: 16) {
                MannaWordmark(width: 76)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.circleName)
                        .font(.headline)
                    LiveActivityStatusText(state: context.state)
                        .font(context.state.hasSubmitted ? .subheadline : .title3.monospacedDigit().weight(.semibold))
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(MannaWidgetTheme.primary)
            .widgetURL(captureURL(promptID: context.attributes.promptID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MannaWordmark(width: 58)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityCompactStatus(state: context.state)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.hasSubmitted ? "Shared with \(context.attributes.circleName)" : "What feels like a blessing today?")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            } compactLeading: {
                MannaWordmark(width: 28)
            } compactTrailing: {
                LiveActivityCompactStatus(state: context.state)
            } minimal: {
                MannaWordmark(width: 24)
            }
            .widgetURL(captureURL(promptID: context.attributes.promptID))
            .keylineTint(MannaWidgetTheme.primary)
        }
    }

    private func captureURL(promptID: UUID) -> URL? {
        URL(string: "blessingcircle://today/capture?prompt=\(promptID.uuidString)")
    }
}

private struct LiveActivityCompactStatus: View {
    let state: PromptActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if !state.hasSubmitted, context.date < state.endsAt {
                LiveActivityCountdownText(endsAt: state.endsAt)
                    .monospacedDigit()
                    .frame(width: 44)
            } else if !state.hasSubmitted, state.allowsLateBlessings {
                Image(systemName: "clock.badge.exclamationmark")
                    .accessibilityLabel("Late sharing is open")
            } else {
                Image(systemName: "checkmark")
                    .accessibilityLabel(state.hasSubmitted ? "Blessing shared" : "Window closed")
            }
        }
    }
}

private struct LiveActivityStatusText: View {
    let state: PromptActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if state.hasSubmitted {
                Text("Your blessing is shared")
            } else if context.date < state.endsAt {
                LiveActivityCountdownText(endsAt: state.endsAt)
            } else if state.allowsLateBlessings {
                Text("Late sharing is open")
            } else {
                Text("Window closed")
            }
        }
    }
}

private struct LiveActivityCountdownText: View {
    let endsAt: Date

    var body: some View {
        let now = Date.now
        Text(
            timerInterval: PromptActivityCountdown.interval(now: now, endsAt: endsAt),
            countsDown: true
        )
    }
}
