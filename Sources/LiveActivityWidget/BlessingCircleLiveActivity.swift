import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BlessingCircleWidgetBundle: WidgetBundle {
    var body: some Widget {
        BlessingCircleLiveActivity()
    }
}

struct BlessingCircleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PromptActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: context.state.hasSubmitted ? "checkmark.circle.fill" : "circle.hexagongrid.fill")
                    .font(.title)
                    .foregroundStyle(context.state.hasSubmitted ? .green : .purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.circleName)
                        .font(.headline)
                    if context.state.hasSubmitted {
                        Text("Your blessing is shared")
                            .font(.subheadline)
                    } else {
                        Text(timerInterval: Date.now...context.state.endsAt, countsDown: true)
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.purple)
            .widgetURL(URL(string: "blessingcircle://today/capture"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .foregroundStyle(.purple)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.hasSubmitted {
                        Text(timerInterval: Date.now...context.state.endsAt, countsDown: true)
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.hasSubmitted ? "Shared with \(context.attributes.circleName)" : "What feels like a blessing today?")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.hasSubmitted ? "checkmark" : "circle.hexagongrid.fill")
                    .foregroundStyle(context.state.hasSubmitted ? .green : .purple)
            } compactTrailing: {
                if !context.state.hasSubmitted {
                    Text(timerInterval: Date.now...context.state.endsAt, countsDown: true)
                        .monospacedDigit()
                        .frame(width: 44)
                }
            } minimal: {
                Image(systemName: context.state.hasSubmitted ? "checkmark" : "circle.hexagongrid.fill")
                    .foregroundStyle(context.state.hasSubmitted ? .green : .purple)
            }
            .widgetURL(URL(string: "blessingcircle://today/capture"))
            .keylineTint(.purple)
        }
    }
}

