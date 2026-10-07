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
                    if context.state.hasSubmitted {
                        Text("Your blessing is shared")
                            .font(.subheadline)
                    } else {
                        LiveActivityCountdownText(endsAt: context.state.endsAt)
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(MannaWidgetTheme.primary)
            .widgetURL(URL(string: "blessingcircle://today/capture"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MannaWordmark(width: 58)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.hasSubmitted {
                        LiveActivityCountdownText(endsAt: context.state.endsAt)
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.hasSubmitted ? "Shared with \(context.attributes.circleName)" : "What feels like a blessing today?")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            } compactLeading: {
                MannaWordmark(width: 28)
            } compactTrailing: {
                if !context.state.hasSubmitted {
                    LiveActivityCountdownText(endsAt: context.state.endsAt)
                        .monospacedDigit()
                        .frame(width: 44)
                }
            } minimal: {
                MannaWordmark(width: 24)
            }
            .widgetURL(URL(string: "blessingcircle://today/capture"))
            .keylineTint(MannaWidgetTheme.primary)
        }
    }
}

private struct LiveActivityCountdownText: View {
    let endsAt: Date

    var body: some View {
        let now = Date.now
        Text(timerInterval: now...max(now, endsAt), countsDown: true)
    }
}
